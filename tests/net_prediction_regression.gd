extends SceneTree
## Client-side prediction, server reconciliation, buffered entity interpolation
## and backward reconciliation (lag compensation).
##
## The pure half drives the real primitives: the input ring that a correction
## replays, the snapshot timeline that smooths uneven arrivals and dead-reckons
## a starved buffer, and the one-second hitbox history the host rewinds. The
## live half joins a real ENet client to a real host and measures what a player
## feels: the body moves on the key press, steady walking needs no corrections,
## the host's fighter is rendered smoothly, and a host-side shove is reconciled
## away instead of rubber-banding.

const NetReplication = preload("res://scripts/net_replication.gd")
const LagCompensation = preload("res://scripts/lag_compensation.gd")

var failures := 0
var checks := 0
var arena
var report
var children: Array[int] = []
var walk_metrics: Dictionary = {}
var shove_metrics: Dictionary = {}


class Report:
	extends Node
	var command := 0
	var messages: Dictionary = {}

	@rpc("authority","call_local","reliable")
	func stage(id: int) -> void:
		command = id

	@rpc("any_peer","call_remote","reliable")
	func result(label: String, payload: Dictionary) -> void:
		messages[label] = payload


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("NET_PREDICTION_FAIL  ",message)


func _initialize() -> void:
	call_deferred("run")


func pause(seconds: float) -> void:
	await create_timer(seconds).timeout


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _max_step(points: Array) -> float:
	var worst := 0.0
	for index in range(1,points.size()):
		worst = maxf(worst,(points[index] as Vector3).distance_to(points[index-1]))
	return worst


func _travel(points: Array) -> float:
	if points.size() < 2:
		return 0.0
	return (points[-1] as Vector3).distance_to(points[0])


## -- pure primitives -----------------------------------------------------


func input_ring_checks() -> void:
	var ring = NetReplication.InputRing.new()
	check(ring.push({"delta":1.0/60.0,"dir":Vector2.ZERO}) == 0,"The first recorded frame is sequence zero")
	ring.push({"delta":1.0/60.0,"dir":Vector2.RIGHT})
	ring.push({"delta":1.0/60.0,"dir":Vector2.RIGHT})
	check(ring.latest_seq() == 2,"Every frame gets the next sequence number")
	check(ring.after(0).size() == 2,"A replay covers every frame recorded after the acknowledgement")
	check(int(ring.after(0)[0].seq) == 1,"The replay keeps frame order")
	ring.acknowledge(1)
	check(ring.size() == 1 and int(ring.records[0].seq) == 2,"Acknowledged frames are dropped, later frames are kept")
	check(ring.after(1).size() == 1,"Only unacknowledged frames replay")
	ring.acknowledge(9)
	check(ring.size() == 0,"Acknowledge past the newest frame empties the history")
	for index in 260:
		ring.push({"delta":1.0/60.0,"dir":Vector2.ZERO})
	check(ring.size() == NetReplication.InputRing.LIMIT,"The movement history is bounded")
	check(int(ring.after(-1)[0].seq) == ring.latest_seq() - ring.size() + 1,"A trimmed ring still replays contiguously")


func timeline_checks() -> void:
	var timeline = NetReplication.SnapshotTimeline.new()
	timeline.configure(60.0)
	var arrival := 10.0
	check(timeline.push(100,Vector3.ZERO,Vector3.ZERO,0.0,arrival),"The first server state is accepted")
	arrival += 0.05
	check(timeline.push(103,Vector3(0,0,1.5),Vector3(0,0,30),0.0,arrival),"A newer state is accepted")
	check(not timeline.push(103,Vector3(0,0,9),Vector3.ZERO,0.0,arrival),"A repeated tick cannot move the body")
	check(not timeline.push(96,Vector3(0,0,9),Vector3.ZERO,0.0,arrival),"A stale tick cannot rewind the body")
	check(timeline.newest_tick() == 103,"The newest tick is the one rendered timeline anchor")
	var start := timeline.render_tick()
	check(start < 103.0,"Rendering starts behind the newest state")
	timeline.advance(0.1)
	check(timeline.render_tick() > start,"The playout clock advances with the render frame")

	timeline.playout = 101.5
	var middle: Dictionary = timeline.sample()
	check(middle.pos.z > 0.6 and middle.pos.z < 0.9,"Two known states interpolate between each other")
	check(not middle.extrapolated,"A covered playout never guesses")

	timeline.playout = 112.0
	var starved: Dictionary = timeline.sample()
	var ceiling: float = 1.5 + 30.0 * NetReplication.SnapshotTimeline.EXTRAPOLATION_TICKS * float(timeline.tick_seconds)
	check(starved.extrapolated,"An empty buffer dead-reckons")
	check(starved.pos.z > 1.5 and starved.pos.z <= ceiling + 0.001,
		"Dead reckoning follows the last velocity and stops at the bound")

	var restarted := int(timeline.restarts)
	arrival += 0.05
	timeline.push(104,Vector3(40,0,0),Vector3.ZERO,0.0,arrival)
	check(timeline.samples.size() == 1 and timeline.restarts == restarted + 1,
		"A teleport restarts the buffer instead of sliding the body across the gap")

	# Irregular arrivals widen the delay instead of being smoothed over silently.
	var jittered = NetReplication.SnapshotTimeline.new()
	jittered.configure(60.0)
	var now := 0.0
	for index in 12:
		now += 0.0333 + (0.035 if index % 2 == 0 else -0.015)
		jittered.push(index * 2,Vector3.ZERO,Vector3.ZERO,0.0,now)
	check(jittered.delay_ticks > NetReplication.SnapshotTimeline.MIN_DELAY_TICKS,
		"Irregular arrival spacing raises the playout delay")
	check(jittered.delay_ticks <= NetReplication.SnapshotTimeline.MAX_DELAY_TICKS,"The playout delay stays inside its clamp")

	# A stream with no velocity field still dead-reckons from its own motion.
	var implied = NetReplication.SnapshotTimeline.new()
	implied.configure(60.0)
	implied.push(0,Vector3.ZERO,Vector3.ZERO,0.0,0.0)
	implied.push(3,Vector3(0,0,0.3),Vector3.ZERO,0.0,0.05)
	implied.playout = 6.0
	var guessed: Dictionary = implied.sample()
	check(guessed.pos.z > 0.3,"A stream without velocities extrapolates the distance it covered")


func lag_history_checks() -> void:
	var body := CharacterBody3D.new()
	body.collision_layer = 4
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	var collider := CollisionShape3D.new()
	collider.position.y = 0.9
	collider.shape = capsule
	body.add_child(collider)
	root.add_child(body)
	var history = LagCompensation.new()
	body.global_position = Vector3(0,0,0)
	history.record(100,[body])
	body.global_position = Vector3(0,0,4)
	history.record(105,[body])
	body.global_position = Vector3(0,0,8)
	history.record(110,[body])
	check(history.latest_tick() == 110 and history.oldest_tick() == 100,"The history records one frame per tick")
	var volume: Dictionary = history.capsule_at(body.get_instance_id(),105)
	check((volume.a as Vector3).is_equal_approx(Vector3(0,0.3,4))
		and (volume.b as Vector3).is_equal_approx(Vector3(0,1.5,4)),
		"The recorded capsule is the body's own collision shape at that tick")
	check(is_equal_approx(float(volume.radius),0.3),"The recorded capsule keeps its radius")
	check(history.position_at(body.get_instance_id(),107).is_equal_approx(Vector3(0,0,4)),
		"A frame lookup returns the newest pose at or before the tick")
	check(history.position_at(-12345,105).is_equal_approx(Vector3.INF),"An unrecorded body has no pose")

	var blade_from := Vector3(-2,1.0,2.0)
	var blade_to := Vector3(2,1.0,6.0)
	check(history.segment_hits(body.get_instance_id(),105,blade_from,blade_to,0.02),
		"A swept segment finds the historical capsule")
	check(not history.segment_hits(body.get_instance_id(),110,blade_from,blade_to,0.02),
		"The same segment misses the present pose")
	check(history.sphere_hits(body.get_instance_id(),105,Vector3(0,1.0,5.0),1.0),
		"A blast reaches the historical capsule")
	check(not history.sphere_hits(body.get_instance_id(),110,Vector3(0,1.0,5.0),1.0),
		"The same blast misses the present pose")
	check(history.refuses(body.get_instance_id(),105,Vector3(0,1.0,6.0),Vector3(0,1.0,9.0),0.02),
		"A contact the shooter's frame cannot explain is refused")
	check(not history.refuses(body.get_instance_id(),110,Vector3(0,1.0,6.0),Vector3(0,1.0,9.0),0.02),
		"A contact the present pose explains is allowed")

	for tick in range(111,200):
		history.record(tick,[body])
	check(history.oldest_tick() >= 199 - LagCompensation.MAX_HISTORY_TICKS,
		"The history is pruned to its one second window")
	check(history.frames.size() <= LagCompensation.MAX_FRAMES,"The frame buffer is bounded")
	history.clear()
	check(history.frames.is_empty() and history.latest_tick() < 0,"Clearing the history empties it")
	body.queue_free()


## -- live arena ----------------------------------------------------------


func _arm_actor(actor, lag: int) -> void:
	actor.combat.lag_tick = int(arena._lag.latest_tick())
	actor.combat.lag_ticks = lag


func lag_rewind_checks() -> void:
	# Real bodies in a real arena: the victim leaves the strike area between the
	# tick a client acted on and the tick the host resolves it.
	var attacker = arena.actors[0]
	var victim = arena.actors[1]
	for actor in arena.actors:
		actor.is_bot = false
		actor.combat.stop()
		actor.combat.stop_block()
		actor.velocity = Vector3.ZERO
	attacker.position = Vector3(0,0.05,0)
	victim.position = Vector3(0,0.05,1.2)
	arena.actors[2].position = Vector3(18,0.05,18)
	arena.actors[3].position = Vector3(21,0.05,21)
	await pause(0.3)
	var seen: int = arena._lag.latest_tick()
	var recorded: Vector3 = arena._lag.position_at(victim.get_instance_id(),seen)
	check(recorded.distance_to(victim.position) < 0.5,
		"The history recorded the victim where it stood (%s vs %s)" % [recorded,victim.position])
	victim.position = Vector3(0,0.05,7.5)
	await pause(0.15)
	var lag: int = arena._lag.latest_tick() - seen
	check(lag > 0,"The history covers the ticks a client was looking at")
	var historical_tick: int = arena._lag.latest_tick() - lag
	check(arena._lag.sphere_hits(victim.get_instance_id(),historical_tick,Vector3(0,1.0,0),2.2),
		"The rewound capsule is inside the strike")
	check(not arena._lag.sphere_hits(victim.get_instance_id(),arena._lag.latest_tick(),Vector3(0,1.0,0),2.2),
		"The present capsule is out of reach")

	_arm_actor(attacker,lag)
	var before: float = victim.health
	attacker.combat.ability_strike(2.2,360.0,10.0,0.0,true,false)
	check(victim.health < before - 9.9,"A strike judged at the client's tick still connects")

	_arm_actor(attacker,0)
	before = victim.health
	attacker.combat.ability_strike(2.2,360.0,10.0,0.0,true,false)
	check(is_equal_approx(victim.health,before),"The same strike against the present pose misses")

	# A shaft's historical contact: the line crosses the body where the shooter
	# saw it and does not cross it now.
	victim.position = Vector3(0,0.05,1.2)
	await pause(0.25)
	var shaft_seen: int = arena._lag.latest_tick()
	victim.position = Vector3(0,0.05,7.5)
	await pause(0.1)
	var current: int = arena._lag.latest_tick()
	check(arena._lag.segment_hits(victim.get_instance_id(),shaft_seen,
			Vector3(0,1.0,0.0),Vector3(0,1.0,2.5),0.02),
		"The shaft crosses the body where the shooter saw it")
	check(not arena._lag.segment_hits(victim.get_instance_id(),current,
			Vector3(0,1.0,0.0),Vector3(0,1.0,2.5),0.02),
		"The present body is not on that line")
	check(arena._lag.refuses(victim.get_instance_id(),shaft_seen,
			Vector3(0,1.0,6.0),Vector3(0,1.0,9.0),0.02),
		"A shaft aimed through the present pose is refused for the shooter's view")
	check(not arena._lag.refuses(victim.get_instance_id(),current,
			Vector3(0,1.0,6.0),Vector3(0,1.0,9.0),0.02),
		"The same shaft is accepted against the present pose")

	# The host keeps its own body; only the three bot slots go back to the AI so
	# a joining peer is seated on the first free seat.
	for actor in arena.actors:
		actor.is_bot = actor.slot != 0
		actor.revive()
	await pause(0.2)


func _host_run() -> void:
	input_ring_checks()
	timeline_checks()
	lag_history_checks()

	var socket := PacketPeerUDP.new()
	check(socket.bind(0) == OK,"The fixture gets an available UDP port")
	var port := socket.get_local_port()
	socket.close()
	arena = load("res://arena.tscn").instantiate()
	root.add_child(arena)
	arena.host_game(port,"Prediction host")
	report = Report.new()
	report.name = "PredictionReport"
	root.add_child(report)
	await pause(0.3)
	# Backward reconciliation is measured on the host's own bodies, before a peer
	# can move a fighter underneath the fixture.
	await lag_rewind_checks()
	var args := PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),
		"--script",get_script().resource_path,"--","--predict-client",str(port)])
	children.append(OS.create_process(OS.get_executable_path(),args))
	check(children[0] > 0,"The client process starts")
	var elapsed := 0.0
	while not report.messages.has("joined") and elapsed < 15.0:
		await pause(0.05)
		elapsed += 0.05
	check(report.messages.has("joined"),"A real ENet client joins the arena")
	check(int(arena.actors[1].peer_id) > 1,"The client is seated on the first free slot")

	# Clear the sparring floor of everything but the two rangers: this stage
	# measures the netcode, not a passing bot's soft-body separation.
	for slot in [2,3]:
		arena.actors[slot].is_bot = false
		arena.actors[slot].global_position = Vector3(28.0-slot*4.0,0.05,-28.0)
	# Two clear lanes: the host walks along -Z, the client along +X, far enough
	# apart that neither soft-body separation nor a stray hit can move a body.
	arena._camera_yaw = 0.0
	arena.actors[0].global_position = Vector3(-14,0.05,10)
	arena.actors[1].global_position = Vector3(-14,0.05,-10)
	await pause(0.4)

	# Stage one: both rangers walk. The client measures its own predicted body
	# and the host's rendered replica.
	report.stage.rpc(1)
	key(KEY_A,true)
	await pause(1.1)
	key(KEY_A,false)
	report.stage.rpc(2)
	elapsed = 0.0
	while not report.messages.has("walk") and elapsed < 12.0:
		await pause(0.05)
		elapsed += 0.05
	check(report.messages.has("walk"),"The client reports its walking trajectory")
	if report.messages.has("walk"):
		walk_metrics = report.messages["walk"]
		for entry in walk_metrics.get("history",[]):
			if float(entry.drift) > 0.02:
				print("HIST ",entry.drift," ack=",entry.ack," latest=",entry.latest,
					" predicted=",entry.predicted," actual=",entry.actual)

		check(int(walk_metrics.get("first_move",99)) <= 2,
			"The predicted body moves on the frame the key went down")
		check(bool(walk_metrics.get("predicted_before_ack",false)),
			"The moving frame is the client's own, before the authority saw it")
		check(float(walk_metrics.get("own_travel",0.0)) > 1.0,"The client's own body really walked")
		check(float(walk_metrics.get("own_max_step",99.0)) < walk_metrics.get("own_bound",0.0),
			"Walking is never interrupted by a visible correction (%s vs %s)"
				% [str(walk_metrics.get("own_max_step")),str(walk_metrics.get("own_bound"))])
		check(float(walk_metrics.get("host_travel",0.0)) > 0.5,"The host's fighter moved on its own")
		check(float(walk_metrics.get("host_max_step",99.0)) < walk_metrics.get("host_bound",0.0),
			"The host's fighter is rendered smoothly (%s vs %s)"
				% [str(walk_metrics.get("host_max_step")),str(walk_metrics.get("host_bound"))])
		check(int(walk_metrics.get("corrections",999)) <= int(walk_metrics.get("frames",0))/3,
			"Steady walking is mostly prediction, not correction (%s of %s frames)"
				% [str(walk_metrics.get("corrections")),str(walk_metrics.get("frames"))])
		check(float(walk_metrics.get("drift",99.0)) < 0.20,
			"Every correction stays under a quarter metre (%s)" % str(walk_metrics.get("drift")))
		check(int(walk_metrics.get("acked",-1)) > 0,"The host acknowledges the client's frames")
		check(int(walk_metrics.get("pending",999)) <= 40,"The unacknowledged history stays bounded")
		check(int(walk_metrics.get("samples",0)) >= 2,"The replica buffers more than the newest state")

	# Stage two: the host shoves the client's ranger. The client must snap to the
	# authoritative pose and then stay there.
	var seat = arena.actors[1]
	seat.global_position += Vector3(2.5,0,0)
	report.stage.rpc(3)
	await pause(0.7)
	report.stage.rpc(4)
	elapsed = 0.0
	while not report.messages.has("shove") and elapsed < 12.0:
		await pause(0.05)
		elapsed += 0.05
	check(report.messages.has("shove"),"The client reports its reconciliation")
	if report.messages.has("shove"):
		shove_metrics = report.messages["shove"]
		check(bool(shove_metrics.get("corrected",false)),"A host-side move is reconciled, not ignored")
		check(int(shove_metrics.get("corrections",0)) >= 1,"The reconciliation is counted")
		check(float(shove_metrics.get("moved",0.0)) > 1.5,
			"The reconciled body travelled to the authoritative pose (%s)" % str(shove_metrics.get("moved")))
		check(int(shove_metrics.get("quiet",99)) <= 3,
			"A correction settles within a few frames instead of repeating (%s)" % str(shove_metrics.get("quiet")))
	await _finish()


func _finish() -> void:
	for pid in children:
		if OS.is_process_running(pid):
			OS.kill(pid)
	if arena != null:
		arena.leave_game()
		arena.queue_free()
		arena = null
	await process_frame
	print("NET_PREDICTION_REGRESSION checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)


func _client_run(port: int) -> void:
	arena = load("res://arena.tscn").instantiate()
	root.add_child(arena)
	report = Report.new()
	report.name = "PredictionReport"
	root.add_child(report)
	arena.join_game("127.0.0.1",port,"Predict peer")
	var joined := false
	var elapsed := 0.0
	while elapsed < 12.0:
		if arena.local_slot >= 1 and arena.last_snapshot_tick >= 0:
			joined = true
			break
		await pause(0.05)
		elapsed += 0.05
	if not joined:
		report.result.rpc_id(1,"join_failed",{})
		await _finish()
		return
	await pause(0.6)
	report.result.rpc_id(1,"joined",{"slot":arena.local_slot})
	# D moves along +X on this peer too, so the two lanes never cross.
	arena._camera_yaw = 0.0
	arena._camera_pitch = 0.0
	var actor = arena.actors[arena.local_slot]
	var host_actor = arena.actors[0]

	# Stage one: hold D and record what the player sees. The counters start once
	# the stage does, so the fixture's own re-placement is not measured as drift.
	while report.command < 1:
		await physics_frame
	var corrections_before: int = actor.prediction_corrections
	actor.prediction_drift = 0.0
	actor.history.clear()
	var own: Array = []
	var remote: Array = []
	key(KEY_D,true)
	var first_move := -1
	var predicted_before_ack := false
	var frames := 0
	var drift_worst := 0.0
	while report.command < 2 and frames < 240:
		await physics_frame
		frames += 1
		own.append(actor.global_position)
		remote.append(host_actor.global_position)
		if first_move < 0 and own.size() > 1 and (own[-1] as Vector3).distance_to(own[0]) > 0.008:
			first_move = own.size() - 1
			# The moving frame is the client's own: the authority has not even
			# consumed it yet.
			predicted_before_ack = int(actor._prediction.acked) < actor.latest_prediction_seq()
		drift_worst = maxf(drift_worst,float(actor.prediction_drift))
	key(KEY_D,false)
	await physics_frame
	# A frame may not move further than four average walking steps: a correction
	# or a stall shows up as one frame that dwarfs the rest.
	var own_step: float = _travel(own)/maxf(float(maxi(frames-1,1)),1.0)
	var host_step: float = _travel(remote)/maxf(float(maxi(frames-1,1)),1.0)
	report.result.rpc_id(1,"walk",{
		"first_move":first_move,
		"own_bound":own_step*4.0+0.05,
		"host_bound":host_step*4.0+0.05,
		"predicted_before_ack":predicted_before_ack,
		"own_travel":_travel(own),
		"own_max_step":_max_step(own),
		"host_travel":_travel(remote),
		"host_max_step":_max_step(remote),
		"corrections":actor.prediction_corrections - corrections_before,
		"frames":frames,
		"drift":drift_worst,
		"acked":int(actor._prediction.acked),
		"pending":actor._prediction.size(),
		"samples":host_actor._timeline.samples.size(),
	})

	# Stage two: the host moved the authoritative body; the correction must land.
	var corrections_after_walk: int = actor.prediction_corrections
	while report.command < 3:
		await physics_frame
	var before_shove: Vector3 = actor.global_position
	var corrected := false
	var settle := 0
	while settle < 300:
		await physics_frame
		settle += 1
		if actor.prediction_corrections > corrections_after_walk:
			corrected = true
			break
	# A correction is a one-shot: once the body has snapped to the authoritative
	# pose it must not be corrected again while this peer stands still.
	var quiet_before: int = actor.prediction_corrections
	for index in 20:
		await physics_frame
	report.result.rpc_id(1,"shove",{
		"corrected":corrected,
		"corrections":actor.prediction_corrections - corrections_after_walk,
		"moved":actor.global_position.distance_to(before_shove),
		"quiet":actor.prediction_corrections - quiet_before,
	})
	await pause(0.2)
	await _finish()


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--predict-client"):
		await _client_run(int(args[args.find("--predict-client") + 1]))
	else:
		await _host_run()
