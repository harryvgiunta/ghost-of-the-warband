extends SceneTree

const Archer = preload("res://scripts/archer.gd")
const Combat = preload("res://scripts/combat.gd")
var failures := 0
var checks := 0
var charges: Array[float] = []
var directions: Array[Vector3] = []
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
		rig._process(delta)
		combat.advance(delta)
		remaining -= delta

func run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	rig = Archer.new()
	holder.add_child(rig)
	rig.set_process(false)
	combat = Combat.new()
	holder.add_child(combat)
	combat.setup(rig, Vector3(0, 1.7, -20))
	combat.shot.connect(func(_origin, direction, _speed, charge):
		charges.append(charge)
		directions.append(direction))
	combat.set_motion(Vector3.ZERO, false, true)
	for bow in 3:
		for fraction in [0.0, 0.25, 0.5, 1.0]:
			advance(14.0)
			rig.set_bow(bow)
			var before := charges.size()
			check(combat.begin_draw(), "Ready bow accepts a held draw")
			if fraction > 0:
				advance(Archer.RAISE_SECONDS + float(Archer.BOW_DATA[bow].draw_seconds) * fraction)
			check(charges.size() == before, "Holding never auto-fires")
			combat.release_draw()
			check(charges.size() == before + 1, "One mouse release emits one arrow")
			check(absf(charges[-1] - fraction) < 0.0001, "Damage multiplier equals actual draw fraction")
			var expected: float = [30.0, 38.0, 50.0][bow] * fraction
			check(absf(Combat.damage_for(bow, charges[-1]) - expected) < 0.001, "Released damage scales linearly from zero to full damage")
			combat.release_draw()
			check(charges.size() == before + 1, "Repeated release cannot duplicate a shot")
	check(Combat.damage_for(1,-1.0) == 0.0 and Combat.damage_for(1,2.0) == 38.0, "Damage multiplier clamps to zero through one")
	for bow in 3:
		for mode in 3:
			advance(14.0)
			rig.set_bow(bow)
			var motion := Vector3.ZERO if mode == 0 else Vector3(5 if mode == 1 else 8,0,0)
			combat.set_motion(motion,mode == 2,true)
			check(combat.begin_draw(), "Recovered bow can start drawing")
			combat.release_draw()
			var expected: float = [1.0,2.0,3.0][bow] * [1.0,2.0,4.0][mode]
			advance(expected - 0.01)
			check(not combat.begin_draw(), "Cooldown rejects early presses")
			advance(0.02)
			check(combat.can_draw(), "Exact bow/movement timer becomes ready")
			print("MANUAL_COOLDOWN bow=",bow," movement=",combat.movement_mode," interval=",expected)
	combat.set_motion(Vector3.ZERO,false,true)
	advance(14.0)
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
	advance(0.5)
	var progress: float = combat.attack_progress
	rig.set_bow(2)
	combat.stop()
	check(is_equal_approx(combat.attack_progress,progress), "Cancel and bow swap cannot reset the cooldown")
	advance(14.0)
	combat.begin_draw()
	advance(0.6)
	combat.stop()
	combat.release_draw()
	check(charges.size() == before + 1, "Cancel does not fire a charged shot")
	holder.queue_free()
	await process_frame
	print("DRAW_COMBAT_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
