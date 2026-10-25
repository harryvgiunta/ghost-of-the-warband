extends SceneTree
## Ability framework regression: definition data, stamina spend, cooldown,
## committed travel, animation/replication, input bindings and HUD wiring.

const Actor = preload("res://scripts/arena_actor.gd")
const Archer = preload("res://scripts/archer.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const Audio = preload("res://scripts/range_audio.gd")
const Stamina = preload("res://scripts/stamina.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("ABILITY_FAIL  ", message)


func pause(seconds: float) -> void:
	await create_timer(seconds).timeout


func fighter(parent: Node3D, index: int, at: Vector3) -> Node3D:
	var actor := Actor.new()
	actor.slot = index
	actor.authoritative = true
	parent.add_child(actor)
	actor.configure(index+1,false,"Ability",at)
	actor.set_process(false)
	actor.rig.set_physics_process(false)
	actor.set_physics_process(false)
	actor.combat.set_motion(Vector3.ZERO,false,true)
	return actor


func run() -> void:
	var watchdog := create_timer(60.0)
	watchdog.timeout.connect(_on_watchdog)
	var definition: Dictionary = AbilityRules.by_slot(0)
	check(not definition.is_empty(), "Slot 0 defines an ability")
	check(str(definition.get("id","")) == "charge", "Slot 0 is the charge ability")
	check(str(definition.get("key","")) == "SHIFT + 1", "The charge binds to Shift + 1")
	check(float(definition.get("stamina_cost",0.0)) > 0.0, "The charge has a stamina cost")
	check(float(definition.get("cooldown",0.0)) > 0.0, "The charge has a cooldown")
	check(is_equal_approx(float(definition.get("duration",0.0)),1.0), "The charge lasts one second")
	check(is_equal_approx(float(definition.get("speed_scale",1.0)),2.0), "The charge moves at 200% speed")
	check(not str(definition.get("sound","")).is_empty(), "The charge has a sound")
	check(not str(definition.get("animation","")).is_empty(), "The charge has an animation clip")
	check(float(definition.get("lean",0.0)) > 0.0, "The charge declares its forward lean")
	check(AbilityRules.by_id("charge") == definition, "The ability is addressable by id")
	check(AbilityRules.slot_of("charge") == 0, "The ability reports its slot")
	check(AbilityRules.by_slot(99).is_empty(), "Unknown slots are rejected")
	check(is_equal_approx(Stamina.MAX,1000.0), "The base stamina pool is ten times the old hundred")
	var icon: Texture2D = AbilityRules.icon_texture("charge")
	check(icon != null and icon.get_width() > 0, "The charge icon loads from disk")

	var audio := Audio.new()
	root.add_child(audio)
	check(audio.sounds.has("charge"), "The charge sound is synthesized and registered")

	var world := Node3D.new()
	root.add_child(world)
	var host := fighter(world,0,Vector3.ZERO)
	check(host.ability != null, "Every actor owns an ability runner")
	host.stamina = Stamina.MAX
	var outcome: Dictionary = host.try_ability(0)
	check(bool(outcome.get("ok",false)), "A grounded, ready fighter starts the charge")
	check(is_equal_approx(host.stamina,Stamina.MAX-float(definition.stamina_cost)), "The charge spends its stamina cost")
	check(host.ability.active and host.rig.is_ability(), "The charge owns the rig phase")
	check(is_equal_approx(host.ability.velocity().length(),11.0), "The charge travels at 200% of the 5.5 m/s walk")
	check(host.ability.velocity().normalized().dot(Vector3.FORWARD) > 0.99, "The charge uses the facing direction")
	var animation: Dictionary = host.rig.get_animation_state()
	check(str(animation.phase) == "ABILITY", "The animation state presents the ability phase")
	check(int(round(float(animation.draw))) == 1, "The animation state carries the ability slot")
	check(host.rig.ability_clip == str(definition.animation), "The rig plays the authored charge clip")
	check(is_equal_approx(host.rig.ability_lean,float(definition.lean)), "The rig reads the ability lean from data")

	var replica_rig := Archer.new()
	world.add_child(replica_rig)
	replica_rig.set_physics_process(false)
	replica_rig.set_weapon("sword")
	replica_rig.apply_animation_state(animation)
	check(replica_rig.is_ability() and replica_rig.ability_id == "charge", "A replica decodes the ability phase")
	check(replica_rig.ability_clip == str(definition.animation), "A replica recovers the charge clip")
	check(is_equal_approx(replica_rig.ability_lean,float(definition.lean)), "A replica recovers the charge lean")

	host.ability.advance(0.5)
	check(host.ability.active and absf(host.ability.elapsed-0.5) < 0.001, "The charge keeps its committed clock")
	host.ability.advance(0.6)
	check(not host.ability.active and not host.rig.is_ability(), "The charge ends after its duration")
	check(float(host.ability.hud_state(0).cooldown) > 0.0, "The ended charge leaves a cooldown")
	var blocked: Dictionary = host.try_ability(0)
	check(not bool(blocked.get("ok",false)) and str(blocked.get("message","")).contains("ready"), "A cooling charge rejects another activation")

	host.ability.reset()
	host.stamina = float(definition.stamina_cost) - 1.0
	blocked = host.try_ability(0)
	check(not bool(blocked.get("ok",false)) and str(blocked.get("message","")).contains("stamina"), "An unaffordable charge is rejected")
	host.stamina = Stamina.MAX
	host.combat.set_motion(Vector3.ZERO,false,false)
	blocked = host.try_ability(0)
	check(not bool(blocked.get("ok",false)) and str(blocked.get("message","")).contains("Land"), "An airborne charge is rejected")
	host.combat.set_motion(Vector3.ZERO,false,true)

	host.ability.reset()
	check(bool(host.try_ability(0).get("ok",false)), "The charge restarts after a cooldown reset")
	host.combat.stagger(0.2)
	host.ability.advance(0.01)
	check(not host.ability.active and not host.rig.is_ability(), "A stagger cancels the charge")
	host.combat.stagger_time = 0.0
	host.ability.reset()

	host.stamina = Stamina.MAX
	host.health = 100.0
	check(bool(host.try_ability(0).get("ok",false)), "The charge starts before the chip test")
	host.take_damage(5.0,4,false)
	check(host.ability.active and host.rig.is_ability(), "A 5% chip cannot cancel the charge")
	host.health = 100.0
	host.take_damage(50.0,4,false)
	host.ability.advance(0.01)
	check(not host.ability.active and not host.rig.is_ability(), "A half-health hit cancels the charge")
	host.health = 100.0
	host.combat.stagger_time = 0.0
	host.ability.reset()

	host.stamina = Stamina.MAX
	check(bool(host.try_ability(0).get("ok",false)), "The charge starts before the replication test")
	var packed: Dictionary = host.snapshot()
	check(packed.has("stamina") and packed.has("ability"), "Snapshots carry stamina and ability state")
	check(JSON.stringify(packed).to_utf8_buffer().size() < 1100, "The fighter snapshot stays below the ENet MTU budget")
	var replica = Actor.new()
	replica.slot = 1
	replica.authoritative = false
	world.add_child(replica)
	replica.configure(2,false,"Replica",Vector3(2,0,0))
	replica.set_process(false)
	replica.rig.set_physics_process(false)
	replica.set_physics_process(false)
	replica.apply_snapshot(packed)
	check(is_equal_approx(replica.stamina,host.stamina), "Stamina replicates to the replica")
	check(replica.ability.active and int(replica.ability.active_slot) == 0, "The active ability replicates")
	check(float(replica.ability.hud_state(0).cooldown) > 0.0, "The replica HUD sees the cooldown")
	replica.rig.apply_animation_state(packed.animation)
	check(replica.rig.is_ability() and replica.rig.ability_clip == str(definition.animation), "The replicated pose plays charge")

	# Frontier binding, live movement and the HUD slot.
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await pause(0.8)
	check(game.ability != null and game.hud._ability_slot != null, "The frontier builds the ability runner and HUD slot")
	check(is_equal_approx(game.hud._stamina_bar.max_value,Stamina.MAX), "The frontier stamina bar uses the new pool")
	var stamina_before: float = game.stamina
	var event := InputEventKey.new()
	event.keycode = KEY_1
	event.physical_keycode = KEY_1
	event.pressed = true
	event.shift_pressed = true
	game._unhandled_input(event)
	check(game.ability.active and game.archer.is_ability(), "Shift + 1 starts the charge in the frontier")
	check(is_equal_approx(game.stamina,stamina_before-float(definition.stamina_cost)), "The frontier charge spends stamina")
	check(game.ability.velocity().length() > 10.0, "The frontier charge exposes its 200% travel")
	await pause(0.12)
	check(Vector2(game.player.velocity.x,game.player.velocity.z).length() > 10.0, "The frontier applies the charge velocity")
	await pause(1.05)
	check(not game.ability.active and game.archer.phase == "READY", "The frontier charge ends on its own clock")
	game.queue_free()
	await process_frame

	# Host-authoritative arena action path.
	var socket := PacketPeerUDP.new()
	check(socket.bind(0) == OK, "Ability fixture gets a free UDP port")
	var port := socket.get_local_port()
	socket.close()
	var arena = load("res://arena.tscn").instantiate()
	root.add_child(arena)
	arena.host_game(port,"Ability Regression")
	await pause(0.4)
	var seat = arena.actors[0]
	seat.stamina = Stamina.MAX
	arena._apply_action(0,"ability",0)
	check(seat.ability.active and seat.rig.is_ability(), "The arena host applies the charge action")
	check(seat.stamina < Stamina.MAX, "The arena charge spends stamina")
	arena._apply_action(0,"ability",99)
	check(seat.ability.active, "An invalid ability slot is ignored")
	arena.leave_game()
	await pause(0.2)
	arena.queue_free()
	await process_frame

	print("ABILITY_REGRESSION checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)


func _on_watchdog() -> void:
	push_error("Ability regression timed out")
	quit(1)
