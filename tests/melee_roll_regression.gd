extends SceneTree

const Actor = preload("res://scripts/arena_actor.gd")
const World = preload("res://scripts/arena_world.gd")
const Roll = preload("res://scripts/dodge_roll.gd")
var checks := 0
var failures := 0
var attacker
var victim

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
		var delta := minf(0.01,remaining)
		attacker.rig._process(delta)
		attacker.combat.advance(delta)
		remaining -= delta

func fighter(parent: Node3D, index: int, position_at: Vector3):
	var actor := Actor.new()
	actor.slot = index
	actor.authoritative = true
	parent.add_child(actor)
	actor.configure(index+1,false,"Regression",position_at)
	actor.rig.set_process(false)
	actor.combat.set_motion(Vector3.ZERO,false,true)
	return actor

func run() -> void:
	var world := World.new()
	root.add_child(world)
	attacker = fighter(world,0,Vector3.ZERO)
	victim = fighter(world,1,Vector3(0,0,-1.4))
	var behind = fighter(world,2,Vector3(0,0,1.4))
	await physics_frame
	await physics_frame
	attacker.rig.set_weapon("sword")
	attacker.combat.set_aim(victim.get_aim_position())
	for size in 3:
		attacker.rig.set_sword(size)
		attacker.combat.attack_progress = 1.0
		victim.health = 100.0
		var duration: float = [1.0,2.0,3.0][size]
		check(attacker.combat.begin_melee(),"Equipped sword starts an uncharged chop")
		check(attacker.rig.draw_amount == 0.0,"Melee never pulls a bowstring")
		advance(duration*0.57)
		check(victim.health == 100.0,"Sword windup cannot deal early damage")
		advance(duration*0.02)
		check(is_equal_approx(victim.health,100.0-[30.0,38.0,50.0][size]),"Overhand strike damages the actual opposing collider once")
		check(behind.health == 100.0,"Overhand chop cannot hit behind the attacker")
		check(not attacker.combat.begin_melee(),"Click spam cannot restart a sword swing")
		advance(duration*0.40)
		check(attacker.rig.phase == "MELEE","Sword remains in its selected-duration swing")
		advance(duration*0.02)
		check(attacker.rig.phase == "READY" and attacker.combat.attack_progress >= 0.999999,"Sword duration and cooldown are exactly 1/2/3 seconds")
		check(is_equal_approx(victim.health,100.0-[30.0,38.0,50.0][size]),"Recovery does not apply duplicate sword damage")
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0,3.0,0.2)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0,1.5,-0.7)
	wall.add_child(collision)
	world.add_child(wall)
	await physics_frame
	await physics_frame
	victim.health = 100.0
	attacker.combat.begin_melee()
	advance(3.1)
	check(victim.health == 100.0,"Cover blocks sword damage through walls")
	wall.queue_free()
	await physics_frame
	await physics_frame
	attacker.combat.begin_melee()
	advance(0.4)
	attacker.rig.set_weapon("bow")
	advance(3.0)
	check(victim.health == 100.0,"Weapon switching cancels an unfinished chop")
	check(attacker.rig.active_bow.visible and not attacker.rig.active_sword.visible,"Bow selection hides the sword")
	attacker.rig.set_weapon("sword")
	check(attacker.rig.active_sword.visible and not attacker.rig.active_bow.visible,"Sword selection hides the bow")
	check(attacker.rig.sword_index == 2,"Weapon switching remembers selected sword size")
	var roll := Roll.new()
	world.add_child(roll)
	check(roll.press_jump(Vector3.RIGHT,Vector3.FORWARD,true),"First Space performs a normal jump")
	roll.advance(0.15,false)
	check(not roll.press_jump(Vector3.RIGHT,Vector3.FORWARD,false) and roll.active,"Quick second Space starts a jump-roll")
	check(roll.direction.is_equal_approx(Vector3.RIGHT),"Strafing direction overrides facing for the roll")
	roll.advance(Roll.DURATION+0.01,false)
	check(not roll.active,"Roll ends after its finite duration")
	roll.press_jump(Vector3.FORWARD,Vector3.FORWARD,false)
	roll.press_jump(Vector3.FORWARD,Vector3.FORWARD,false)
	check(not roll.active,"Repeated airborne presses cannot chain infinite jump-rolls")
	roll.reset()
	roll.press_jump(Vector3.ZERO,Vector3.BACK,true)
	roll.advance(0.2,false)
	roll.press_jump(Vector3.ZERO,Vector3.BACK,false)
	check(roll.direction.is_equal_approx(Vector3.BACK),"Standing roll uses the facing direction")
	roll.reset()
	roll.press_jump(Vector3.RIGHT,Vector3.FORWARD,true)
	roll.advance(0.31,false)
	roll.press_jump(Vector3.RIGHT,Vector3.FORWARD,false)
	check(not roll.active,"Separated Space presses do not accidentally roll")
	world.queue_free()
	await process_frame
	print("MELEE_ROLL_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
