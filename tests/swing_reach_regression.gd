extends SceneTree
## Standard cuts sweep the front from the loaded side without depending on target
## height or needle-thin blade contact, and one swing strikes only as many bodies
## as its weapon allows: one for a one-hander or a dagger, two for a two-hander.
## Precision attacks have separate blade regressions.
const Actor = preload("res://scripts/warband/warband_body.gd")
const Enemy = preload("res://scripts/enemy.gd")
const Combat = preload("res://scripts/combat.gd")
const Stamina = preload("res://scripts/stamina.gd")
const STEP := 1.0 / 240.0
const START_HEALTH := 500.0
var failures := 0
var checks := 0
var world: Node3D
var attacker
var targets: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func fighter(index: int, at: Vector3):
	var actor := Actor.new()
	actor.slot = index
	actor.authoritative = true
	world.add_child(actor)
	actor.configure(index+1,"Cleave",at)
	actor.rig.set_physics_process(false)
	actor.combat.set_motion(Vector3.ZERO,false,true)
	return actor

func target_at(offset: Vector3, kind: int = 2):
	var enemy := Enemy.new()
	enemy.kind = kind
	enemy.position = attacker.global_position+offset
	world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.max_health = START_HEALTH
	enemy.health = START_HEALTH
	targets.append(enemy)
	return enemy

func target_on_arc(distance: float, angle: float):
	var radians := deg_to_rad(angle)
	return target_at(Vector3(sin(radians),0,-cos(radians))*distance)

func step(delta: float) -> void:
	attacker.rig.advance_animation(delta)
	attacker.combat.advance(delta)

func advance(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.000001:
		var delta := minf(STEP,remaining)
		step(delta)
		remaining -= delta

func reset_swing() -> void:
	attacker.combat.abort_melee_to_neutral()
	attacker.combat.stagger_time = 0.0
	attacker.rig.set_hit_react(0.0)
	attacker.combat.set_aim(attacker.global_position+Vector3(0,1.2,-20))
	for enemy in targets:
		enemy.health = START_HEALTH

func clear_targets() -> void:
	for enemy in targets:
		enemy.queue_free()
	targets.clear()
	await process_frame
	await physics_frame

func settle() -> void:
	await physics_frame
	await physics_frame

## How many of `bodies` the last swing struck.
func struck(bodies: Array) -> int:
	var count := 0
	for enemy in bodies:
		if enemy.health < START_HEALTH:
			count += 1
	return count

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	# Elevated world origin catches absolute-world-height cut and hit bands.
	attacker = fighter(0,Vector3(0,6,0))
	attacker.combat.target_mask = 2
	attacker.rig.set_sword(0)
	attacker.rig.set_weapon("sword")
	var offsets: Array[Vector3] = []
	for distance in [0.65,1.15,1.75]:
		for angle in [-65.0,0.0,65.0]:
			var radians := deg_to_rad(angle)
			offsets.append(Vector3(sin(radians),0,-cos(radians))*distance)
	offsets.append(Vector3(0,0,-0.25))
	offsets.append(Vector3(0.6,0,-1.0))

	# Every frontal place a cut covers - point-blank, both flanks, the far edge of
	# the reach - is reached by both diagonals, one body at a time.
	var solo = target_at(offsets[0])
	for offset in offsets:
		solo.position = attacker.global_position+offset
		await settle()
		for variant in ["diagonal_right","diagonal_left"]:
			reset_swing()
			attacker.combat.begin_melee("right",variant)
			step(1.0)
			check(is_equal_approx(solo.health,START_HEALTH-30.0),
				"%s hits a lone frontal target exactly once at %s" % [variant,offset])
	await clear_targets()

	var crowd: Array = []
	for offset in offsets:
		crowd.append(target_at(offset))
	var rear = target_at(Vector3(0,0,1.0))
	var far = target_at(Vector3(0,0,-2.30))
	var above = target_at(Vector3(0,3.0,-1.0))
	var below = target_at(Vector3(0,-3.0,-1.0))
	await settle()
	# A one-handed cut strikes one body of a crowd: the first it crosses, from the
	# side the diagonal was loaded on - the nearest body on that flank's line -
	# however coarse the frame that carried the sweep.
	for variant in ["diagonal_right","diagonal_left"]:
		var first = crowd[2] if variant == "diagonal_right" else crowd[0]
		var last = crowd[0] if variant == "diagonal_right" else crowd[2]
		for coarse in [false,true]:
			reset_swing()
			check(attacker.combat.begin_melee("right",variant),"A ready sword starts either diagonal direction")
			if coarse:
				step(1.0)
			else:
				var window: Vector2 = attacker.rig._melee_window("right")
				advance(window.x*0.8)
				for enemy in crowd:
					check(enemy.health == START_HEALTH,"Diagonal windup cannot damage a future target")
				var early_time := window.x+(window.y-window.x)*0.15
				advance(early_time-window.x*0.8)
				check(first.health == START_HEALTH-30.0 and last.health == START_HEALTH,
					"Contact travels from the loaded side instead of hitting the whole sector at once")
				advance(1.0-early_time)
			check(is_equal_approx(first.health,START_HEALTH-30.0),
				"%s coarse=%s strikes the loaded flank's nearest body exactly once" % [variant,coarse])
			check(struck(crowd) == 1,
				"%s coarse=%s: a one-hander strikes one body of the crowd, got %d" % [variant,coarse,struck(crowd)])
			check(rear.health == START_HEALTH,"A diagonal does not damage a target behind the attacker")
			check(far.health == START_HEALTH,"Shortsword reach ends before a 2.3 m target")
			check(above.health == START_HEALTH and below.health == START_HEALTH,"A frontal cut cannot hit another floor")
			# A second swing may hit the same body, but the prior recovery may not.
			advance(0.3)
			check(first.health == START_HEALTH-30.0,"Finished recovery cannot repeat a hit")
			check(attacker.combat.begin_melee("right",variant),"Recovery permits a fresh cut")
			step(1.0)
			check(first.health == START_HEALTH-60.0,"A new cut clears the per-swing victim set")

	# Camera aiming checks projectile lanes against actors as well as scenery.
	# That query must never make the next melee sight check reject its victim: a
	# greatsword spends its two bodies on the flank's line, the second standing
	# right behind the first.
	attacker.rig.set_sword(2)
	reset_swing()
	attacker.combat.set_camera_ray(attacker.global_position+Vector3(0,1.2,4),Vector3.FORWARD)
	attacker.combat.begin_melee("right","diagonal_right")
	step(1.2)
	check(crowd[2].health == START_HEALTH-50.0 and crowd[5].health == START_HEALTH-50.0
		and struck(crowd) == 2,
		"Camera aiming cannot turn a cleave victim or nearby fighter into world cover")
	attacker.rig.set_sword(0)

	reset_swing()
	attacker.combat.begin_melee("right","diagonal_right")
	advance(attacker.rig._melee_window("right").x*0.5)
	attacker.combat.stop()
	advance(1.0)
	for enemy in crowd:
		check(enemy.health == START_HEALTH,"Canceling windup prevents all crowd damage")
	reset_swing()
	attacker.combat.damage_enabled = false
	attacker.combat.begin_melee("right","diagonal_right")
	step(1.0)
	check(struck(crowd) == 0,"A replica never applies cleave damage")
	attacker.combat.damage_enabled = true
	reset_swing()
	attacker.combat.begin_melee("right","diagonal_right")
	advance(attacker.rig._melee_window("right").x*0.5)
	attacker.rig.set_weapon("bow")
	advance(1.0)
	check(struck(crowd) == 0,"Changing equipment cancels later cleave contacts")
	attacker.rig.set_weapon("sword")
	await clear_targets()

	# Reach grows with weapon size, including both off-centre flanks, and the
	# weapon decides how many of the bodies it reaches it strikes: the arming
	# sword the first of them, the greatsword the first two.
	var middle: Array = []
	var outer: Array = []
	for angle in [-60.0,0.0,60.0]:
		middle.append(target_on_arc(2.15,angle))
		outer.append(target_on_arc(2.55,angle))
	await settle()
	for size in 3:
		attacker.rig.set_sword(size)
		for variant in ["diagonal_right","diagonal_left"]:
			reset_swing()
			attacker.combat.begin_melee("right",variant)
			step(1.2)
			var flank := 2 if variant == "diagonal_right" else 0
			check((middle[flank].health < START_HEALTH) == (size >= 1),"Only arming/greatsword reach the 2.15 m ring")
			check((outer[flank].health < START_HEALTH) == (size == 2),"Only the greatsword reaches the 2.55 m ring")
			check(struck(middle)+struck(outer) == [0,1,2][size],
				"Sword %d %s strikes %d of the ringed bodies, got %d"
				% [size,variant,[0,1,2][size],struck(middle)+struck(outer)])
	await clear_targets()

	# Staff reach is measured to the body surface, so the probe distance has to
	# include the cinder devil's 0.34 m capsule radius. 1.84 - 0.34 = 1.50 m is
	# the bone staff's limit and just inside the ember staff's 1.60 m.
	var staff_edge = target_on_arc(1.84,0)
	var staff_far = target_on_arc(2.22,0)
	await settle()
	for staff_index in 2:
		attacker.rig.set_staff(staff_index,true)
		reset_swing()
		attacker.combat.begin_melee("right","diagonal_right")
		step(1.2)
		check((staff_edge.health < START_HEALTH) == (staff_index == 0),"The longer ember staff sweeps farther than the bone staff")
		check(staff_far.health == START_HEALTH,"Staff length does not grant unlimited cleave reach")
	attacker.rig.set_staff(0,false)
	await clear_targets()

	# The dagger's reach first, alone, so no nearer body can spend its one strike.
	attacker.rig.set_weapon("dagger")
	var dagger_far = target_on_arc(1.9,0)
	await settle()
	for variant in ["diagonal_right","diagonal_left"]:
		reset_swing()
		attacker.combat.begin_melee("right",variant)
		step(0.7)
		check(dagger_far.health == START_HEALTH,"Dagger cleaves remain shorter than sword cleaves")
	var dagger_front: Array = []
	for angle in [-60.0,0.0,60.0]:
		dagger_front.append(target_on_arc(1.2,angle))
	await settle()
	for variant in ["diagonal_right","diagonal_left"]:
		reset_swing()
		attacker.combat.begin_melee("right",variant)
		step(0.7)
		var loaded = dagger_front[2] if variant == "diagonal_right" else dagger_front[0]
		check(loaded.health == START_HEALTH-14.0 and struck(dagger_front) == 1,
			"A dagger slice strikes one body of the close frontal arc, the loaded flank's, once")
	await clear_targets()

	# Scenery occludes each body, not the cut: a wall in the middle lane shields
	# the body behind it and nothing else, so a greatsword's two strikes land on
	# both open flanks.
	attacker.rig.set_sword(2)
	attacker.rig.set_weapon("sword")
	var covered = target_on_arc(1.4,0)
	var open_left = target_on_arc(1.4,-65)
	var open_right = target_on_arc(1.4,65)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5,3.0,0.02)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	wall.add_child(collision)
	world.add_child(wall)
	wall.position = attacker.position+Vector3(0,1.0,-0.8)
	await settle()
	for variant in ["diagonal_right","diagonal_left"]:
		reset_swing()
		attacker.combat.begin_melee("right",variant)
		step(1.2)
		check(covered.health == START_HEALTH,"Thin world geometry occludes the target behind it")
		check(open_left.health == START_HEALTH-50.0 and open_right.health == START_HEALTH-50.0,
			"A wall in one lane does not swallow either open flank of the cleave")
	wall.queue_free()
	await clear_targets()

	# A dense crowd - more than the old blade query's 32 contacts - loses exactly
	# what the weapon allows, from the loaded flank, and no body twice: a
	# shortsword or a club one body, a greatsword, a heavy branch or a staff two.
	for index in 40:
		target_on_arc(0.8+0.1*(index%4),-65.0+130.0*index/39.0)
	await settle()
	for kit in [{"sword":0, "cap":1}, {"sword":3, "cap":1}, {"sword":2, "cap":2},
			{"sword":4, "cap":2}, {"sword":0, "staff":true, "cap":2}]:
		attacker.rig.set_sword(int(kit["sword"]))
		attacker.rig.set_staff(0,bool(kit.get("staff",false)))
		reset_swing()
		check(attacker.combat.begin_melee("right","diagonal_right"),"%s starts a diagonal" % str(kit))
		step(1.2)
		var blow: float = START_HEALTH-float(targets[39].health)
		var single := blow > 0.0
		for enemy in targets:
			if enemy.health < START_HEALTH and not is_equal_approx(enemy.health,START_HEALTH-blow):
				single = false
		check(struck(targets) == int(kit["cap"]) and single,
			"%s strikes exactly %d bodies of a dense crowd from the loaded flank, once each (got %d)"
			% [str(kit),int(kit["cap"]),struck(targets)])
	attacker.rig.set_staff(0,false)
	attacker.rig.set_sword(0)
	await clear_targets()

	# An item skill is an attack too: one activation strikes at most ten bodies,
	# the nearest first - however many beats its ring takes, and a blast as well.
	var ring: Array = []
	for index in 14:
		ring.append(target_on_arc(1.0+0.1*index,360.0*index/14.0))
	await settle()
	reset_swing()
	var shared: Dictionary = {}
	var ringed: int = attacker.combat.ability_strike(2.9,360.0,20.0,0.0,true,false,shared)
	ringed += attacker.combat.ability_strike(2.9,360.0,20.0,0.0,true,false,shared)
	check(ringed == Combat.ABILITY_MAX_VICTIMS and struck(ring) == Combat.ABILITY_MAX_VICTIMS,
		"A whirlwind's beats strike at most ten bodies between them (%d)" % struck(ring))
	var nearest := true
	for index in ring.size():
		if (ring[index].health < START_HEALTH) != (index < Combat.ABILITY_MAX_VICTIMS):
			nearest = false
	check(nearest,"The ten bodies a ring strikes are the nearest ten")
	reset_swing()
	var blasted: int = attacker.combat.ability_blast(attacker.global_position+Vector3.UP*0.95,2.9,20.0)
	check(blasted == Combat.ABILITY_MAX_VICTIMS and struck(ring) == Combat.ABILITY_MAX_VICTIMS,
		"One blast strikes at most ten bodies (%d)" % struck(ring))
	await clear_targets()

	attacker.combat.target_mask = 4
	var defender = fighter(1,attacker.position+Vector3(0,0,-1.2))
	defender.rig.set_sword(0)
	defender.rig.set_weapon("sword")
	await settle()
	reset_swing()
	defender.stamina = Stamina.MAX
	defender.combat.start_block(Vector3.BACK)
	defender.combat.advance(0.4)
	attacker.combat.begin_melee("right","diagonal_right")
	advance(1.0)
	check(defender.health == 100.0 and defender.stamina == Stamina.MAX-Combat.BLOCK_STAMINA,
		"A diagonal cleave honors a held guard and spends stamina only once")
	reset_swing()
	defender.combat.stop_block()
	defender.stamina = 100.0
	attacker.combat.begin_melee("right","diagonal_left")
	advance(attacker.rig._melee_window("right").x)
	defender.combat.start_block(Vector3.BACK)
	advance(0.15)
	check(defender.health == 100.0 and attacker.combat.stagger_time > 0.0,
		"A timely guard parries and cancels an assisted diagonal hit")

	world.queue_free()
	await process_frame
	print("SWING_REACH_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
