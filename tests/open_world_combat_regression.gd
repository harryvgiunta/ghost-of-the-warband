extends SceneTree
## Two real ENet processes on a simulated 80 ms ± 15 ms link: the host opens the
## open world, a client joins it, walks, then fights a mob under its reported
## crosshair **while moving** — the shape of the failing report (the joining
## ranger vanished and the view shook the moment it attacked).
##
## It checks what a player can see and what the session owes them:
##
##   * the model never moves faster than a walk plus the correction glide,
##   * the third-person boom never zooms faster than `CAMERA_BOOM_IN`/`_OUT`,
##   * the ranger's body is never launched (the reported 3.5–4.4 m teleports),
##   * its rig is never hidden while it is alive,
##   * its prediction settles instead of correcting on every packet,
##   * the authority consumes the frames it is sent (bounded input queue and
##     unacknowledged window), both peers agree where the ranger stands, and
##   * swings aimed at a mob under the crosshair damage that mob.
##
## The link is simulated because 0.1 ms on localhost hides exactly these
## defects: the past and the present are the same frame.

const TRACE_PATH := "user://open_world_combat_trace.txt"
## One-way delay and its spread, in milliseconds, applied to both peers.
const LINK_MS := 80.0
const LINK_JITTER_MS := 15.0
## The model is drawn at most `RIG_DRAW_STEP` (0.35 m) from where it was in a
## frame; the reported defect moved it metres.
const MAX_RIG_STEP := 0.40
## And it may never trail its body further than a glide: the report was the
## guest's own view snapping back to where it last stood (a stale anchor after a
## death), so the model has to stay attached to the body it belongs to.
const RIG_TRAIL_LIMIT := 2.7
## While a swing plays, the pelvis is pinned to a planted stance that is
## captured in world space; it must be the stance under the body, not an old one.
const MELEE_HIPS_LIMIT := 1.2
## The boom zooms at a bounded speed, so one frame can only shorten it by what
## that frame lasted. A stalled frame is allowed more than a smooth one; the
## defect this catches snapped 4–8 m.
const MAX_BOOM_STEP := 3.0
## A body may take the authority's verdict in one frame, but the reported defect
## launched it metres. Two strides plus a correction is the ceiling.
const MAX_FRAME_STEP := 1.6
## Corrections are for disagreement, not for phase.
const MAX_CORRECTION_SHARE := 0.25
## Frames the client may be ahead of the authority's acknowledgement.
const MAX_UNACKED_FRAMES := 30
## Positions the two peers report for the same ranger must agree this closely.
const POSITION_AGREEMENT := 1.2
## Free-standing mobs the joining ranger must kill, counted on the host.
const KILL_TARGET := 3

var failures := 0
var checks := 0
var session
var game
var reports: Dictionary = {}
var child_pid := -1
var fight_started := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("OPEN_WORLD_COMBAT_FAIL  ",message)

func _trace(message: String) -> void:
	var file := FileAccess.open(TRACE_PATH,FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(TRACE_PATH,FileAccess.WRITE)
	else:
		file.seek_end()
	if file != null:
		file.store_line(message)
		file.close()

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

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _click() -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()

class Report:
	extends Node
	signal submitted(kind: String, payload: Dictionary)
	signal go()
	@rpc("any_peer","call_remote","reliable")
	func submit(kind: String, payload: Dictionary) -> void:
		submitted.emit(kind,payload)
	@rpc("authority","call_remote","reliable")
	func start_fight() -> void:
		go.emit()

func _host_run() -> void:
	_clear_trace()
	var probe := PacketPeerUDP.new()
	check(probe.bind(0) == OK,"The fixture gets an available UDP port")
	var port := probe.get_local_port()
	probe.close()
	session.arm_world("world-host","127.0.0.1",port,"World host")
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	# The host's half of the simulated link. The client is launched with the same
	# flag, so both directions carry a Tailscale-shaped delay and jitter.
	# `--link-ms`/`--link-jitter` override the simulated link, so the same
	# scenario can be run at the 0.1 ms a localhost pair really has.
	var args := OS.get_cmdline_user_args()
	var link_ms := LINK_MS
	var link_jitter := LINK_JITTER_MS
	if args.has("--link-ms"):
		link_ms = float(args[args.find("--link-ms") + 1])
	if args.has("--link-jitter"):
		link_jitter = float(args[args.find("--link-jitter") + 1])
	game._link.configure(link_ms/1000.0,link_jitter/1000.0)
	var report := Report.new()
	report.name = "CombatReport"
	report.submitted.connect(func(kind: String,payload: Dictionary):
		reports[kind] = payload)
	root.add_child(report)
	check(await _wait_until(func(): return game.network_role == "host",8.0),
		"The host opens the open world")
	if link_ms > 0.0:
		check(float(game._link.lag) > 0.0,"The host runs the simulated link")
	var child_args := PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),
		"--script",get_script().resource_path,"--","--world-client",str(port),
		"--net-lag",str(int(link_ms)),"--net-jitter",str(int(link_jitter))])
	child_pid = OS.create_process(OS.get_executable_path(),child_args)
	check(child_pid > 0,"The client process starts")
	var joined := await _wait_until(func(): return game.get_human_count() == 2,25.0)
	check(joined,"A real ENet client joins the open world")
	if not joined:
		print("CLIENT_TRACE:\n",FileAccess.get_file_as_string(TRACE_PATH))
		await _print_and_quit()
		return
	var seat = game._seats.get(1)
	check(seat != null,"The host seats the joining ranger")
	if seat == null:
		await _print_and_quit()
		return
	check(seat.alive and seat.visible,"The joining ranger is alive and visible on the host")

	# The joining ranger now hunts the frontier's own free-standing mobs: no
	# fixture places anything, and the host is the one that counts the kills.
	report.start_fight.rpc_id(int(seat.peer_id))
	var queue_peak := 0
	var dead_at := {}
	var killed_at := Vector3.ZERO
	var killed_once := false
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 62000 and not reports.has("done"):
		await physics_frame
		queue_peak = maxi(queue_peak,seat._input_queue.size())
		if not killed_once and Time.get_ticks_msec() - start > 15000 and seat.alive:
			# Die out in the field. The reported symptom is the guest's own view
			# snapping back to where it last stood, so a real death away from the
			# revive point is part of the scenario.
			killed_once = true
			killed_at = seat.global_position
			seat.take_damage(seat.max_health + 25.0,-1)
		for index in game._enemies_by_index.size():
			var enemy = game._enemies_by_index[index]
			if not is_instance_valid(enemy) or dead_at.has(index):
				continue
			if enemy.alive:
				continue
			dead_at[index] = str(enemy.name)
	check(queue_peak <= 12,"The host's input queue stays small (%d frames)" % queue_peak)

	await _wait_until(func(): return reports.has("done"),12.0)
	check(reports.has("done"),"The client reports its own findings")
	if reports.has("done"):
		var data: Dictionary = reports["done"]
		check(not data.has("join_failed") and not data.has("seat_failed") and not data.has("fight_failed"),
			"The client reached the hunt (%s)" % str(data.keys()))
		check(int(data.get("hidden_frames",99)) == 0,
			"Its rig is never hidden while it is alive (%d frames)" % int(data.get("hidden_frames",-1)))
		var rig_step: float = float(data.get("rig_step",999.0))
		check(rig_step <= MAX_RIG_STEP,
			"The ranger's model never teleports (%s m in one frame)" % str(rig_step))
		var trail: float = float(data.get("rig_trail",999.0))
		check(trail <= RIG_TRAIL_LIMIT,
			"The ranger's model is never left standing somewhere else (%s m behind the body at frame %s)"
				% [str(trail),str(data.get("rig_trail_frame",-1))])
		var melee_trail: float = float(data.get("melee_trail",999.0))
		check(melee_trail <= MELEE_HIPS_LIMIT,
			"A swing keeps the hips on the body (%s m away at frame %s)"
				% [str(melee_trail),str(data.get("melee_trail_frame",-1))])
		var boom_step: float = float(data.get("boom_step",999.0))
		check(boom_step <= MAX_BOOM_STEP,
			"The camera never snaps its boom (%s m in one frame)" % str(boom_step))
		var worst: float = float(data.get("worst_step",99.0))
		check(worst <= MAX_FRAME_STEP,
			"The ranger's body is never launched (%s m in one frame)" % str(worst))
		var frames: int = int(data.get("frames",0))
		var corrections: int = int(data.get("corrections",999))
		check(frames > 240,"The client measured a real run (%d frames)" % frames)
		check(corrections <= int(maxf(4.0,float(frames)*MAX_CORRECTION_SHARE)),
			"Its prediction settles instead of correcting on every packet (%d of %d frames)"
				% [corrections,frames])
		var unacked: int = int(data.get("ring_next",9999)) - int(data.get("ring_acked",0))
		check(unacked <= MAX_UNACKED_FRAMES,
			"The unacknowledged window stays bounded (%d frames)" % unacked)
		check(int(data.get("swings",0)) > 0,"The joining ranger really swung")
		var own: Vector3 = data.get("own_pos",Vector3.ZERO)
		check(own.distance_to(seat.global_position) <= POSITION_AGREEMENT,
			"Both peers agree where the joining ranger stands (%s vs %s)"
				% [str(own),str(seat.global_position)])
		print("OPEN_WORLD_COMBAT_PRED rig_step=",rig_step," boom_step=",boom_step,
			" worst_step=",worst," corrections=",corrections," frames=",frames," unacked=",unacked,
			" swings=",int(data.get("swings",0)))
	check(killed_once,"The guest was killed out in the field during the hunt")
	check(seat.alive and seat.global_position.distance_to(killed_at) > 5.0,
		"The host revived it away from where it fell (%s vs %s)"
			% [str(seat.global_position),str(killed_at)])
	check(dead_at.size() >= KILL_TARGET,
		"The host sees the joining ranger kill at least %d free-standing mobs (it saw %d: %s)"
			% [KILL_TARGET,dead_at.size(),str(dead_at.values())])
	print("OPEN_WORLD_COMBAT_KILLS dead=",dead_at.size()," ",dead_at.values(),
		" seat_hp=",seat.health," seat_kills=",seat.kills)
	await _print_and_quit()

func _print_and_quit() -> void:
	if child_pid > 0 and OS.is_process_running(child_pid):
		OS.kill(child_pid)
	if game != null:
		game._close_network()
		game.queue_free()
	await process_frame
	_clear_trace()
	print("OPEN_WORLD_COMBAT_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func _client_run(port: int) -> void:
	session.arm_world("world-join","127.0.0.1",port,"World client")
	var report := Report.new()
	report.name = "CombatReport"
	root.add_child(report)
	report.go.connect(func(): fight_started = true)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	_trace("client scene added lag=%s" % str(game._link.lag))
	var joined := await _wait_until(func(): return game.local_slot == 1,20.0)
	_trace("joined=%s slot=%s" % [str(joined),str(game.local_slot)])
	if not joined:
		report.submit.rpc_id(1,"done",{"join_failed":true})
		await _finish(1)
		return
	var seated := await _wait_until(func(): return game._seats.has(0) and game._seats.has(1),10.0)
	if not seated:
		report.submit.rpc_id(1,"done",{"seat_failed":true})
		await _finish(1)
		return
	game.send_action("weapon","sword")
	await create_timer(0.3).timeout
	var seat = game._seats.get(game.local_slot)
	var frames := 0
	var hidden_frames := 0
	var previous: Vector3 = game.player.global_position
	var previous_rig: Vector3 = seat.rig.global_position
	var swings := 0
	var started := Time.get_ticks_msec()
	_trace("phase walk")
	# Stage one: a real walk on real key events.
	var corrections_before: int = seat.prediction_corrections
	_key(KEY_D,true)
	var walk_frames := 0
	var walk_start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - walk_start < 1200:
		await physics_frame
		frames += 1
		walk_frames += 1
		previous = game.player.global_position
		if not seat.rig.visible or not seat.alive:
			hidden_frames += 1
	_key(KEY_D,false)
	var walk_corrections: int = seat.prediction_corrections - corrections_before
	_trace("walk frames=%d corrections=%d" % [walk_frames,walk_corrections])
	var go := await _wait_until(func(): return fight_started,30.0)
	if not go:
		_trace("no fight start")
		report.submit.rpc_id(1,"done",{"fight_failed":true})
		await _finish(1)
		return
	_trace("phase hunt")
	# Stage two: hunt the frontier's own free-standing mobs while moving — past
	# the court, out where the mobs hit back and shove. A real key is held, the
	# mouse is clicked, and the quarry is tracked at a mouse-like turn rate;
	# model, camera boom and body are measured apart.
	var worst_step := 0.0
	var rig_step := 0.0
	var boom_step := 0.0
	var previous_boom: float = game.camera.global_position.distance_to(game.camera_focus)
	previous_rig = seat.rig.global_position
	var rig_trail := 0.0
	var rig_trail_frame := 0
	var melee_trail := 0.0
	var melee_trail_frame := 0
	var transition_grace := 0
	var was_alive: bool = seat.alive
	var walking: bool = false
	var kills_before: int = _dead_replicas()
	var hunt_start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - hunt_start < 45000:
		await physics_frame
		frames += 1
		var point: Vector3 = game.player.global_position
		var rig_point: Vector3 = seat.rig.global_position
		var boom: float = game.camera.global_position.distance_to(game.camera_focus)
		# A death hides the model for the host's three-second respawn and the
		# revive is a teleport to the gate: both are legitimate. Everything else
		# is measured: what must never happen is a model left standing at an old
		# corpse, or a body launched across the map.
		var alive_now: bool = seat.alive
		if alive_now != was_alive:
			transition_grace = 40
			was_alive = alive_now
		if transition_grace > 0:
			transition_grace -= 1
		# A swing pins the pelvis and both ankles to a planted stance; that
		# stance is captured in world space, so a replica that never re-captures
		# it keeps its hips at the spot of its first swing for the whole session.
		if seat.rig.is_melee():
			var pelvis: Vector3 = seat.rig._bone_world(seat.rig._bones.pelvis).origin
			var hips := pelvis-point
			hips.y = 0.0
			if hips.length() > melee_trail:
				melee_trail = hips.length()
				melee_trail_frame = frames
		if alive_now and transition_grace <= 0:
			worst_step = maxf(worst_step,point.distance_to(previous))
			if seat.rig.visible:
				rig_step = maxf(rig_step,rig_point.distance_to(previous_rig))
				var trail_now: float = rig_point.distance_to(point)
				if trail_now > rig_trail:
					rig_trail = trail_now
					rig_trail_frame = frames
			else:
				hidden_frames += 1
		previous = point
		previous_rig = rig_point
		boom_step = maxf(boom_step,absf(boom-previous_boom))
		previous_boom = boom
		# The nearest living mob is the quarry.
		var quarry = null
		var closest := 1e9
		for enemy in game._enemies_by_index:
			if not is_instance_valid(enemy) or not enemy.alive:
				continue
			var gap: float = enemy.global_position.distance_to(point)
			if gap < closest:
				closest = gap
				quarry = enemy
		if quarry == null:
			break
		var toward: Vector3 = quarry.global_position - point
		toward.y = 0.0
		var gap := toward.length()
		if gap > 0.05:
			toward = toward.normalized()
			var wanted := atan2(-toward.x,-toward.z)
			game.camera_yaw += clampf(wrapf(wanted-game.camera_yaw,-PI,PI),-0.12,0.12)
			game.camera_pitch = 0.0
		# Walk in, then stand and swing: what a player does with a sword.
		var should_walk: bool = gap > 2.3 and seat.alive
		if should_walk != walking:
			_key(KEY_W,should_walk)
			walking = should_walk
		if frames % 14 == 0:
			game.update_crosshair_aim()
			_click()
			swings += 1
	if walking:
		_key(KEY_W,false)
	_trace("submitting frames=%d swings=%d dead=%d (was %d)" % [frames,swings,_dead_replicas(),kills_before])
	report.submit.rpc_id(1,"done",{
		"frames":frames,"walk_frames":walk_frames,"walk_corrections":walk_corrections,
		"hidden_frames":hidden_frames,"worst_step":worst_step,"swings":swings,
		"rig_step":rig_step,"boom_step":boom_step,
		"rig_trail":rig_trail,"rig_trail_frame":rig_trail_frame,
		"melee_trail":melee_trail,"melee_trail_frame":melee_trail_frame,
		"corrections":seat.prediction_corrections,
		"alive":seat.alive,"visible":seat.rig.visible,
		"own_pos":game.player.global_position,
		"ring_next":seat._prediction.next_seq,"ring_acked":int(seat._prediction.acked),
		"health":game.health})
	_trace("submitted")
	await create_timer(0.4).timeout
	await _finish(0)

## Mobs the replicated world reports dead: the guest's own view of the hunt.
func _dead_replicas() -> int:
	var dead := 0
	for enemy in game._enemies_by_index:
		if is_instance_valid(enemy) and not enemy.alive:
			dead += 1
	return dead

func _finish(code: int) -> void:
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
