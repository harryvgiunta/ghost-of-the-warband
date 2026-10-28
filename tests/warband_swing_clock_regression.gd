extends SceneTree
## GHOST OF THE WARBAND: the swing clock.
##
## The player's report was "clicking after playing for a while makes it so its
## impossible to attack". The cause was two clocks gating one click:
##
##   * `Archer` advances its own clip on every physics frame;
##   * `Combat` kept a *copy* of each hand's recovery, advanced only by whoever
##     stepped the body (`ArenaActor.step` -> `combat.advance`), and
##     `Combat.begin_melee` gated on that copy.
##
## Any frame that animated the rig without stepping the body - a paused frame, a
## downed or dead body, a guest's predicted body - let the two disagree: the copy
## froze mid-swing (or never recovered) while the clip ran to completion, and
## every click after it was refused *silently*. Worse, before a swing had ever
## started the copy was still the class default (1.0 s) while the rig reported the
## real weapon's duration (0.55 s for the shiv): the two clocks named different
## numbers for the same cut.
##
## The fix is structural, so this test asserts the structure:
##
##   1. **Identity.** At the frame a swing starts, `combat._right_swing_seconds`
##      is exactly `rig.melee_seconds("right")` - for the sword, the dagger, the
##      club and the two-handed branch. It is seeded from the rig, so it holds
##      before the first cut too.
##   2. **Duration.** One diagonal cut takes the rig's own clip and nothing else:
##      a dagger inside 0.6 s, a club inside 1.0 s, the branch inside 1.7 s.
##   3. **Recovery is the clip.** When the rig's hand is idle the gate is open;
##      while the rig is swinging the gate is shut. A frozen copy of the progress
##      can no longer refuse a click, and a swing cannot outlive its clip.
##   4. **Click rate.** Thirty clicks one physics frame apart start thirty swings.
##   5. **No wedge.** Three thousand frames of clicking, walking, blocking and a
##      body swap leave `can_begin_melee` answering true, and the next click
##      still starts a cut.
##   6. **The bow.** A `bow_twig` draw charges in its authored 0.7 s and the
##      release returns the rig to READY.

const WORLD := "res://scenes/warband_world.tscn"

var checks := 0
var failures := 0
var game
var controller
var warband
var body
var rig
var combat
var frames_per_second := 60.0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

## Seconds of simulated time, counted in physics frames: the assertion is about
## the clock the game runs on, not about how fast this machine renders.
func seconds(frames: int) -> float:
	return float(frames) / frames_per_second

# --- setup ----------------------------------------------------------------

## The tutorial card pauses the tree, and a paused tree neither steps the bodies
## nor animates the rig: this test is about the frames after it.
func close_card() -> void:
	if game.card != null and game.card.is_open():
		game.card.close()

## A floor of our own under the squad. The world's ground is a terrain field
## rebuilt by another regression's subject; the swing clock must not depend on
## whether a body is standing on the authored ground or on this plate.
func plate(at: Vector3) -> void:
	var ground := StaticBody3D.new()
	ground.name = "ClockFloor"
	ground.collision_layer = 1
	ground.collision_mask = 0
	ground.position = Vector3(at.x, at.y, at.z)
	game.add_child(ground)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(160.0, 4.0, 160.0)
	shape.shape = box
	shape.position = Vector3(0.0, -2.0, 0.0)
	ground.add_child(shape)

func settle(count: int) -> void:
	for index in count:
		await physics_frame

## Wait until the body is standing on something and the controller has stepped it.
func settle_grounded(limit: int = 240) -> int:
	var frames := 0
	while frames < limit:
		if bool(combat.grounded) and int(controller._tick) > 4:
			return frames
		await physics_frame
		frames += 1
	return frames

func arm(item: String) -> bool:
	var merc: int = controller.merc_for_peer(1)
	if merc <= 0:
		return false
	warband.stash.add(item, 1)
	var result: Dictionary = warband.equip_merc(merc, "main", item)
	if not bool(result.get("ok", false)):
		return false
	controller.refresh_gear(merc)
	await settle(2)
	return true

## One left click on the real possession controller, exactly as the input layer
## calls it. Returns whether a swing was running afterwards.
func click() -> bool:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	controller._mouse_press(press)
	return bool(rig.is_melee())

func wheel(direction: String) -> bool:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_WHEEL_UP if direction == "stab" else MOUSE_BUTTON_WHEEL_DOWN
	press.pressed = true
	controller._mouse_press(press)
	return bool(rig.is_melee())

## Physics frames from now until the rig's right hand is idle again. The frame
## count is the swing's duration on the game's own clock.
func wait_hand_idle(limit: int = 400) -> int:
	var frames := 0
	while frames < limit and bool(rig.is_melee()):
		await physics_frame
		frames += 1
	return frames

# --- 1/2. identity and duration -------------------------------------------

## One weapon, one click: the clock identity at the start of the cut, the clip's
## own length, and the gate opening again the frame the clip ends.
func measure_cut(item: String, bound: float) -> void:
	var armed: bool = await arm(item)
	check(armed, "%s is worn by the possessed body" % item)
	var merc: int = controller.merc_for_peer(1)
	check(rig.weapon in ["sword", "dagger", "dual"], "%s puts a melee weapon in the hand (%s)" % [item, str(rig.weapon)])
	var started := click()
	check(started, "%s: a left click starts a cut" % item)
	var duration: float = float(rig.melee_seconds("right"))
	var seconds_combat: float = float(combat._right_swing_seconds)
	check(is_equal_approx(seconds_combat, duration),
		"%s: the two clocks agree at the frame the cut starts (combat %.3f, rig %.3f)" % [item, seconds_combat, duration])
	check(is_equal_approx(float(combat.melee_progress_for("right")), 0.0),
		"%s: the cut starts at zero progress (%.3f)" % [item, float(combat.melee_progress_for("right"))])
	var frames := await wait_hand_idle()
	var took := seconds(frames)
	check(frames > 0 and absf(took - duration) <= 0.05,
		"%s: one diagonal cut takes its own clip (%.2f s, clip %.2f s)" % [item, took, duration])
	check(took <= bound, "%s: the cut is inside %.2f s (%.2f s)" % [item, bound, took])
	# The gate has to be open on the frame the clip ends, not one clock later.
	check(float(combat.melee_progress_for("right")) >= 1.0 - 0.000001,
		"%s: the copy recovered with the clip (%.3f)" % [item, float(combat.melee_progress_for("right"))])
	check(bool(rig.can_begin_melee("right")), "%s: the rig takes the next cut" % item)
	await settle(2)
	check(merc == controller.merc_for_peer(1), "%s: the soul stayed in its body" % item)
	print("SWING_CLOCK %s clip=%.3f took=%.3f frames=%d" % [item, duration, took, frames])

# --- 3. the copy cannot outlive the clock it copies -----------------------

## The bug in one line: the copy of the recovery was a second clock, so a body
## whose frames were skipped left it frozen and refused every click. The rig is
## the clock now, in both directions:
##
##   * while the rig swings the copy cannot open the gate, whatever a scene
##     writes into it;
##   * a copy left mid-way recovers on the rig's own clock, inside one swing.
func check_copy_cannot_outlive_rig() -> void:
	check(bool(rig.can_begin_melee("right")), "the hand is idle before the copy check")
	var clip: float = 0.42
	combat.right_melee_progress = 0.0
	combat.melee_progress = 0.0
	var frames := 0
	while frames < 200 and float(combat.melee_progress_for("right")) < 1.0 - 0.000001:
		await physics_frame
		frames += 1
	check(frames <= int(ceil(clip * frames_per_second)) + 2,
		"a copy left at zero recovers inside one swing (%.3f s)" % seconds(frames))
	check(click(), "a click starts a cut once the copy has recovered")
	# While the rig swings, writing 1.0 into the copy cannot bypass the clip.
	await settle(3)
	combat.right_melee_progress = 1.0
	check(float(combat.melee_progress_for("right")) < 1.0,
		"a live clip keeps the gate shut whatever the copy says (%.3f)" % float(combat.melee_progress_for("right")))
	await wait_hand_idle()
	check(bool(rig.can_begin_melee("right")), "the hand recovers after the copy check")

## The base game's rule the warband must not lose: a weapon swap cancels the
## animation but not the recovery the cut already earned.
func check_swap_keeps_recovery() -> void:
	await wait_hand_idle()
	check(click(), "a cut starts before the weapon swap")
	await settle(4)
	check(bool(combat.begin_melee("right", "diagonal_right")) == false,
		"a cut in flight is not restarted by a second call")
	rig.set_weapon("bow")
	rig.set_weapon("sword")
	check(float(combat.melee_progress_for("right")) < 1.0,
		"the swapped-out cut keeps its recovery (%.3f)" % float(combat.melee_progress_for("right")))
	check(not bool(combat.begin_melee("right", "diagonal_right")),
		"a weapon swap cannot bypass the sword's own recovery")
	var frames := 0
	while frames < 200 and float(combat.melee_progress_for("right")) < 1.0 - 0.000001:
		await physics_frame
		frames += 1
	check(float(combat.melee_progress_for("right")) >= 1.0 - 0.000001,
		"the recovery tail finishes (%.3f s)" % seconds(frames))
	check(click(), "the next cut starts after the tail")
	await wait_hand_idle()
	print("SWING_CLOCK swap tail=%.3f" % seconds(frames))

# --- 4. thirty clicks, one frame apart ------------------------------------

func check_click_rate() -> void:
	await wait_hand_idle()
	var starts := 0
	var clicks := 0
	# One click a frame for the length of forty cuts: the gate has to open again
	# on its own, so a click that lands while the last cut is still running is
	# refused and the next one after it starts the following cut.
	var frames := 0
	var per_swing: int = maxi(1, int(round(float(rig.melee_seconds("right")) * frames_per_second)))
	var budget: int = per_swing * 40 + 120
	while clicks < 30 and frames < budget:
		if not bool(rig.is_melee()):
			if click():
				starts += 1
			clicks += 1
		await physics_frame
		frames += 1
	check(starts >= 30, "thirty clicks one frame apart start thirty cuts (%d)" % starts)
	check(clicks >= 30, "thirty clicks landed on a body that would take them (%d)" % clicks)
	await wait_hand_idle()
	check(bool(rig.can_begin_melee("right")), "the gate is open again after thirty cuts")
	await settle(2)
	print("SWING_CLOCK rate starts=%d clicks=%d frames=%d per_swing=%d" % [starts, clicks, frames, per_swing])

# --- 5. three thousand frames of a session --------------------------------

func check_long_session() -> void:
	var frames := 0
	var starts := 0
	var swaps := 0
	var wedged := 0
	controller.input_enabled = false
	while frames < 3000:
		# Walk, sprint, stand: the body's own intent, through the real step. The
		# walk reverses every two seconds so the squad paces its own camp instead
		# of walking off the plate, and `input_age` is refreshed because a live
		# intent would arrive every frame (`_drive` does this in the game).
		var block: int = frames / 120
		if block % 3 == 2:
			body.move_direction = Vector2.ZERO
		else:
			body.move_direction = Vector2(1.0, 0.0) if block % 2 == 0 else Vector2(-1.0, 0.0)
		body.run_requested = block % 4 == 1
		body.input_age = 0.0
		# Hold and drop the guard every so often: `stop_block` and the stagger
		# clock are the other things that gate a click.
		if frames % 200 == 0:
			var right := InputEventMouseButton.new()
			right.button_index = MOUSE_BUTTON_RIGHT
			right.pressed = true
			controller._mouse_press(right)
		if frames % 200 == 40:
			var release := InputEventMouseButton.new()
			release.button_index = MOUSE_BUTTON_RIGHT
			release.pressed = false
			controller._mouse_release(release)
		if frames == 1200 or frames == 2400:
			var moved: Dictionary = controller.cycle(1, 1)
			check(bool(moved.get("ok", false)), "the soul changes body mid-session (%s)" % str(moved.get("reason", "")))
			await physics_frame
			body = controller.active_body(1)
			rig = body.rig
			combat = body.combat
			controller.input_enabled = false
			var dressed: bool = await arm("dagger_ironwood")
			check(dressed, "the new body wears the shiv")
			await settle(4)
			body.position = Vector3(-7.6, 0.6, 6.0)
			await settle_grounded()
			swaps += 1
		var was_swinging := bool(rig.is_melee())
		var started := click()
		if started and not was_swinging:
			starts += 1
			if not is_equal_approx(float(combat._right_swing_seconds), float(rig.melee_seconds("right"))):
				wedge_probe(wedged)
				wedged += 1
		# The copy may never disagree with the rig for long: an idle hand is open.
		if not bool(rig.is_melee()) and float(combat.melee_progress_for("right")) < 1.0 and not bool(combat.blocking):
			await physics_frame
			frames += 1
			if not bool(rig.is_melee()) and float(combat.melee_progress_for("right")) < 1.0:
				wedge_probe(wedged)
				wedged += 1
		await physics_frame
		frames += 1
	controller.input_enabled = true
	check(wedged == 0, "no frame in the session left the gate shut with an idle rig (%d)" % wedged)
	check(swaps == 2, "the session swapped bodies twice (%d)" % swaps)
	check(starts >= 60, "the session kept swinging (%d cuts in %d frames)" % [starts, frames])
	# Ends wedged? The next click has to take, on the body the soul is inside now.
	controller.input_enabled = false
	if not bool(combat.grounded):
		await settle_grounded()
	var recovered := 0
	while recovered < 120 and not bool(rig.can_begin_melee("right")):
		await physics_frame
		recovered += 1
	check(bool(rig.can_begin_melee("right")),
		"the clock is not wedged after the session (%d frames to recover)" % recovered)
	var last := click()
	check(last, "the first click after the session still starts a cut")
	check(recovered <= int(frames_per_second * 2.0),
		"recovery is inside one swing duration (%d frames)" % recovered)
	await wait_hand_idle()
	controller.input_enabled = true
	print("SWING_CLOCK session frames=%d starts=%d swaps=%d recovered=%d" % [frames, starts, swaps, recovered])

func wedge_probe(wedged: int) -> void:
	if wedged < 4:
		print("SWING_CLOCK WEDGE copy=%.3f live=%.3f rig=%.3f phase=%s weapon=%s grounded=%s" % [
			float(combat.right_melee_progress), float(combat.melee_progress_for("right")),
			float(rig.melee_progress_for("right")) if bool(rig.is_melee()) else 1.0,
			str(rig.phase), str(rig.weapon), str(combat.grounded)])

# --- 6. the bow -----------------------------------------------------------

func check_bow() -> void:
	var dressed: bool = await arm("bow_twig")
	check(dressed, "the twig bow is worn")
	check(rig.weapon == "bow", "the rig carries the bow (%s)" % str(rig.weapon))
	var draw := 0.7
	var charge: float = float(rig.charge_seconds())
	check(is_equal_approx(charge, draw), "the twig bow's draw is its authored %.2f s (%.3f)" % [draw, charge])
	controller.input_enabled = true
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	controller._mouse_press(press)
	check(rig.phase in ["DRAWING", "HOLDING"], "a click on the bow begins a draw (%s)" % str(rig.phase))
	var frames := 0
	while frames < 400 and float(rig.draw_amount) < 1.0 - 0.000001:
		await physics_frame
		frames += 1
	check(float(rig.draw_amount) >= 1.0 - 0.000001, "the draw reaches full charge (%.3f)" % float(rig.draw_amount))
	var took := seconds(frames)
	check(frames > 0 and absf(took - draw) <= 0.06,
		"the twig bow charges on its authored draw (%.2f s, authored %.2f s)" % [took, draw])
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	controller._mouse_release(release)
	check(rig.phase in ["RELEASE", "RECOVER"], "the release leaves the draw (%s)" % str(rig.phase))
	var recovery := 0
	while recovery < 400 and str(rig.phase) != "READY":
		await physics_frame
		recovery += 1
	check(str(rig.phase) == "READY", "the shot recovers to READY (%s)" % str(rig.phase))
	var shot := seconds(recovery)
	check(absf(shot - (0.28 + 0.95)) <= 0.08,
		"release and recovery take their authored %.2f s (%.2f s)" % [0.28 + 0.95, shot])
	await settle(2)
	print("SWING_CLOCK bow charge=%.3f frames=%d recovery=%.2f" % [took, frames, shot])

# --- main -----------------------------------------------------------------

func run() -> void:
	var watchdog := Timer.new()
	watchdog.name = "Watchdog"
	watchdog.wait_time = 120.0
	watchdog.one_shot = true
	watchdog.timeout.connect(_on_watchdog)
	root.add_child(watchdog)
	watchdog.start()

	game = load(WORLD).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	controller = game.controller
	warband = game.warband
	if controller == null or controller.active_body(1) == null:
		check(false, "the world seated a soul in a body")
		_finish()
		return
	frames_per_second = float(Engine.physics_ticks_per_second)
	close_card()
	check(not paused, "the world is not paused once the card is dismissed")
	body = controller.active_body(1)
	rig = body.rig
	combat = body.combat
	body.position = Vector3(-7.6, 0.6, 6.0)
	plate(Vector3(-7.6, 0.0, 6.0))
	await settle_grounded()
	check(bool(combat.grounded), "the possessed body is standing on the ground")
	close_card()

	await measure_cut("dagger_ironwood", 0.6)
	await measure_cut("sword_makeshift", 0.75)
	await measure_cut("club_makeshift", 1.0)
	await measure_cut("branch_heavy", 1.7)
	# The wheel-up lunge is the dagger's other clock, and it is the fast one the
	# prison shank passive shortens; it still has to start on the rig's number.
	var dressed: bool = await arm("dagger_ironwood")
	check(dressed, "the shiv is back in the hand")
	var diagonal: float = 0.42
	check(wheel("stab"), "the wheel-up starts a stab")
	var stab_seconds: float = float(combat._right_swing_seconds)
	check(is_equal_approx(stab_seconds, float(rig.melee_seconds("right"))),
		"the stab starts on the rig's clock (combat %.3f, rig %.3f)" % [
			stab_seconds, float(rig.melee_seconds("right"))])
	check(stab_seconds < diagonal,
		"the shiv's stab is shorter than its diagonal cut (%.3f < %.2f)" % [stab_seconds, diagonal])
	print("SWING_CLOCK stab %.3f" % stab_seconds)
	await wait_hand_idle()

	await check_copy_cannot_outlive_rig()
	await check_swap_keeps_recovery()
	await check_click_rate()
	await check_long_session()
	await check_bow()
	_finish()

func _on_watchdog() -> void:
	check(false, "the swing clock regression did not finish inside its budget")
	_finish()

func _finish() -> void:
	print("WARBAND_SWING_CLOCK_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
