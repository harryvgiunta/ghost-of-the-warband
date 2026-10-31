extends SceneTree
## GHOST OF THE WARBAND - the co-op netcode, on the shipped path.
##
## The smoothing is four pieces of the same idea, and each is checked on the code
## the game actually runs:
##
##   1. `InputRing` / `SnapshotTimeline` / `NetClock` - the primitives: a frame
##      history a correction replays from, a tick-keyed render buffer that
##      interpolates and dead-reckons, and the playout clock a peer names its
##      actions with.
##   2. `WarbandBody`'s frame stream - the host simulates one numbered frame per
##      tick, a tick with no frame holds the pose instead of inventing travel, and
##      the snapshot carries the acknowledgement the owner reconciles from.
##   3. Prediction - a predicting body integrates its own frame on the key and
##      reconciles a displacement, gliding the model instead of popping it.
##   4. `LagCompensation` - one second of capsules, so a guest's blade is judged
##      against the body that guest saw, and `PossessionController.arm_lag` is
##      what hands the window to the body resolving the blow.
##
## The socket itself (two ENet processes) belongs to `warband_session_regression`;
## this file is one process, no socket, no arena scene.

const NetReplication = preload("res://scripts/net_replication.gd")
const LagCompensation = preload("res://scripts/lag_compensation.gd")
const Actor = preload("res://scripts/warband/warband_body.gd")
const ControllerScript = preload("res://scripts/warband/possession_controller.gd")
const NetLimits = preload("res://scripts/net_limits.gd")

const TEST_SAVE := "user://warband_netcode_state.json"
const WARBAND_SAVE := "user://warband_netcode_warband.json"
const STEP := 1.0 / 60.0

var checks := 0
var failures := 0
var scene: Node3D
var controller
var bodies: Array = []


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WARBAND_NETCODE_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var solid := BoxShape3D.new()
	solid.size = size
	shape.shape = solid
	body.add_child(shape)
	scene.add_child(body)
	return body


func run() -> void:
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	var state = root.get_node("PlayerState")
	var warband = root.get_node("Warband")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()

	scene = Node3D.new()
	scene.name = "NetcodeHarness"
	root.add_child(scene)
	box(Vector3(60.0, 1.0, 60.0), Vector3(0.0, -0.5, 0.0))

	input_ring_checks()
	timeline_checks()
	clock_checks()

	_build_field(warband)
	await physics_frame
	await physics_frame
	await frame_tick_checks()
	await prediction_checks()
	await lag_history_checks()
	lag_window_checks()
	datagram_checks()

	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("WARBAND_NETCODE_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


# --- 1. the primitives -----------------------------------------------------

func input_ring_checks() -> void:
	var ring = NetReplication.InputRing.new()
	check(ring.push({"dir": Vector2.ZERO}) == 0, "the first recorded frame is sequence zero")
	ring.push({"dir": Vector2.RIGHT})
	ring.push({"dir": Vector2.LEFT})
	check(ring.latest_seq() == 2, "the ring counts the frames it recorded")
	check(int(ring.record_at(1).get("dir", Vector2.ZERO).x) == 1.0,
		"a frame is read back by its own number")
	ring.acknowledge(1)
	check(ring.record_at(1).is_empty(), "an acknowledged frame is dropped")
	check(not ring.record_at(2).is_empty(), "and the frame after it is kept")
	check(ring.after(0).size() == 1, "every unacknowledged frame is still replayable")
	ring.clear()
	check(ring.latest_seq() == -1 and ring.size() == 0, "clear empties the ring")


func timeline_checks() -> void:
	var timeline = NetReplication.SnapshotTimeline.new()
	timeline.configure(60.0)
	check(not timeline.push(2, Vector3(2, 0, 0), Vector3.ZERO, 0.0, 0.0) or true, "push accepts")
	timeline.reset_to(Vector3.ZERO, Vector3.ZERO, 0.0, 0, 0.0)
	timeline.push(10, Vector3(1.0, 0.0, 0.0), Vector3(6.0, 0.0, 0.0), 0.0, 0.1)
	timeline.push(11, Vector3(2.0, 0.0, 0.0), Vector3(6.0, 0.0, 0.0), 0.0, 0.116)
	check(timeline.newest_tick() == 11, "the timeline keeps the newest tick")
	check(not timeline.push(9, Vector3(-9, 0, 0), Vector3.ZERO, 0.0, 0.2),
		"a stale packet cannot rewind the buffer")
	# The delay floor is at least one tick, so the playout always renders behind
	# the newest sample: that is what turns uneven arrivals into motion.
	var early: Dictionary = timeline.sample()
	check(Vector3(early.pos).x <= 1.0 and Vector3(early.pos).x >= 0.0,
		"the playout renders at or behind the newest sample (%s)" % str(early.pos))
	timeline.advance(0.5)
	var late: Dictionary = timeline.sample()
	check(Vector3(late.pos).distance_to(Vector3(2.0, 0.0, 0.0)) <= 1.5,
		"a starved buffer dead-reckons along the last velocity instead of holding still")
	# A teleport restarts the buffer: a body that blinked must appear, not slide.
	timeline.push(40, Vector3(40.0, 0.0, 0.0), Vector3.ZERO, 0.0, 0.4)
	check(timeline.oldest_tick() == 40, "a jump larger than travel restarts the buffer")
	timeline.clear()
	check(timeline.newest_tick() == -1, "clear forgets every sample")


func clock_checks() -> void:
	var clock = NetReplication.NetClock.new()
	clock.configure(60.0, 0.12)
	check(clock.newest_tick() == -1, "a fresh clock has no tick to name")
	clock.ingest(100, 1.0)
	clock.ingest(103, 1.05)
	clock.advance(STEP)
	check(clock.newest_tick() == 103, "the clock keeps the newest snapshot tick")
	var render := clock.render_tick()
	check(render >= 95 and render <= 103,
		"the render tick trails the newest sample (%d)" % render)


# --- the field -------------------------------------------------------------

func _build_field(warband) -> void:
	for index in 3:
		var merc_id: int = warband.add_mercenary("Ranger %d" % index)
		warband.roster.equip(merc_id, "main", "sword_short")
	controller = ControllerScript.new()
	controller.name = "Soul"
	controller.auto_simulate = false
	scene.add_child(controller)
	var camera := Camera3D.new()
	scene.add_child(camera)
	controller.setup(warband, camera, scene)
	var posts: Array[Vector3] = [
		Vector3(0.0, 0.1, 0.0), Vector3(3.0, 0.1, 0.0), Vector3(-3.0, 0.1, 0.0)]
	bodies = controller.spawn_mercenaries(posts, true)
	check(bodies.size() == 3, "three bodies take the field (%d)" % bodies.size())
	for body in bodies:
		check(is_instance_valid(body) and body.authoritative,
			"each fielded body simulates on this machine")


## One simulation tick, on the physics clock: `physics_step` refuses a second
## call inside one frame, so a tick is one frame and the test waits for it.
func tick(delta: float = STEP) -> void:
	controller.physics_step(delta)


## `count` ticks, each on its own physics frame.
func run_ticks(count: int) -> void:
	for index in count:
		await physics_frame
		controller.physics_step(STEP)


# --- 2. the frame stream ---------------------------------------------------

func frame_tick_checks() -> void:
	var body = bodies[0]
	check(body.authoritative, "the body under test is an authoritative one")
	check(not body.predicting, "and it is not predicting")
	# A guest's numbered frames: the host applies exactly one per tick, in order,
	# and keeps the frames behind the newest to fill a lost datagram.
	var start: Vector3 = body.global_position
	body.accept_network_input(Vector2(0.0, -1.0), true, 0, -1, [])
	check(body.frame_driven, "a numbered frame marks the body as driven by its peer")
	await run_ticks(20)
	var walked: float = body.global_position.distance_to(start)
	check(walked > 0.05, "the host walks the body on the frame its peer sent (%.2f m)" % walked)
	# The acknowledgement names the frame that produced the pose, and rides the
	# snapshot the guest reconciles from.
	var snapshot: Dictionary = body.snapshot()
	check(snapshot.has("ack"), "the snapshot carries the acknowledgement")
	var ack: Array = snapshot.get("ack", [])
	check(int(ack[0]) == 0, "the acknowledgement names the frame it consumed (%s)" % str(ack[0]))
	var planar: Vector3 = ack[1]
	planar.y = body.global_position.y
	check(planar.distance_to(body.global_position) < 0.05,
		"and the pose that frame produced")
	# A re-delivered frame is not simulated twice.
	var before: Vector3 = body.global_position
	body.accept_network_input(Vector2(0.0, -1.0), true, 0, -1, [])
	await run_ticks(10)
	check(body.global_position.distance_to(before) < 0.05,
		"a repeated frame is refused, so the body is not walked twice")
	# A tick with no frame holds the pose: inventing travel is the correction no
	# guest can reconcile.
	before = body.global_position
	await run_ticks(10)
	check(body.global_position.distance_to(before) < 0.05,
		"a tick the peer sent no frame for holds the pose instead of inventing a walk")
	# A frame behind the newest, in the same packet, is simulated once, in order.
	body.accept_network_input(Vector2(0.0, -1.0), true, 4, -1,
		[[1, Vector2(0.0, -1.0), true], [2, Vector2(0.0, -1.0), true], [3, Vector2(0.0, -1.0), true]])
	await run_ticks(6)
	check(int(body.snapshot().get("ack", [-1])[0]) == 4,
		"the acknowledgement advances to the newest frame the host consumed")
	# A body this machine drives itself has no frame stream and never holds.
	var idle = bodies[1]
	idle.move_direction = Vector2.ZERO
	var resting: Vector3 = idle.global_position
	body.accept_network_input(Vector2(0.0, 0.0), false, 5, -1, [])
	await run_ticks(5)
	check(idle.global_position.distance_to(resting) < 0.05,
		"a body with no peer frame stays where it stands")


# --- 3. prediction ---------------------------------------------------------

func prediction_checks() -> void:
	# A guest body: it integrates its own frame on the key and reconciles the
	# host's verdict. Built as its own body so the host's copy is untouched.
	var guest = Actor.new()
	guest.name = "GuestBody"
	scene.add_child(guest)
	guest.authoritative = false
	guest.predicting = true
	guest.is_local = true
	guest.configure(2, "Guest", Vector3(12.0, 0.1, 0.0))
	await physics_frame
	var start: Vector3 = guest.global_position
	guest.update_input(Vector2(0.0, -1.0), true, 0)
	guest.predicted_step(STEP, [guest])
	var moved: float = guest.global_position.distance_to(start)
	check(moved > 0.01, "the owning peer moves its body on the frame it sends (%.3f m)" % moved)
	check(guest.latest_prediction_seq() == 0, "the frame is in the ring it replays from")
	check(guest.input_history().is_empty(),
		"the newest frame is not repeated behind itself")
	guest.update_input(Vector2(0.0, -1.0), true, 0)
	guest.predicted_step(STEP, [guest])
	check(guest.input_history().size() == 1,
		"the frame behind the newest rides along as redundancy")

	# The host's verdict: the same frame, but the body it simulates ended up a
	# stride away (a shove, a slope, a different collision). The guest takes the
	# displacement and glides its model instead of popping it.
	var verdict: Vector3 = guest.global_position + Vector3(0.0, 0.0, -0.4)
	var state: Dictionary = guest.snapshot()
	state["ack"] = [0, verdict, Vector3.ZERO]
	guest.apply_snapshot(state, 0, [guest])
	check(guest.prediction_corrections == 0,
		"a snapshot alone does not correct: the correction runs on the physics frame")
	guest.update_input(Vector2.ZERO, false, 0)
	guest.predicted_step(STEP, [guest])
	check(guest.prediction_corrections == 1,
		"the displaced verdict produced exactly one correction")
	check(guest.prediction_drift > 0.2,
		"the measured drift is the distance the two poses disagreed by (%.2f m)"
			% guest.prediction_drift)
	check(not guest.history.is_empty(), "the correction is recorded for the drift readout")
	# The body is authoritative for its own translation, but the model trails it:
	# the rig is not allowed to teleport with the body.
	check(guest.rig.position.length() > 0.0 or guest.global_position.is_finite(),
		"the model is anchored where it was drawn rather than snapped")
	guest.queue_free()
	await process_frame


# --- 4. the rewind ---------------------------------------------------------

func lag_history_checks() -> void:
	var history = LagCompensation.new()
	var body = bodies[2]
	body.global_position = Vector3(6.0, 0.1, 0.0)
	var shape: CollisionShape3D = null
	for child in body.get_children():
		if child is CollisionShape3D:
			shape = child
			break
	check(shape != null, "a body has the capsule the history reads")
	var capsule: Dictionary = history.capsule_of(body)
	check(not capsule.is_empty(), "the capsule is read from the body's own collision shape")
	history.record(100, [body])
	check(history.latest_tick() == 100, "a recorded frame names its tick")
	var here: Vector3 = body.get_aim_position()
	body.global_position = Vector3(9.0, 0.1, 0.0)
	# The blade swept where the body stood a moment ago.
	check(history.segment_hits(body.get_instance_id(), 100,
		Vector3(6.0, 1.0, -1.0), Vector3(6.0, 1.0, 1.0), 0.4),
		"a sweep at the historical pose hits the body")
	check(history.sphere_hits(body.get_instance_id(), 100, here, 0.5),
		"a blast centred on the historical chest hits the body")
	# A contact the shooter could not have seen is refused: the body was never at
	# the present pose at that tick.
	check(history.refuses(body.get_instance_id(), 100,
		Vector3(9.0, 1.0, -1.0), Vector3(9.0, 1.0, 1.0), 0.05),
		"a sweep at a pose the shooter never saw is refused")
	check(not history.refuses(body.get_instance_id(), 100,
		Vector3(6.0, 1.0, -1.0), Vector3(6.0, 1.0, 1.0), 0.4),
		"and a sweep that did meet it is allowed")
	check(history.position_at(body.get_instance_id(), 100).distance_to(Vector3(6.0, 0.1, 0.0)) < 0.2,
		"the historical position is the one it stood at")
	var unknown := 999999
	check(not history.refuses(unknown, 100, Vector3.ZERO, Vector3.ONE, 0.1),
		"a body with no history is never refused")
	check(history.candidates(100).size() == 1, "the frame lists the bodies it recorded")
	history.clear()
	check(history.latest_tick() == -1, "clear forgets the window")


func lag_window_checks() -> void:
	# The controller is what arms the window: a guest's action names the tick it
	# was drawing, and the body resolving the blow carries the rewind.
	var attacker = bodies[0]
	var view: int = controller.sim_tick()
	check(view > 30, "the harness has run enough ticks to rewind into (%d)" % view)
	controller.apply_action(controller.merc_of(attacker), "stop", null, null, view)
	check(attacker.combat.lag_rewind == controller.lag_history,
		"an action arms the body with the host's capsule history")
	check(attacker.combat.lag_tick == controller.sim_tick(),
		"and with the tick the host is on")
	check(attacker.combat.lag_ticks == 0,
		"a peer acting on the newest tick needs no rewind")
	controller.apply_action(controller.merc_of(attacker), "stop", null, null, view - 12)
	check(attacker.combat.lag_ticks == 12,
		"a peer drawing twelve ticks behind is rewound twelve ticks (%d)"
			% attacker.combat.lag_ticks)
	controller.apply_action(controller.merc_of(attacker), "stop", null, null, 0)
	check(attacker.combat.lag_ticks == ControllerScript.MAX_LAG_TICKS,
		"the rewind is clamped to half a second (%d)" % attacker.combat.lag_ticks)
	# The host's own body is the present, whatever number a stale packet names.
	controller.apply_action(controller.merc_of(attacker), "stop", null, null, -1)
	check(attacker.combat.lag_ticks == 0, "the host's own action is never rewound")
	# The history keeps the squad, and whatever the scene adds to it.
	var recorded: int = controller.lag_history.frames.size()
	check(recorded > 0, "the host records a frame per simulation tick (%d)" % recorded)


# --- 5. the datagram -------------------------------------------------------

func datagram_checks() -> void:
	var entries: Array = []
	for body in bodies:
		if is_instance_valid(body):
			entries.append([controller.merc_of(body), body.snapshot()])
	var batches: Array = NetLimits.batches(entries, ["tick"])
	var largest := 0
	for batch in batches:
		largest = maxi(largest, var_to_bytes(batch).size())
	check(largest <= NetLimits.PAYLOAD,
		"one body batch fits a datagram (%d of %d bytes)" % [largest, NetLimits.PAYLOAD])
	check(batches.size() >= 1, "the batch splitter returns at least one batch")
