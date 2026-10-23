extends SceneTree

const Actor = preload("res://scripts/arena_actor.gd")
const Archer = preload("res://scripts/archer.gd")
const Combat = preload("res://scripts/combat.gd")
const STEP := 1.0 / 240.0
var checks := 0
var failures := 0
var attacker
var victim
var clock := 0.0
var recording := false
var samples: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func step(delta: float) -> void:
	clock += delta
	attacker.rig.advance_animation(delta)
	attacker.combat.advance(delta)
	victim.rig.advance_animation(delta)
	victim.combat.advance(delta)

func advance(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.000001:
		var delta := minf(STEP, remaining)
		step(delta)
		remaining -= delta

func observe_sweep(hand: String, previous_base: Vector3, previous_tip: Vector3,
		current_base: Vector3, current_tip: Vector3, radius: float) -> void:
	check(attacker.rig.has_melee(hand), "Only an active dual hand emits blade sweeps")
	if recording:
		samples.append({"hand":hand, "time":clock, "base":current_base, "tip":current_tip, "radius":radius})

func fighter(parent: Node3D, index: int, position_at: Vector3):
	var actor := Actor.new()
	actor.slot = index
	actor.authoritative = true
	parent.add_child(actor)
	actor.configure(index+1,false,"Dual Regression",position_at)
	actor.set_process(false)
	actor.rig.set_process(false)
	actor.rig.set_physics_process(false)
	actor.combat.set_motion(Vector3.ZERO,false,true)
	return actor

func place_victim(from_contact: Vector3) -> void:
	victim.position = from_contact - Vector3(0,0.9,0)
	victim.velocity = Vector3.ZERO
	victim.rig.global_basis = Basis(Vector3.UP,PI)
	attacker.rig.global_basis = Basis.IDENTITY
	victim.combat.set_aim(attacker.global_position+Vector3(0,1.2,0))
	attacker.combat.set_aim(victim.global_position+Vector3(0,1.2,0))

func reset_pair() -> void:
	attacker.combat.stop()
	victim.combat.stop()
	attacker.combat.left_melee_progress = 1.0
	attacker.combat.right_melee_progress = 1.0
	victim.combat.left_melee_progress = 1.0
	victim.combat.right_melee_progress = 1.0
	attacker.combat.melee_progress = 1.0
	victim.combat.melee_progress = 1.0
	attacker.combat.stagger_time = 0.0
	victim.combat.stagger_time = 0.0
	attacker.rig._clear_melee()
	victim.rig._clear_melee()
	attacker.rig._sync_primary_hand()
	victim.rig._sync_primary_hand()
	attacker.combat.set_motion(Vector3.ZERO,false,true)
	victim.combat.set_motion(Vector3.ZERO,false,true)
	attacker.position = Vector3.ZERO
	victim.position = Vector3(0,0,-1.5)
	attacker.rig.global_basis = Basis.IDENTITY
	victim.rig.global_basis = Basis(Vector3.UP,PI)
	attacker.rig.set_locomotion(Vector3.ZERO,true)
	victim.rig.set_locomotion(Vector3.ZERO,true)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	attacker = fighter(world,0,Vector3.ZERO)
	victim = fighter(world,1,Vector3(0,0,-1.5))
	attacker.rig.melee_sweep.connect(observe_sweep)
	attacker.rig.set_sword(0)
	attacker.rig.set_weapon("dual")
	attacker.rig.set_locomotion(Vector3.ZERO,true)
	await physics_frame
	await physics_frame
	advance(0.4)

	# Equipment rules: sword in the right hand, dagger in the left, no shield or guard.
	check(attacker.rig.weapon == "dual", "Dual wield is an explicit weapon mode")
	check(attacker.rig.active_sword.visible and attacker.rig.active_dagger.visible and not attacker.rig.active_bow.visible,
		"Dual wield shows the sword and the dagger together")
	check(not attacker.rig.can_equip_shield() and not attacker.rig.set_shield(true),
		"A dual wielder cannot carry the shield")
	check(not attacker.combat.start_block(Vector3(0,0,-1)) and not attacker.combat.blocking,
		"A dual wielder cannot raise a guard")
	attacker.rig.set_blocking(true,Vector3(0,0,-1))
	check(not attacker.rig.is_blocking(), "The rig also refuses a dual guard pose")
	attacker.combat.blocking = true
	attacker.combat.block_time = 0.0
	check(attacker.combat.resolve_melee_defense(victim.global_position) == Combat.DEFENSE_NONE,
		"A stale combat guard flag cannot block while dual wielding")
	attacker.combat.advance(0.01)
	check(not attacker.combat.blocking, "Dual wield clears any stale guard on the next combat tick")
	attacker.rig.set_sword(2)
	check(attacker.rig.weapon == "sword" and not attacker.rig.active_dagger.visible,
		"Selecting the greatsword leaves dual wield")
	check(not attacker.rig.set_weapon("dual"), "The two-handed greatsword cannot enter dual wield")
	attacker.rig.set_sword(0)
	check(attacker.rig.set_weapon("dual"), "The shortsword can enter dual wield")

	# The offhand dagger is held in a low forward guard, not left on the authored wrist.
	attacker.rig._aim_point = Vector3(0,1.2,-4)
	advance(0.4)
	var offhand_base: Vector3 = attacker.rig.active_dagger.to_global(Vector3(0,0,-0.09))
	var offhand_tip: Vector3 = attacker.rig.active_dagger.to_global(Vector3(0,0,-0.43))
	var offhand_dir: Vector3 = (offhand_tip-offhand_base).normalized()
	check(offhand_dir.dot(Vector3(0,0,-1)) > 0.90 and offhand_dir.y < -0.10,
		"The offhand dagger rests aimed forward and slightly down")
	check(attacker.rig.active_dagger.global_position.distance_to(attacker.rig._bone_world(attacker.rig._arms[0][2]).origin) < 0.20,
		"The offhand dagger stays attached to the left hand")

	# Left attack: the dagger profile, the authored stab clip, and the left-hand blade.
	attacker.combat.damage_enabled = false
	reset_pair()
	attacker.combat.set_aim(victim.global_position+Vector3(0,1.2,0))
	check(attacker.combat.begin_melee("left"), "A dual wielder starts the left attack")
	check(attacker.rig.phase == "MELEE_L", "The left attack has its own replicated phase")
	check(attacker.rig._melee_clip().name == "Dagger_Stab", "The left attack uses the authored dagger stab")
	check(is_equal_approx(attacker.rig.melee_damage(),float(Archer.DAGGER_DATA.damage)),
		"The left hand uses dagger damage")
	check(is_equal_approx(attacker.rig.melee_seconds(),float(Archer.DAGGER_DATA.seconds)),
		"The left hand uses dagger timing")
	check(is_equal_approx(attacker.rig.melee_reach(),float(Archer.DAGGER_DATA.reach)),
		"The left hand uses dagger reach")
	advance(0.05)
	var left_hand: Vector3 = attacker.rig._bone_world(attacker.rig._arms[0][2]).origin
	check(attacker.rig.get_blade_base().distance_to(left_hand) < 0.25,
		"The left strike samples the left-hand dagger, not the sword")
	var right_hand: Vector3 = attacker.rig._bone_world(attacker.rig._arms[1][2]).origin
	check(attacker.rig.active_sword.global_position.distance_to(right_hand) < 0.25,
		"The right sword stays socketed in the right hand during a left strike")
	var left_forward := 0.0
	var right_idle_offset := Vector3.ZERO
	var right_motion := 0.0
	var rest_upper: float = attacker.rig._bone_world(attacker.rig._arms[0][0]).origin.distance_to(attacker.rig._bone_world(attacker.rig._arms[0][1]).origin)
	var rest_lower: float = attacker.rig._bone_world(attacker.rig._arms[0][1]).origin.distance_to(attacker.rig._bone_world(attacker.rig._arms[0][2]).origin)
	for index in 8:
		attacker.rig.advance_animation(0.04)
		attacker.combat.advance(0.04)
		var blade: Vector3 = attacker.rig.get_blade_tip()-attacker.rig.get_blade_base()
		left_forward = maxf(left_forward,blade.normalized().dot((attacker.combat.aim_point-attacker.rig.get_blade_base()).normalized()))
		var right_offset: Vector3 = attacker.rig._bone_world(attacker.rig._arms[1][2]).origin-attacker.rig._bone_world(attacker.rig._arms[1][0]).origin
		if index == 0:
			right_idle_offset = right_offset
		else:
			right_motion = maxf(right_motion,right_offset.distance_to(right_idle_offset))
	check(left_forward > 0.95, "The left dagger points at the crosshair aim point")
	check(right_motion < 0.15, "The right sword arm holds its neutral pose during a left strike")
	check(is_equal_approx(attacker.rig._bone_world(attacker.rig._arms[0][0]).origin.distance_to(attacker.rig._bone_world(attacker.rig._arms[0][1]).origin),rest_upper) and is_equal_approx(attacker.rig._bone_world(attacker.rig._arms[0][1]).origin.distance_to(attacker.rig._bone_world(attacker.rig._arms[0][2]).origin),rest_lower),
		"The left strike preserves fixed upper-arm and forearm lengths")
	advance(0.2)
	check(attacker.rig.phase == "READY", "The left stab recovers after the dagger clip")

	# Real left-hand contact deals the dagger's base damage once.
	reset_pair()
	attacker.rig._aim_point = victim.global_position+Vector3(0,1.2,0)
	attacker.combat.set_aim(attacker.rig._aim_point)
	attacker.combat.damage_enabled = false
	recording = true
	samples.clear()
	clock = 0.0
	check(attacker.combat.begin_melee("left"), "The contact probe starts a left stab")
	advance(Archer.DAGGER_DATA.seconds+STEP)
	recording = false
	check(not samples.is_empty(), "The left stab emits real blade samples")
	if samples.is_empty():
		world.queue_free()
		await process_frame
		quit(1)
		return
	var middle: Dictionary = samples[samples.size()/2]
	var contact: Vector3 = (middle.base as Vector3).lerp(middle.tip,0.70)
	place_victim(contact)
	await physics_frame
	await physics_frame
	victim.health = 200.0
	attacker.combat.damage_enabled = true
	attacker.combat.melee_progress = 1.0
	clock = 0.0
	check(attacker.combat.begin_melee("left"), "A second left stab starts after recovery")
	advance(Archer.DAGGER_DATA.seconds+STEP)
	check(is_equal_approx(victim.health,200.0-float(Archer.DAGGER_DATA.damage)),
		"A real left dagger contact deals its base damage once")
	check(is_equal_approx(victim.health,200.0-float(Archer.DAGGER_DATA.damage)),
		"The left dagger does not damage the victim twice")

	# Right attack: the equipped sword profile, and the dagger stays offhand.
	reset_pair()
	victim.health = 200.0
	attacker.combat.damage_enabled = false
	attacker.combat.set_aim(victim.global_position+Vector3(0,1.2,0))
	check(attacker.combat.begin_melee("right"), "A dual wielder starts the right attack")
	check(attacker.rig.phase == "MELEE", "The right attack keeps the normal melee phase")
	check(attacker.rig._melee_clip().name == "Sword_Overhead_OneHand", "The right attack uses the one-hand sword clip")
	check(is_equal_approx(attacker.rig.melee_damage(),float(Archer.SWORD_DATA[0].damage)),
		"The right hand uses sword damage")
	check(attacker.rig.active_dagger.visible, "The offhand dagger stays visible during a right sword attack")
	advance(0.2)
	var right_hand_now: Vector3 = attacker.rig._bone_world(attacker.rig._arms[1][2]).origin
	check(attacker.rig.get_blade_base().distance_to(right_hand_now) < 0.30,
		"The right strike samples the right-hand sword, not the dagger")

	# Overlap: the right hand may start while the left is still swinging.
	reset_pair()
	attacker.combat.set_aim(victim.global_position+Vector3(0,1.2,0))
	attacker.combat.damage_enabled = false
	check(attacker.combat.begin_melee("left"), "The overlap probe starts the left attack")
	advance(0.1)
	check(attacker.combat.left_melee_progress > 0.1 and attacker.combat.left_melee_progress < 0.3,
		"The left hand owns its own recovery clock")
	check(not attacker.combat.begin_melee("left"), "The same hand cannot restart before its own recovery")
	check(attacker.combat.begin_melee("right"), "The right hand starts while the left is still active")
	check(attacker.rig.has_melee("left") and attacker.rig.has_melee("right"),
		"Both hands remain active after the overlapping input")
	check(attacker.rig.phase == "MELEE", "The right sword owns the primary body clip while both are active")
	check(attacker.combat.right_melee_progress < 0.1, "The right hand starts its own recovery clock")
	var overlap_state: Dictionary = attacker.rig.get_animation_state()
	check(str(overlap_state.phase) == "MELEE" and float(overlap_state.draw) > 0.0 and float(overlap_state.time) < 0.2,
		"The compact snapshot carries the primary time and the left hand's secondary time")
	var overlap_replica := Archer.new()
	world.add_child(overlap_replica)
	overlap_replica.set_physics_process(false)
	overlap_replica.set_process(false)
	overlap_replica.set_sword(1)
	overlap_replica.set_weapon("dual")
	overlap_replica.apply_animation_state(overlap_state)
	check(overlap_replica.has_melee("left") and overlap_replica.has_melee("right") and overlap_replica.phase == "MELEE",
		"A replica decodes both overlapping hands from the compact snapshot")
	check(is_equal_approx(overlap_replica._right_melee_duration,float(Archer.SWORD_DATA[1].seconds)) and is_equal_approx(overlap_replica._left_melee_duration,float(Archer.DAGGER_DATA.seconds)),
		"The replica derives the replicated sword and dagger durations")
	overlap_replica.advance_animation(0.6)
	check(not overlap_replica.has_melee("left") and overlap_replica.has_melee("right") and overlap_replica.phase == "MELEE",
		"The shorter dagger completes on the replica while the arming sword continues")
	overlap_replica.advance_animation(1.6)
	check(not overlap_replica.has_melee("right") and overlap_replica.phase == "READY",
		"The replicated arming sword uses its full two-second duration")
	overlap_replica.queue_free()
	recording = true
	samples.clear()
	clock = 0.0
	advance(1.2)
	recording = false
	var left_samples := 0
	var right_samples := 0
	for sample: Dictionary in samples:
		if str(sample.hand) == "left":
			left_samples += 1
		else:
			right_samples += 1
	check(left_samples > 0 and right_samples > 0,
		"Both overlapping hands emit independent blade sweeps")
	check(not attacker.rig.has_melee("left") and not attacker.rig.has_melee("right") and attacker.rig.phase == "READY",
		"Both hands finish and return to ready")
	check(is_equal_approx(attacker.combat.left_melee_progress,1.0) and is_equal_approx(attacker.combat.right_melee_progress,1.0),
		"Both recovery clocks reach ready")

	# Real damage from both hands while their clocks overlap.
	reset_pair()
	victim.position = Vector3(0,0,-1.0)
	victim.health = 200.0
	attacker.combat.damage_enabled = true
	attacker.combat.set_aim(victim.global_position+Vector3(0,1.2,0))
	victim.combat.set_aim(attacker.global_position+Vector3(0,1.2,0))
	check(attacker.combat.begin_melee("left"), "The damage overlap starts the left stab")
	advance(0.12)
	check(attacker.combat.begin_melee("right"), "The damage overlap starts the right sword")
	advance(0.12)
	var after_left: float = victim.health
	check(after_left <= 200.0-float(Archer.DAGGER_DATA.damage),
		"The left dagger deals damage while the right sword is already swinging")
	advance(0.5)
	check(victim.health <= after_left-float(Archer.SWORD_DATA[0].damage),
		"The right sword also deals damage while the left attack is on its clock")
	attacker.combat.stop()
	attacker.combat.damage_enabled = false

	# The reverse order: start the sword, then the dagger, and let the shorter
	# dagger finish while the sword continues. The freed left hand can re-attack.
	reset_pair()
	check(attacker.combat.begin_melee("right"), "The reverse overlap starts the right sword")
	advance(0.3)
	check(attacker.combat.begin_melee("left"), "The left dagger starts during the sword windup")
	check(attacker.rig.phase == "MELEE", "Starting the left later does not steal the sword body clip")
	advance(0.55)
	check(not attacker.rig.has_melee("left") and attacker.rig.has_melee("right"),
		"The shorter left attack finishes while the sword keeps swinging")
	check(attacker.combat.begin_melee("left"), "The freed left hand can start another attack during the sword")
	attacker.combat.stop()
	advance(0.2)
	# The right sword can finish first while the late left dagger continues.
	reset_pair()
	check(attacker.combat.begin_melee("right"), "The finish-order probe starts the sword")
	advance(0.9)
	check(attacker.combat.begin_melee("left"), "The late dagger starts before the sword finishes")
	advance(0.15)
	check(not attacker.rig.has_melee("right") and attacker.rig.has_melee("left"),
		"The sword can finish before the later dagger")
	check(attacker.rig.phase == "MELEE_L", "The surviving dagger takes the body clip after the sword ends")
	advance(0.45)
	check(not attacker.rig.has_melee("left") and attacker.rig.phase == "READY",
		"The late dagger completes after the sword")
	reset_pair()

	# A standard block knocks aside only the contacting hand.
	check(attacker.combat.begin_melee("right"), "The hand-abort probe starts the sword")
	advance(0.1)
	check(attacker.combat.begin_melee("left"), "The hand-abort probe starts the dagger")
	check(attacker.rig.has_melee("left") and attacker.rig.has_melee("right"), "Both hands are active before the block")
	attacker.combat.abort_swing("right")
	check(not attacker.rig.has_melee("right") and attacker.rig.has_melee("left"),
		"Aborting the blocked sword leaves the dagger swinging")
	check(attacker.rig.phase == "MELEE_L", "The surviving dagger becomes the primary body clip")
	check(is_equal_approx(attacker.combat.right_melee_progress,1.0),
		"The blocked hand keeps no recovery penalty")
	advance(0.5)
	check(not attacker.rig.has_melee("left") and attacker.rig.phase == "READY",
		"The surviving dagger completes normally")
	reset_pair()

	# Attack parry: only dual wield, only inside the active strike window, only facing.
	reset_pair()
	victim.rig.set_weapon("dual")
	victim.combat.set_motion(Vector3.ZERO,false,true)
	check(victim.combat.begin_melee("left"), "The defender starts a left stab")
	advance(0.20)
	check(victim.rig.in_strike_window(), "The dagger strike window is active for the parry test")
	check(victim.combat.resolve_melee_defense(attacker.global_position) == Combat.DEFENSE_PARRY,
		"An active dual strike parries a front melee hit")
	var health_before: float = victim.health
	var outcome: int = victim.receive_melee(30.0,0,attacker.global_position,false)
	check(outcome == Combat.DEFENSE_PARRY and is_equal_approx(victim.health,health_before),
		"The attack parry prevents all damage")
	advance(0.20)
	check(not victim.rig.in_strike_window(), "The parry window closes with the dagger strike")
	check(victim.combat.resolve_melee_defense(attacker.global_position) == Combat.DEFENSE_NONE,
		"An out-of-window dual attack does not parry")
	reset_pair()
	victim.rig.set_weapon("dual")
	victim.rig.global_basis = Basis(Vector3.UP,PI)
	check(victim.combat.begin_melee("left"), "The wrong-facing parry test starts a stab")
	advance(0.20)
	var behind: Vector3 = victim.global_position+Vector3(0,0,-2.0)
	check(victim.combat.resolve_melee_defense(behind) == Combat.DEFENSE_NONE,
		"A dual strike does not parry a hit from behind")
	reset_pair()
	victim.rig.set_weapon("sword")
	victim.rig.set_sword(0)
	check(victim.combat.begin_melee(), "A non-dual sword attack starts for the parry control")
	advance(0.55)
	check(victim.rig.in_strike_window(), "The control sword is in its strike window")
	check(victim.combat.resolve_melee_defense(attacker.global_position) == Combat.DEFENSE_NONE,
		"Attack parrying is exclusive to dual wield")
	reset_pair()

	# Snapshot phase and replica pose must carry the attacking hand.
	attacker.rig.set_weapon("dual")
	attacker.rig.set_sword(0)
	attacker.combat.left_melee_progress = 1.0
	attacker.combat.right_melee_progress = 1.0
	attacker.combat.melee_progress = 1.0
	attacker.rig._clear_melee()
	attacker.rig._sync_primary_hand()
	attacker.combat.set_motion(Vector3.ZERO,false,true)
	attacker.rig._aim_point = attacker.global_position+Vector3(-0.8,1.25,-5.0)
	check(attacker.combat.begin_melee("left"), "The replication probe starts a left stab")
	advance(0.22)
	var state: Dictionary = attacker.rig.get_animation_state()
	check(str(state.phase) == "MELEE_L", "The animation snapshot carries the left attack phase")
	var replica := Archer.new()
	world.add_child(replica)
	replica.set_physics_process(false)
	replica.set_process(false)
	replica.set_weapon("dual")
	replica.apply_animation_state(state)
	replica.advance_animation(0.22)
	check(replica.phase == "MELEE_L" and replica.has_melee("left"),
		"A replica decodes the left attack phase")
	check(replica.active_sword.visible and replica.active_dagger.visible,
		"A replica shows both dual weapons")
	var replica_dagger: Vector3 = replica.active_dagger.to_global(Vector3(0,0,-0.09))
	var replica_hand: Vector3 = replica._bone_world(replica._arms[0][2]).origin
	check(replica_dagger.distance_to(replica_hand) < 0.25,
		"A replica attaches the dagger to the left hand")

	# Throwing keeps the right sword and the endless-supply contract.
	reset_pair()
	attacker.rig.set_weapon("dual")
	attacker.combat.set_aim(attacker.global_position+Vector3(0,1.3,-8))
	check(attacker.combat.begin_throw(), "A dual wielder can charge a throw")
	check(attacker.rig.phase == "T_DRAW" and attacker.rig.throw_weapon_name() == "sword",
		"T throws the right-hand sword")
	check(is_equal_approx(attacker.rig.charge_seconds(),float(Archer.SWORD_DATA[0].seconds)),
		"The dual throw uses the equipped sword's charge time")
	attacker.rig.release_throw()
	check(attacker.rig.phase == "T_RELEASE", "Releasing T throws the right-hand sword")
	attacker.combat.stop()

	world.queue_free()
	await process_frame

	# Frontier input: LMB left, RMB right, and RMB never guards.
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.4).timeout
	for enemy in game.enemies:
		enemy.set_physics_process(false)
	game.archer.set_sword(0)
	game.archer.set_weapon("dual")
	game._set_cursor_free(false)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	check(game.archer.phase == "MELEE_L", "Frontier left click starts the left dagger attack")
	var overlap_press := InputEventMouseButton.new()
	overlap_press.button_index = MOUSE_BUTTON_RIGHT
	overlap_press.pressed = true
	Input.parse_input_event(overlap_press)
	await process_frame
	check(game.archer.has_melee("left") and game.archer.has_melee("right") and game.archer.phase == "MELEE",
		"Frontier right click overlaps the active left dagger")
	check(not game.combat.blocking, "The overlapping right click still cannot guard")
	var overlap_release := InputEventMouseButton.new()
	overlap_release.button_index = MOUSE_BUTTON_RIGHT
	overlap_release.pressed = false
	Input.parse_input_event(overlap_release)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	Input.parse_input_event(release)
	await create_timer(1.2).timeout
	check(game.archer.phase == "READY", "Both overlapping frontier attacks return to ready")
	var right_press := InputEventMouseButton.new()
	right_press.button_index = MOUSE_BUTTON_RIGHT
	right_press.pressed = true
	Input.parse_input_event(right_press)
	await process_frame
	check(game.archer.phase == "MELEE" and not game.combat.blocking,
		"Frontier right click starts the right sword attack and cannot guard")
	var right_release := InputEventMouseButton.new()
	right_release.button_index = MOUSE_BUTTON_RIGHT
	right_release.pressed = false
	Input.parse_input_event(right_release)
	await process_frame
	game.queue_free()
	await process_frame

	# Arena host routing for both attack hands and the mode action.
	var arena = load("res://arena.tscn").instantiate()
	root.add_child(arena)
	await create_timer(0.3).timeout
	arena.host_game(7898,"Dual Regression")
	await create_timer(0.2).timeout
	arena.send_action("sword",0)
	arena.send_action("weapon","dual")
	await create_timer(0.1).timeout
	check(arena.actors[0].rig.weapon == "dual", "Arena accepts the dual loadout action")
	arena.send_action("draw",Vector3(0,1.2,-4))
	await create_timer(0.1).timeout
	check(arena.actors[0].rig.phase == "MELEE_L", "Arena draw input starts the left attack")
	arena.send_action("attack_right",Vector3(0,1.2,-4))
	await create_timer(0.1).timeout
	check(arena.actors[0].rig.has_melee("left") and arena.actors[0].rig.has_melee("right") and arena.actors[0].rig.phase == "MELEE",
		"Arena right attack action overlaps the active left hand")
	arena.send_action("stop")
	arena.leave_game()
	arena.queue_free()
	await process_frame

	print("DUAL_WIELD_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
