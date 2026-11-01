extends SceneTree
## The frame budget's two rules for a rig and a body that stand about, measured on
## the real profiler the F12 overlay reads:
##
##   * a rig poses from the drawn frame, once per `set_pose_stride` of them, and a
##     coarser solve advances the authored clocks by the whole time it skipped -
##     the stride costs frames of work, never frames of motion;
##   * a `view_paced` rig is asked for a pose by the camera: every frame in front
##     of the eye, far fewer for a body off the screen;
##   * a scenery rig past `MobLod.ANIMATE_DISTANCE` from the camera stops posing,
##     and comes back on its own when the eye returns (`scripts/rig_presence.gd`);
##   * a world frame turned toward another keeps its absolute scale - the slerp
##     that used to do this raised an engine error on every stride and blend and
##     blended from the identity instead (`Archer._turn_toward`).
##
## Presentation only: nothing here is allowed to change what the sim does.

const Archer = preload("res://scripts/archer.gd")
const Perf = preload("res://scripts/perf_probe.gd")
const Presence = preload("res://scripts/rig_presence.gd")

const FRAMES := 40

var world: Node3D
var camera: Camera3D
var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("FRAME_BUDGET_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.7, 0.0)
	world.add_child(camera)
	camera.current = true
	await check_solve_stride()
	await check_clock_conservation()
	await check_view_pacing()
	await check_presence()
	check_turn_toward_scale()
	world.queue_free()
	await process_frame
	print("FRAME_BUDGET_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


## One rig on a holder. `view_paced` rigs use the drawn-frame clock; the rest the
## physics tick.
func make_rig(at: Vector3, paced: bool = false):
	var rig = Archer.new()
	rig.sparse_props = true
	rig.view_paced = paced
	rig.position = at
	world.add_child(rig)
	rig.set_physics_process(false)
	rig.advance_animation(0.2)
	return rig


## Poses counted on the real profiler: the `rig.pose` row of the window.
func poses_in(frames: int) -> int:
	Perf.reset()
	Perf.enabled = true
	for _index in frames:
		await physics_frame
	Perf.enabled = false
	var total := 0
	for row in Perf.rows():
		if str(row["name"]) == "rig.pose":
			total += int(row["calls"])
	return total


func check_solve_stride() -> void:
	var rig = make_rig(Vector3(0.0, 0.0, -4.0))
	rig.set_pose_stride(1)
	rig.set_physics_process(true)
	var every := await poses_in(FRAMES)
	check(every >= FRAMES - 2 and every <= FRAMES + 2,
		"a rig at stride 1 poses every physics tick (%d in %d)" % [every, FRAMES])
	rig.set_pose_stride(4)
	var quarter := await poses_in(FRAMES)
	check(quarter >= FRAMES / 4 - 1 and quarter <= FRAMES / 4 + 2,
		"stride 4 poses every fourth tick (%d in %d)" % [quarter, FRAMES])
	rig.set_physics_process(false)
	rig.queue_free()


## The point of a stride: the same authored time, in fewer solves. A slow clock
## must not slow the body down.
func check_clock_conservation() -> void:
	var plain = make_rig(Vector3(0.0, 0.0, -4.0))
	var strided = make_rig(Vector3(3.0, 0.0, -4.0))
	plain.set_locomotion(Vector3(0.0, 0.0, -4.0), true)
	strided.set_locomotion(Vector3(0.0, 0.0, -4.0), true)
	plain.set_pose_stride(1)
	strided.set_pose_stride(6)
	plain.set_physics_process(true)
	strided.set_physics_process(true)
	for _index in FRAMES:
		await physics_frame
	plain.set_physics_process(false)
	strided.set_physics_process(false)
	var plain_time := plain.motion_seconds()
	var strided_time := strided.motion_seconds()
	# Both ran the same 40 ticks; the strided rig solves on a whole stride and may
	# sit up to six ticks short of the wall clock, never more.
	check(absf(plain_time - strided_time) <= 6.5 / 60.0,
		"a strided rig keeps the same authored clock (%.3f s vs %.3f s)" % [strided_time, plain_time])
	check(plain_time > 0.5, "the walk cycle advanced at all (%.3f s)" % plain_time)
	plain.queue_free()
	strided.queue_free()


## In front of the eye, on the screen, and behind it: three different asks.
func check_view_pacing() -> void:
	var near = make_rig(Vector3(0.0, 0.0, -5.0), true)
	var far = make_rig(Vector3(0.0, 0.0, -60.0), true)
	var behind = make_rig(Vector3(0.0, 0.0, 30.0), true)
	behind.set_shadow_casting(false)
	near.set_physics_process(true)
	far.set_physics_process(true)
	behind.set_physics_process(true)
	# One drawn frame asks the camera where each of them stands.
	await process_frame
	await process_frame
	var counted := await poses_in(FRAMES)
	# Three rigs over 40 frames: the ones off the screen must account for only a
	# handful of the solves.
	check(counted >= FRAMES, "the rig before the eye poses every frame (%d in %d)" % [counted, FRAMES])
	check(counted <= FRAMES + FRAMES / 2 + FRAMES / 20 + 4,
		"the rigs off the screen pose a fraction as often (%d in %d)" % [counted, FRAMES])
	check(int(behind.get("_view_stride")) > int(near.get("_view_stride")),
		"a body behind the camera is asked for fewer poses than one in front (%d vs %d)"
		% [int(behind.get("_view_stride")), int(near.get("_view_stride"))])
	for rig in [near, far, behind]:
		rig.set_physics_process(false)
		rig.queue_free()


## A keeper's rig has no brain to budget: the presence node is its only clock.
func check_presence() -> void:
	var rig = make_rig(Vector3(0.0, 0.0, -5.0))
	rig.set_physics_process(true)
	var presence: Node = Presence.new(rig)
	world.add_child(presence)
	await process_frame
	await create_timer(Presence.INTERVAL * 1.5).timeout
	check(rig.is_physics_processing(), "a scenery rig in front of the eye poses")
	# The eye walks a kilometre away down the Hollow.
	camera.position = Vector3(0.0, 1.7, 1000.0)
	await create_timer(Presence.INTERVAL * 1.5).timeout
	check(not rig.is_physics_processing(), "a scenery rig a kilometre off stops posing")
	camera.position = Vector3(0.0, 1.7, 0.0)
	await create_timer(Presence.INTERVAL * 1.5).timeout
	check(rig.is_physics_processing(), "and comes back when the eye does")
	presence.queue_free()
	rig.set_physics_process(false)
	rig.queue_free()


## The slerp this replaced raised "Basis must be normalized" on every blended foot
## in the game and blended from the identity. The turn must keep the scale it
## found and stay a rotation.
func check_turn_toward_scale() -> void:
	var rig = make_rig(Vector3(0.0, 0.0, -4.0))
	rig.set_body_height(1.12)
	var from: Basis = (rig.global_transform.basis * Basis(Vector3.UP, 0.3)).scaled(Vector3.ONE * 1.12)
	var to := Basis(Vector3.UP, 1.1).scaled(Vector3.ONE * 1.12)
	var turned: Basis = rig.call("_turn_toward", from, to, 0.5)
	check(is_equal_approx(turned.get_scale().x, 1.12),
		"the turned frame keeps the rig's scale (%.4f)" % turned.get_scale().x)
	var ortho := turned.orthonormalized()
	check(turned.is_equal_approx(ortho.scaled(turned.get_scale())) or
		absf(turned.determinant() - pow(1.12, 3.0)) < 0.02,
		"the turned frame is a rotation, not a shear (det %.4f)" % turned.determinant())
	var halfway: float = turned.get_rotation_quaternion().angle_to(Quaternion(Vector3.UP, 1.1))
	var total: float = from.get_rotation_quaternion().angle_to(Quaternion(Vector3.UP, 1.1))
	check(halfway < total, "the turn moved toward the target (%.3f < %.3f rad)" % [halfway, total])
	rig.queue_free()
