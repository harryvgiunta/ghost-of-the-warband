extends SceneTree
## Two real ENet processes: the host opens the town/frontier, a client joins it,
## and both peers see the same rangers, mobs, arrows and loot. The client sends
## movement/action intents; the host stays authoritative for seats and mobs.

const TRACE_PATH := "user://world_net_client_trace.txt"

var failures := 0
var checks := 0
var session
var game
var reports: Dictionary = {}
var child_pid := -1
var watch_index := -1

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WORLD_NET_FAIL  ",message)

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
	signal watched(index: int)
	@rpc("any_peer","call_remote","reliable")
	func submit(payload: Dictionary) -> void:
		submitted.emit(payload)
	@rpc("any_peer","call_remote","reliable")
	func watch(index: int) -> void:
		watched.emit(index)

func _store_report(payload: Dictionary) -> void:
	if payload.has("client_error"):
		reports["client_error"] = str(payload["client_error"])
	else:
		reports["world"] = payload

func _host_run() -> void:
	_clear_trace()
	var probe := PacketPeerUDP.new()
	check(probe.bind(0) == OK,"The fixture gets an available UDP port")
	var port := probe.get_local_port()
	probe.close()
	session.arm_world("world-host","127.0.0.1",port,"World host")
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	var report := Report.new()
	report.name = "WorldNetReport"
	report.submitted.connect(_store_report)
	root.add_child(report)
	var hosted := await _wait_until(func(): return game.network_role == "host",8.0)
	check(hosted,"The host opens the open world")
	check(game.get_human_count() == 1,"The host starts alone")
	check(str(game.hud._session.text).contains("OPEN WORLD"),"The host shows the session line")

	var child_args := PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),
		"--script",get_script().resource_path,"--","--world-client",str(port)])
	child_pid = OS.create_process(OS.get_executable_path(),child_args)
	check(child_pid > 0,"The client process starts")
	var joined := await _wait_until(func(): return game.get_human_count() == 2,20.0)
	check(joined,"A real ENet client joins the open world")
	if not joined:
		print("CLIENT_TRACE:\n",_read_trace())
		await _print_and_quit()
		return

	var seat = game._seats.get(1)
	check(seat != null and seat.alive and seat.visible,"The joining ranger is alive and visible on the host")
	check(seat != null and int(seat.peer_id) > 1,"The host seats the client on seat one")
	check(str(game.hud._session.text).contains("2 RANGERS"),"The host session line counts both rangers")
	var shared_targets := await _wait_until(func(): return game._enemies_by_index[0].targets.size() == 2,3.0)
	check(shared_targets,"Every mob targets both rangers")
	var armed := await _wait_until(func(): return str(game._seats[1].rig.weapon) == "sword",6.0)
	check(armed,"The client's weapon intent switches its host seat")

	var chosen_index := -1
	var chosen = null
	for index in game._enemies_by_index.size():
		var enemy = game._enemies_by_index[index]
		if not is_instance_valid(enemy) or not enemy.alive:
			continue
		if enemy.global_position.distance_to(game.player.global_position) > 55.0:
			continue
		chosen = enemy
		chosen_index = index
		break
	check(chosen != null,"A mob stands within replication range of the town")
	if chosen == null:
		await _print_and_quit()
		return
	chosen.take_damage(5.0,-1)
	var expected_health: float = chosen.health
	var host_clone = null
	for enemy in game._enemies_by_index:
		if int(enemy.get("kind")) == 8:
			host_clone = enemy
			break
	check(host_clone != null,"The frontier hosts ranger clones")
	if host_clone != null:
		host_clone.global_position = game.player.global_position + Vector3(-6.0,0.1,10.0)
		host_clone.home = host_clone.global_position
		host_clone.velocity = Vector3.ZERO
		host_clone.auto_ai = false
	game.player.global_position += Vector3(2.5,0.0,0.0)
	seat.global_position += Vector3(0.0,0.0,2.5)
	seat.take_damage(20.0,-1)
	check(seat.health < 99.9,"The host damages the client seat")
	var routed_health: float = seat.health
	game._on_enemy_attack(chosen,5.0,seat)
	check(seat.health < routed_health,"A mob strike routes to the client seat")
	game._spawn_loot("dagger_iron",game.player.global_position + Vector3(15.0,0.0,0.0),true)
	game._on_mob_arrow(game.player.global_position + Vector3(0.0,1.5,0.0),Vector3(0.0,0.0,1.0),30.0,5.0)
	game.take_damage(12.0,false)
	await create_timer(0.7).timeout

	report.watch.rpc_id(int(seat.peer_id),chosen_index)
	var jumped := await _wait_until(func(): return game._seats[1].velocity.y > 0.3 or not game._seats[1].is_on_floor(),4.0)
	check(jumped,"The client's jump intent moves its host-authoritative ranger")
	var swung := await _wait_until(func(): return str(game._seats[1].rig.phase).begins_with("MELEE"),4.0)
	check(swung,"The client's melee intent starts the host-authoritative swing")
	var reported := await _wait_until(func(): return reports.has("world") or reports.has("client_error"),15.0)
	if reports.has("client_error"):
		check(false,"Client reported an error: " + str(reports["client_error"]))
		print("CLIENT_TRACE:\n",_read_trace())
	check(reported,"The client reports replicated state")
	if reports.has("world"):
		var data: Dictionary = reports["world"]
		check(int(data.get("slot",0)) == 1,"The client owns seat one")
		var seats: Array = data.get("seats",[])
		check(seats.size() == 2 and seats.has(0) and seats.has(1),"Both rangers exist on the client")
		check(str(data.get("hud","")).contains("OPEN WORLD"),"The client shows the session line")
		var host_pos: Vector3 = data.get("host_pos",Vector3.ZERO)
		check(host_pos.distance_to(game.player.global_position) < 0.8,"The client renders the host ranger at the host position")
		var own_pos: Vector3 = data.get("own_pos",Vector3.ZERO)
		check(own_pos.distance_to(game._seats[1].global_position) < 0.8,"The client's own ranger follows the host seat")
		check(float(data.get("health",100.0)) < 99.9,"The client sees its authoritative health drop")
		check(float(data.get("enemy_health",-1.0)) <= expected_health + 0.2,"The client sees the damaged mob's health")
		check(bool(data.get("enemy_alive",false)),"The damaged mob is still alive on the client")
		check(float(data.get("enemy_time",0.0)) > 0.0,"The client runs the replicated mob clock")
		check(int(data.get("loot",0)) >= 1,"The client spawns the host's dropped loot")
		check(int(data.get("arrows",0)) >= 1,"The client renders the host's mob arrow")
		check(bool(data.get("replicas",false)),"Every client mob is a host-driven replica")
		check(int(data.get("clone_count",0)) == 4,"The client builds all four ranger clones")
		check(bool(data.get("clone_replica",false)),"Clones are host-driven replicas on the client")
		var clone_pos: Vector3 = data.get("clone_pos",Vector3.ZERO)
		if host_clone != null:
			check(clone_pos.distance_to(host_clone.global_position) < 0.8,"The client follows the host clone position (%s vs %s)" % [clone_pos,host_clone.global_position])
		check(str(data.get("weapon","")) == "sword","The client sees its replicated sword")
		var prediction: Dictionary = data.get("prediction",{})
		check(bool(prediction.get("predicting",false)),
			"The open-world client owns and predicts its own ranger")
		check(int(prediction.get("first_move",99)) <= 2,
			"The open-world ranger moves on the frame its key went down")
		check(float(prediction.get("walked",0.0)) > 0.5,
			"The predicted open-world ranger really moved")
		check(float(prediction.get("worst_step",99.0)) < 0.30,
			"The open-world prediction never jumps (%s)" % str(prediction.get("worst_step")))
		check(int(prediction.get("acked",-1)) > 0,
			"The host acknowledges the open-world client's frames")
		print("WORLD_PRED_KEYS health=",data.get("health")," weapon=",data.get("weapon"),
			" host_health=",data.get("host_health")," own_pos=",data.get("own_pos"))
		var seat_one = game._seats.get(1)
		print("WORLD_PRED_DIAG client=",prediction," host ack=",
			seat_one.ack_seq if is_instance_valid(seat_one) else "none",
			" pending=",seat_one._pending_seq if is_instance_valid(seat_one) else "none",
			" age=",seat_one.input_age if is_instance_valid(seat_one) else "none",
			" authoritative=",seat_one.authoritative if is_instance_valid(seat_one) else "none")
		check(float(data.get("host_health",100.0)) < 99.9,"The client sees the host ranger's damaged health")

	var left := await _wait_until(func(): return game.get_human_count() == 1,10.0)
	check(left,"The host frees the seat when the client leaves")
	check(not game._seats.has(1),"The departing ranger node is removed")
	await _print_and_quit()

func _print_and_quit() -> void:
	if child_pid > 0 and OS.is_process_running(child_pid):
		OS.kill(child_pid)
	if game != null:
		game._close_network()
		game.queue_free()
	await process_frame
	_clear_trace()
	print("WORLD_NETWORK_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func _on_watch(index: int) -> void:
	watch_index = index

func _client_run(port: int) -> void:
	session.arm_world("world-join","127.0.0.1",port,"World client")
	var report := Report.new()
	report.name = "WorldNetReport"
	report.watched.connect(_on_watch)
	root.add_child(report)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	_trace("client scene added")
	var joined := await _wait_until(func(): return game.local_slot == 1,15.0)
	_trace("joined=" + str(joined) + " slot=" + str(game.local_slot))
	if not joined:
		report.submit.rpc_id(1,{"client_error":"join timeout"})
		await _finish_client(1)
		return
	print("WORLD_NET_CLIENT joined slot=",game.local_slot)
	var seated := await _wait_until(func(): return game._seats.has(0) and game._seats.has(1),8.0)
	if not seated:
		report.submit.rpc_id(1,{"client_error":"seat replication timeout"})
		await _finish_client(1)
		return
	game.send_action("weapon","sword")
	await create_timer(0.2).timeout
	var deadline := Time.get_ticks_msec() + 20000
	while watch_index < 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	if watch_index < 0:
		report.submit.rpc_id(1,{"client_error":"probe timeout"})
		await _finish_client(1)
		return

	# Prediction: the joined ranger must move on the frame its key goes down,
	# before any round trip, and stay smooth afterwards.
	var own_seat = game._seats.get(game.local_slot)
	var corrections_before: int = own_seat.prediction_corrections if own_seat != null else 0
	var walk_before: Vector3 = game.player.global_position
	var steps: Array = []
	var first_move := -1
	var hold := InputEventKey.new()
	hold.keycode = KEY_D
	hold.physical_keycode = KEY_D
	hold.pressed = true
	Input.parse_input_event(hold)
	Input.flush_buffered_events()
	for index in 40:
		await physics_frame
		steps.append(game.player.global_position)
		if first_move < 0 and steps.size() > 1 and (steps[-1] as Vector3).distance_to(steps[0]) > 0.008:
			first_move = steps.size() - 1
	var release := InputEventKey.new()
	release.keycode = KEY_D
	release.physical_keycode = KEY_D
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	var worst_step := 0.0
	for index in range(1,steps.size()):
		worst_step = maxf(worst_step,(steps[index] as Vector3).distance_to(steps[index-1]))
	# The frontier host simulates every mob in the valley, so give its
	# acknowledgement time to land instead of measuring only the walk's window.
	var ack_deadline := Time.get_ticks_msec() + 3000
	while own_seat != null and int(own_seat._prediction.acked) < 0 \
			and Time.get_ticks_msec() < ack_deadline:
		await process_frame
	var prediction := {
		"predicting":bool(own_seat.predicting) if own_seat != null else false,
		"first_move":first_move,
		"walked":game.player.global_position.distance_to(walk_before),
		"worst_step":worst_step,
		"acked":int(own_seat._prediction.acked) if own_seat != null else -1,
		"corrections":(own_seat.prediction_corrections-corrections_before) if own_seat != null else -1,
	}
	_trace("prediction " + str(prediction))
	var jump := InputEventKey.new()
	jump.keycode = KEY_SPACE
	jump.physical_keycode = KEY_SPACE
	jump.pressed = true
	Input.parse_input_event(jump)
	Input.flush_buffered_events()
	var jump_up := InputEventKey.new()
	jump_up.keycode = KEY_SPACE
	jump_up.physical_keycode = KEY_SPACE
	jump_up.pressed = false
	Input.parse_input_event(jump_up)
	Input.flush_buffered_events()
	_trace("client jumped via Space")
	await create_timer(1.6).timeout
	game.send_action("melee",{"hand":"right","variant":"diagonal_right","aim":game.player.global_position + Vector3(0.0,1.2,5.0)})
	await create_timer(0.35).timeout
	var seats: Array = []
	for slot in game._seats.keys():
		seats.append(int(slot))
	seats.sort()
	var enemy = game._enemies_by_index[watch_index] if watch_index < game._enemies_by_index.size() else null
	var replicas := true
	var clone_replica = null
	var clone_count := 0
	for entry in game._enemies_by_index:
		if not bool(entry.replica):
			replicas = false
		if int(entry.get("kind")) == 8:
			clone_count += 1
			if clone_replica == null:
				clone_replica = entry
	var payload := {"world":true,"slot":game.local_slot,"seats":seats,"prediction":prediction,
		"host_pos":game._seats[0].global_position if game._seats.has(0) else Vector3.ZERO,
		"own_pos":game.player.global_position,"health":game.health,
		"enemy_health":float(enemy.health) if enemy != null else -1.0,
		"enemy_alive":bool(enemy.alive) if enemy != null else false,
		"enemy_time":float(enemy._state_time) if enemy != null else 0.0,
		"loot":game.loot_pickups.size(),"arrows":game.arrows.size(),
		"replicas":replicas,"hud":str(game.hud._session.text),
		"weapon":str(game._seats[1].rig.weapon),
		"clone_count":clone_count,
		"clone_replica":bool(clone_replica.replica) if clone_replica != null else false,
		"clone_pos":clone_replica.global_position if clone_replica != null else Vector3.ZERO,
		"host_health":float(game._seats[0].health)}
	print("WORLD_NET_CLIENT report slot=",game.local_slot," health=",game.health," loot=",game.loot_pickups.size())
	report.submit.rpc_id(1,payload)
	await create_timer(0.5).timeout
	await _finish_client(0)

func _finish_client(code: int) -> void:
	if game != null:
		game._close_network()
		game.queue_free()
	await process_frame
	quit(code)

func run() -> void:
	session = root.get_node_or_null("Session")
	check(session != null,"The Session autoload exists")
	var args := OS.get_cmdline_user_args()
	if args.has("--world-client"):
		await _client_run(int(args[args.find("--world-client") + 1]))
	else:
		await _host_run()
