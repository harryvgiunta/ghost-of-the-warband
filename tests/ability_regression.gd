extends SceneTree
## Ability framework regression: item-granted definitions, two hand slots,
## stamina spend, cooldown, committed travel, cue timing, animation/
## replication, input bindings and HUD wiring.

const Actor = preload("res://scripts/arena_actor.gd")
const Archer = preload("res://scripts/archer.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const AbilityRunner = preload("res://scripts/ability_runner.gd")
const Audio = preload("res://scripts/range_audio.gd")
const Stamina = preload("res://scripts/stamina.gd")
const State = preload("res://scripts/player_state.gd")

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


func equip(rig, main_id: String, off_id: String = "") -> void:
	rig.apply_loadout(State.build_loadout(main_id,off_id,{"head":0,"chest":0,"hands":0,"legs":0,"feet":0}))


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
	check(is_equal_approx(Stamina.MAX,1000.0), "The base stamina pool is ten times the old hundred")

	# Data: the starter shortbow grants Barrage; an empty hand keeps Charge.
	var world := Node3D.new()
	root.add_child(world)
	var host := fighter(world,0,Vector3.ZERO)
	equip(host.rig,"bow_short")
	var definition: Dictionary = host.ability.definition(0)
	check(str(definition.get("id","")) == "barrage", "The shortbow grants Barrage in the main hand")
	check(str(definition.get("key","")) == "SHIFT + 1", "Barrage binds to Shift + 1")
	check(is_equal_approx(float(definition.get("stamina_cost",0.0)),AbilityRules.TEST_STAMINA_COST), "Barrage costs a trivial stamina sliver")
	check(float(definition.get("cooldown",0.0)) > 0.0, "Barrage has a cooldown")
	check(is_equal_approx(float(definition.get("duration",0.0)),1.15), "Barrage lasts 1.15 s")
	check(is_equal_approx(float(definition.get("speed_scale",1.0)),0.0), "Barrage is stationary")
	check(str(definition.get("animation","")) == "Bow_Barrage", "Barrage declares its authored clip")
	check(AbilityRules.by_id("barrage") == definition, "The ability is addressable by id")
	check(AbilityRules.by_item("bow_short",0) == definition, "The item resolves its slot-0 ability")
	check(AbilityRules.by_item("bow_short",1).is_empty(), "A bow grants no off-hand ability")
	check(AbilityRules.by_index(AbilityRules.index_of("barrage")) == definition, "The wire index round-trips")
	check(AbilityRules.by_item("sword_cutlery",0).is_empty(), "Unknown items grant nothing")
	check(host.ability.definition(1).is_empty(), "An empty off hand grants no skill")
	var icon: Texture2D = AbilityRules.icon_texture("barrage")
	check(icon != null and icon.get_width() > 0, "The Barrage icon loads from disk")

	var audio := Audio.new()
	root.add_child(audio)
	check(audio.sounds.has("barrage"), "The Barrage sound is synthesized and registered")
	for id in ["volley","pierce","slash","lunge","spin","backstab","fire","bone","bash","slam"]:
		check(audio.sounds.has(id), "The %s sound is synthesized and registered" % id)

	# Activation: spend, ownership, HUD, cues and the committed clock.
	host.stamina = Stamina.MAX
	var cues: Array = []
	host.ability.cue.connect(func(id: String, cue: String, index: int): cues.append([id,cue,index]))
	var outcome: Dictionary = host.try_ability(0)
	check(bool(outcome.get("ok",false)), "A grounded, ready archer starts Barrage")
	check(is_equal_approx(host.stamina,Stamina.MAX-float(definition.stamina_cost)), "Barrage spends exactly its cost")
	check(host.ability.active and host.rig.is_ability(), "Barrage owns the rig phase")
	check(host.ability.velocity().is_zero_approx(), "Barrage does not travel")
	check(str(host.ability.hud_state(0).get("id","")) == "barrage", "The HUD state names the granted skill")
	var animation: Dictionary = host.rig.get_animation_state()
	check(str(animation.phase) == "ABILITY", "The animation state presents the ability phase")
	var packed_code := int(round(float(animation.draw)))
	check(packed_code & 3 == 1, "The animation state carries the ability slot")
	check((packed_code >> 2)-1 == AbilityRules.index_of("barrage"), "The animation state carries the ability index")
	check(host.rig.ability_clip == "Bow_Barrage", "The rig plays the authored Barrage clip")
	host.ability.advance(0.24)
	check(cues.size() == 1 and str(cues[0][1]) == "shot", "The first Barrage cue fires on its beat")
	host.ability.advance(0.92)
	check(cues.size() == 6, "Barrage fires all six shot cues")
	check(not host.ability.active and not host.rig.is_ability(), "Barrage ends after its duration")
	check(float(host.ability.hud_state(0).cooldown) > 0.0, "The ended Barrage leaves a cooldown")
	var blocked: Dictionary = host.try_ability(0)
	check(not bool(blocked.get("ok",false)) and str(blocked.get("message","")).contains("ready"), "A cooling Barrage rejects another activation")
	host.ability.reset()
	check(host.ability.hud_state(0).cooldown == 0.0, "A reset clears the cooldown")

	# A weapon swap clears the trailing cooldown of the stowed skill.
	host.stamina = Stamina.MAX
	check(bool(host.try_ability(0).get("ok",false)), "Barrage restarts for the swap test")
	host.ability.advance(1.0)
	check(float(host.ability.hud_state(0).cooldown) > 0.0, "Barrage is cooling before the swap")
	host.ability.cancel()
	host.rig.set_bow(1)
	host.ability.advance(0.01)
	check(host.ability.hud_state(0).cooldown == 0.0, "Switching weapons clears the slot's testing cooldown")
	check(str(host.ability.hud_state(0).get("id","")) == "triple_volley", "The new bow grants its own skill")
	host.rig.set_bow(0)
	host.ability.advance(0.01)

	# Eligibility boundaries.
	host.stamina = float(definition.stamina_cost) - 1.0
	blocked = host.try_ability(0)
	check(not bool(blocked.get("ok",false)) and str(blocked.get("message","")).contains("stamina"), "An unaffordable skill is rejected")
	host.stamina = Stamina.MAX
	host.combat.set_motion(Vector3.ZERO,false,false)
	blocked = host.try_ability(0)
	check(not bool(blocked.get("ok",false)) and str(blocked.get("message","")).contains("Land"), "An airborne skill is rejected")
	host.combat.set_motion(Vector3.ZERO,false,true)
	host.ability.reset()

	# Charge remains the unarmed fallback.
	equip(host.rig,"")
	var charge: Dictionary = host.ability.definition(0)
	check(str(charge.get("id","")) == "charge", "Empty hands fall back to Charge")
	host.stamina = Stamina.MAX
	check(bool(host.try_ability(0).get("ok",false)), "The unarmed Charge still starts")
	check(is_equal_approx(host.ability.velocity().length(),11.0), "Charge travels at 200% of the 5.5 m/s walk")
	var charge_state: Dictionary = host.rig.get_animation_state()
	var charge_code := int(round(float(charge_state.draw)))
	check((charge_code & 3) == 1 and ((charge_code >> 2)-1) == AbilityRules.index_of("charge"), "The unarmed charge packs its table index and slot")
	host.ability.advance(1.1)
	host.ability.reset()

	# Stagger and damage cancellation on a travelling skill.
	host.combat.stagger(0.2)
	host.ability.advance(0.01)
	check(not host.ability.active, "A stagger cancels an ability")
	host.combat.stagger_time = 0.0
	host.ability.reset()

	# Replication: snapshot carries the ability index, replicas decode the clip.
	equip(host.rig,"sword_great")
	host.stamina = Stamina.MAX
	check(bool(host.try_ability(0).get("ok",false)), "The greatsword starts its spin")
	var packed: Dictionary = host.snapshot()
	check(packed.has("stamina") and packed.has("ability"), "Snapshots carry stamina and ability state")
	check(int(AbilityRunner.unpack_snapshot(packed.ability).get("ability",-1)) == AbilityRules.index_of("spin_slash"), "Snapshots carry the ability index")
	check(JSON.stringify(packed).to_utf8_buffer().size() < 1100, "The fighter snapshot stays below the ENet MTU budget")
	var replica = Actor.new()
	replica.slot = 1
	replica.authoritative = false
	world.add_child(replica)
	replica.configure(2,false,"Replica",Vector3(2,0,0))
	replica.set_process(false)
	replica.rig.set_physics_process(false)
	replica.set_physics_process(false)
	equip(replica.rig,"sword_great")
	replica.apply_snapshot(packed)
	check(is_equal_approx(replica.stamina,host.stamina), "Stamina replicates to the replica")
	check(replica.ability.active and int(replica.ability.active_slot) == 0, "The active ability replicates")
	check(replica.ability.active_id == "spin_slash", "The replica recovers the active id from the wire index")
	check(not replica.ability.hud_state(0).is_empty(), "The replica HUD sees the granted skill")
	replica.rig.apply_animation_state(packed.animation)
	check(replica.rig.is_ability(), "The replicated pose plays the ability phase")
	check(replica.rig.ability_id == "spin_slash", "The replicated pose decodes the greatsword spin")
	check(is_equal_approx(replica.rig.ability_spin,1.0), "The replicated pose knows the spin data")
	host.ability.advance(2.0)

	# Off-hand shield skills occupy slot 1 beside the main-hand skill.
	equip(host.rig,"sword_arming","shield_tower")
	check(str(host.ability.definition(0).get("id","")) == "lunge_thrust", "The arming sword grants Lunge Thrust")
	check(str(host.ability.definition(1).get("id","")) == "shield_slam", "The tower shield grants Ground Shield Slam")
	check(str(host.ability.definition(1).get("key","")) == "SHIFT + 2", "The shield skill binds to Shift + 2")
	host.stamina = Stamina.MAX
	check(bool(host.try_ability(1).get("ok",false)), "The second hand slot activates independently")
	check(host.ability.active_slot == 1, "The active slot is the off hand")
	check(host.rig.ability_slot == 1, "The rig carries the off-hand slot")
	var packed_off: Dictionary = host.rig.get_animation_state()
	check(int(round(float(packed_off.draw))) & 3 == 2, "The animation state packs slot 2")
	host.ability.advance(2.0)

	# Frontier binding and HUD slots.
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await pause(0.8)
	check(game.ability != null and game.hud._ability_slot != null, "The frontier builds the ability runner and HUD slot")
	check(game.hud._off_ability_slot != null, "The frontier builds the off-hand ability slot")
	check(is_equal_approx(game.hud._stamina_bar.max_value,Stamina.MAX), "The frontier stamina bar uses the new pool")
	var stamina_before: float = game.stamina
	var event := InputEventKey.new()
	event.keycode = KEY_1
	event.physical_keycode = KEY_1
	event.pressed = true
	event.shift_pressed = true
	game._unhandled_input(event)
	check(game.ability.active and game.archer.is_ability(), "Shift + 1 starts the equipped bow skill")
	check(str(game.ability.active_id) == "barrage", "The starter shortbow fires Barrage")
	check(is_equal_approx(game.stamina,stamina_before-AbilityRules.TEST_STAMINA_COST), "The frontier skill spends its trivial cost")
	await pause(0.2)
	check(game.ability.active, "Barrage keeps its committed clock in the frontier")
	await pause(1.1)
	check(not game.ability.active and game.archer.phase == "READY", "Barrage ends on its own clock")
	equip(game.archer,"sword_arming","shield_kite")
	var shift_two := InputEventKey.new()
	shift_two.keycode = KEY_2
	shift_two.physical_keycode = KEY_2
	shift_two.pressed = true
	shift_two.shift_pressed = true
	game._unhandled_input(shift_two)
	check(game.ability.active and str(game.ability.active_id) == "shield_charge", "Shift + 2 starts the shield skill")
	check(game.ability.active_slot == 1, "Shift + 2 uses the off-hand slot")
	await pause(0.6)
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
	check(arena.hud._ability_slot != null and arena.hud._off_ability_slot != null, "The arena HUD builds both ability slots")
	seat.stamina = Stamina.MAX
	equip(seat.rig,"sword_great")
	arena._apply_action(0,"ability",0)
	check(seat.ability.active and seat.rig.is_ability(), "The arena host applies the greatsword action")
	check(seat.stamina < Stamina.MAX, "The arena skill spends stamina")
	arena._apply_action(0,"ability",99)
	check(seat.ability.active, "An invalid ability slot is ignored")
	# The hosted cue lands real damage on a second fighter.
	var victim = arena.actors[1]
	victim.set_physics_process(false)
	victim.global_position = seat.global_position + Vector3(0,0,-2.0)
	victim.health = 100.0
	victim.combat.stagger_time = 0.0
	seat.combat.set_aim(seat.global_position + Vector3(0,1,-5))
	await pause(0.75)
	check(victim.health < 100.0, "The arena spin cue damages the second fighter")
	check(is_equal_approx(victim.health,30.0), "The arena spin lands its 70 through the cue")
	arena.leave_game()
	await pause(0.2)
	arena.queue_free()
	await process_frame

	print("ABILITY_REGRESSION checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)


func _on_watchdog() -> void:
	push_error("Ability regression timed out")
	quit(1)
