extends SceneTree

const Archer = preload("res://scripts/archer.gd")
const Combat = preload("res://scripts/combat.gd")
var failures := 0
var checks := 0
var charges: Array[float] = []
var directions: Array[Vector3] = []
var origins: Array[Vector3] = []
var speeds: Array[float] = []
var rig
var combat

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func advance(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.000001:
		var delta := minf(0.01, remaining)
		rig.advance_animation(delta)
		combat.advance(delta)
		remaining -= delta

func run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	rig = Archer.new()
	holder.add_child(rig)
	rig.set_physics_process(false)
	combat = Combat.new()
	holder.add_child(combat)
	combat.setup(rig, Vector3(0, 1.7, -20))
	combat.shot.connect(func(origin, direction, speed, charge):
		charges.append(charge)
		directions.append(direction)
		origins.append(origin)
		speeds.append(speed))
	combat.set_motion(Vector3.ZERO, false, true)
	for bow in 3:
		for fraction in [0.0, 0.25, 0.5, 1.0]:
			advance(1.24)
			rig.set_bow(bow)
			var before := charges.size()
			check(combat.begin_draw(), "Ready bow accepts a held draw")
			advance(float(bow + 1) * fraction)
			check(absf(rig.draw_amount - fraction) < 0.0001, "Charge bar fills over exactly 1/2/3 seconds, including the raise")
			check(charges.size() == before, "Holding never auto-fires")
			combat.release_draw()
			check(charges.size() == before + 1, "One mouse release emits one arrow")
			check(absf(charges[-1] - fraction) < 0.0001, "Damage multiplier equals actual draw fraction")
			var expected: float = [30.0, 38.0, 50.0][bow] * fraction
			check(absf(Combat.damage_for(bow, charges[-1]) - expected) < 0.001, "Released damage scales linearly from zero to full damage")
			var expected_speed: float = float(Archer.BOW_DATA[bow].speed) * lerpf(0.45,1.0,charges[-1])
			check(absf(speeds[-1] - expected_speed) < 0.001, "Arrow launch speed scales with the bow and charge")
			combat.release_draw()
			check(charges.size() == before + 1, "Repeated release cannot duplicate a shot")
			check(not combat.begin_draw() and not rig.active_bow.nocked_arrow.visible, "Every release spends the arrow and requires re-nocking, even at zero charge")
	check(Combat.damage_for(1,-1.0) == 0.0 and Combat.damage_for(1,2.0) == 38.0, "Damage multiplier clamps to zero through one")
	check(is_equal_approx(float(Archer.BOW_DATA[0].speed),66.0) and is_equal_approx(float(Archer.BOW_DATA[1].speed),84.0) and is_equal_approx(float(Archer.BOW_DATA[2].speed),102.0), "Bow arrows launch at 66/84/102 m/s")
	for mode in 3:
		advance(1.24)
		rig.set_bow(2)
		var motion := Vector3.ZERO if mode == 0 else Vector3(5 if mode == 1 else 8,0,0)
		combat.set_motion(motion,mode == 2,true)
		check(combat.begin_draw(), "Nocked bow can start drawing in every movement mode")
		advance(1.5)
		combat.release_draw()
		check(absf(charges[-1] - 0.5) < 0.0001, "A 1.5-second longbow hold gives 50% damage even while moving")
		advance(0.29)
		check(rig.phase == "RECOVER" and not combat.begin_draw(), "Next draw cannot interrupt the arrow retrieval animation")
		advance(0.93)
		check(not combat.can_draw(), "Bow remains unavailable until re-nocking finishes")
		advance(0.01)
		check(combat.can_draw() and rig.active_bow.nocked_arrow.visible, "Bow is ready at the animation boundary without an additional movement cooldown")
		print("BOW_RECOVERY movement=",combat.movement_mode," seconds=1.23 charge=",charges[-1])
	combat.set_motion(Vector3.ZERO,false,true)
	advance(1.24)
	rig.set_bow(1)
	combat.begin_draw()
	advance(0.8)
	combat.set_aim(Vector3(-8,1.7,-20))
	var left: Vector3 = rig.active_bow.get_arrow_direction()
	var before := charges.size()
	combat.set_aim(Vector3(8,1.7,-20))
	advance(2.0)
	check(left.dot(rig.active_bow.get_arrow_direction()) < 0.90, "Aim follows pointer changes while holding")
	check(charges.size() == before and rig.phase == "HOLDING", "Full draw stays held without auto-fire")
	var fixed_point: Vector3 = combat.aim_point
	advance(2.0)
	check(combat.aim_point == fixed_point, "No entity tracking or automatic target lock")
	combat.release_draw()
	check(charges.size() == before + 1 and directions[-1].x > 0.25, "Release uses the latest aim, not the initial click")
	check(directions[-1].dot((fixed_point-origins[-1]).normalized())>0.99999,"Released arrow follows the actual aim line without gravity compensation")
	advance(0.5)
	rig.set_bow(2)
	combat.stop()
	rig.set_weapon("sword")
	advance(0.2)
	rig.set_weapon("bow")
	check(not combat.begin_draw(), "Cancellation and equipment swaps cannot skip arrow retrieval")
	advance(0.53)
	check(combat.can_draw(), "Equipment swaps preserve recovery progress rather than restarting it")
	combat.begin_draw()
	advance(0.6)
	var held_fraction: float = rig.draw_amount
	rig.set_bow(0)
	rig.set_armor(2)
	check(rig.phase == "DRAWING" and is_equal_approx(rig.draw_amount,held_fraction), "Cover-intent cancellation does not change ordinary mid-draw equipment behavior")
	combat.stop()
	combat.release_draw()
	check(charges.size() == before + 1, "Cancel does not fire a charged shot")
	check(combat.can_draw(), "Canceling an unshot arrow does not invent a cooldown")
	combat.begin_draw()
	combat.release_draw()
	advance(0.1)
	rig.set_roll(0.5, Vector3.FORWARD)
	combat.stop()
	check(not combat.begin_draw(), "Rolling cannot bypass arrow recovery")
	rig.set_roll(-1.0, Vector3.FORWARD)
	advance(1.13)
	check(combat.can_draw(), "Recovery finishes normally after a roll")
	combat.begin_draw()
	combat.release_draw()
	rig.advance_animation(1.23)
	combat.advance(1.23)
	check(combat.can_draw(), "A long frame carries release time into recovery without extra delay")
	holder.queue_free()
	await process_frame
	print("DRAW_COMBAT_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
