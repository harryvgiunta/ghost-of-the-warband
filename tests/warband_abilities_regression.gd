extends SceneTree
## Warband abilities and HUD: a possessed body's three skills are reachable from
## the number row, the HUD reads stamina and the grants from that same body, stock
## steel carries no skill until the altar anoints it, the right mouse button
## guards and peeks out of cover, and the scene-level ability node resolves a cue
## into exactly one projectile on the authority only.

const Actor = preload("res://scripts/arena_actor.gd")
const State = preload("res://scripts/player_state.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const ControllerScript = preload("res://scripts/warband/possession_controller.gd")
const HudScript = preload("res://scripts/warband/warband_hud.gd")
const AbilitiesScript = preload("res://scripts/warband/warband_abilities.gd")
const CameraRig = preload("res://scripts/warband/possession_camera.gd")

const ARMOR := {"head": 0, "chest": 0, "hands": 0, "legs": 0, "feet": 0}

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WARBAND_ABILITIES_FAIL  ", message)


func _on_watchdog() -> void:
	check(false, "the regression did not finish in time")
	print("WARBAND_ABILITIES_REGRESSION checks=", checks, " failures=", failures)
	quit(1)


func key_event(code: Key, pressed: bool, shift: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.shift_pressed = shift
	return event


## Pump the real input path until `predicate` answers, or the timeout expires.
func _wait_until(predicate: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())


func mouse_event(button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


## The key line an ability tile currently reads.
func tile_key(tile) -> String:
	var label = tile.get("_key")
	return str(label.text) if label != null else ""


## A real arena body with its own rig, built the way the campaign spawns one.
func fighter(parent: Node3D, index: int, at: Vector3) -> Node3D:
	var actor := Actor.new()
	actor.slot = index
	actor.authoritative = true
	parent.add_child(actor)
	actor.configure(index + 1, false, "Probe", at)
	actor.set_process(false)
	actor.rig.set_physics_process(false)
	actor.set_physics_process(false)
	actor.combat.set_motion(Vector3.ZERO, false, true)
	actor.combat.target_mask = 1 | 2
	actor.combat.damage_enabled = true
	# A bare harness has no floor to stand on; the skills only ask that the body
	# is not falling.
	actor.combat.grounded = true
	return actor


func run() -> void:
	var watchdog := create_timer(30.0)
	watchdog.timeout.connect(_on_watchdog)
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	var actor := fighter(world, 0, Vector3.ZERO)
	# The opening beat hands the player an empty main hand: slot 0 falls back to
	# the legacy unarmed Charge.
	actor.rig.apply_loadout(State.build_loadout("", "", ARMOR))
	check(str(actor.rig.weapon) == "none", "an empty main hand holds nothing, got %s"
		% str(actor.rig.weapon))
	var charge: Dictionary = AbilityRules.definition_for(actor.rig, 0)
	check(str(charge.get("id", "")) == "charge", "an empty main hand grants Charge")

	var controller := ControllerScript.new()
	controller.name = "Controller"
	controller.auto_simulate = false
	world.add_child(controller)
	controller.active_actor = actor
	await _check_number_row(actor)
	_check_hud(world, actor)
	_check_peek(controller, actor)
	_check_peek_side(controller, actor, world)
	_check_ability_node(world, actor, controller)

	world.queue_free()
	print("WARBAND_ABILITIES_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


## Plain 1/2/3 is the warband's binding. The key travels through the real input
## pump, so the controller's own `_unhandled_input` is what answers.
func _check_number_row(actor) -> void:
	Input.parse_input_event(key_event(KEY_1, true))
	Input.flush_buffered_events()
	var started := await _wait_until(func(): return bool(actor.ability.active), 1.5)
	Input.parse_input_event(key_event(KEY_1, false))
	Input.flush_buffered_events()
	check(started, "KEY_1 starts slot 0")
	check(str(actor.ability.active_id) == "charge",
		"KEY_1 starts the Charge, got %s" % str(actor.ability.active_id))

	# Shift is not part of this binding: the same press with a held shift still
	# starts the skill, because the warband never asks for a modifier.
	actor.ability.cancel()
	actor.ability.cooldowns[0] = 0.0
	actor.stamina = actor.max_stamina
	Input.parse_input_event(key_event(KEY_1, true, true))
	Input.flush_buffered_events()
	var shifted := await _wait_until(func(): return bool(actor.ability.active), 1.5)
	Input.parse_input_event(key_event(KEY_1, false, true))
	Input.flush_buffered_events()
	check(shifted, "Shift+1 is the same press, not a requirement")
	actor.ability.cancel()
	actor.ability.cooldowns[0] = 0.0
	actor.stamina = actor.max_stamina


## The HUD reads the possessed body: stamina beside health, and one tile per
## skill slot labelled with the key that actually fires it.
func _check_hud(world: Node3D, actor) -> void:
	var hud := HudScript.new()
	hud.name = "Hud"
	world.add_child(hud)
	hud.set_body(actor, "Probe", 1)
	var bar: ProgressBar = hud.stamina_bar()
	check(bar != null, "the HUD owns a stamina bar")
	if bar != null:
		check(bar.max_value > 0.0, "the stamina bar has a positive maximum")
		check(is_equal_approx(bar.max_value, float(actor.max_stamina)),
			"the stamina bar reads the body's maximum, got %.1f vs %.1f"
			% [bar.max_value, float(actor.max_stamina)])
		check(is_equal_approx(bar.value, float(actor.stamina)),
			"the stamina bar reads the body's stamina, got %.1f vs %.1f"
			% [bar.value, float(actor.stamina)])
	var tiles: Array = hud.ability_tiles()
	check(tiles.size() == AbilityRules.SLOT_COUNT,
		"the HUD has one tile per skill slot, got %d" % tiles.size())
	for index in tiles.size():
		check(str(tiles[index].name) == "Ability%d" % (index + 1),
			"tile %d is named Ability%d" % [index, index + 1])
	check(tiles[0].visible, "the granted slot is shown")
	check(tile_key(tiles[0]) == "1", "the first tile is labelled 1, got %s"
		% tile_key(tiles[0]))
	check(not tiles[1].visible, "a hand with no grant hides its tile")

	# Stock steel carries no skill: a dagger and a buckler off the shelf leave both
	# hand tiles dark, while the amulet's grant is worn, not anointed, and shows.
	actor.rig.apply_loadout(State.build_loadout("dagger_iron", "shield_buckler", ARMOR,
		{"neck": "neck_shield"}))
	actor.stamina = actor.max_stamina
	hud.set_body(actor, "Probe", 1)
	check(not tiles[0].visible and not tiles[1].visible,
		"stock steel in both hands shows no hand tile")
	check(tiles[2].visible, "the worn amulet still shows its grant")

	# The same kit anointed grants all three slots: main hand, shield and amulet.
	actor.rig.apply_loadout(State.build_loadout("dagger_iron", "shield_buckler", ARMOR,
		{"neck": "neck_shield"}, ["dagger_iron", "shield_buckler"]))
	hud.set_body(actor, "Probe", 1)
	for index in tiles.size():
		check(tiles[index].visible, "slot %d is shown for an anointed kit" % index)
		check(tile_key(tiles[index]) == str(index + 1),
			"tile %d is labelled %d, got %s" % [index, index + 1,
			tile_key(tiles[index])])
	hud.set_body(null, "", -1)
	check(not tiles[0].visible, "no body hides every tile")
	hud.queue_free()


## RMB in cover is a guard that also leans out; outside cover it is only a
## guard, and releasing either one settles the body back.
func _check_peek(controller, actor) -> void:
	actor.cover.active = true
	controller._unhandled_input(mouse_event(MOUSE_BUTTON_RIGHT, true))
	check(bool(actor.peek_requested), "RMB in cover asks for a peek")
	check(bool(actor.combat.blocking), "RMB in cover keeps the guard up")
	controller._input(mouse_event(MOUSE_BUTTON_RIGHT, false))
	check(not bool(actor.peek_requested), "releasing RMB ends the peek")
	check(not bool(actor.combat.blocking), "releasing RMB drops the guard")

	actor.cover.active = false
	controller._unhandled_input(mouse_event(MOUSE_BUTTON_RIGHT, true))
	check(not bool(actor.peek_requested), "RMB outside cover does not peek")
	check(bool(actor.combat.blocking), "RMB outside cover still guards")
	controller._input(mouse_event(MOUSE_BUTTON_RIGHT, false))
	check(not bool(actor.combat.blocking), "the outside guard is released too")


## The peek side follows the shoulder: `_drive` writes the camera right vector
## into the body, and the same wall is leaned out of on the other side when the
## eye crosses.
func _check_peek_side(controller, actor, world: Node3D) -> void:
	var rig := CameraRig.new()
	rig.name = "Sight"
	world.add_child(rig)
	controller.camera_rig = rig
	actor.cover.active = true
	actor.cover.normal = Vector3(-1.0, 0.0, 0.0)
	rig.yaw = PI * 0.5
	controller._drive(actor)
	check(actor.peek_view_right.distance_to(Vector3(0.0, 0.0, -1.0)) < 0.01,
		"the peek view follows the camera right, got %s" % str(actor.peek_view_right))
	check(int(actor.combat.cover_side) == 1,
		"the peek side is the shoulder side, got %d" % int(actor.combat.cover_side))
	rig.yaw = -PI * 0.5
	controller._drive(actor)
	check(actor.peek_view_right.distance_to(Vector3(0.0, 0.0, 1.0)) < 0.01,
		"the peek view crosses with the shoulder, got %s" % str(actor.peek_view_right))
	check(int(actor.combat.cover_side) == -1,
		"the peek side crosses with the shoulder, got %d" % int(actor.combat.cover_side))
	actor.cover.active = false
	controller.camera_rig = null
	rig.queue_free()


## The scene half: binding is idempotent, a cue on the authority spawns one
## projectile, and a replica's cue is ignored.
func _check_ability_node(world: Node3D, actor, controller) -> void:
	var abilities = AbilitiesScript.new()
	abilities.name = "WarbandAbilities"
	world.add_child(abilities)
	abilities.setup(world, controller)
	abilities.bind_body(actor)
	abilities.bind_body(actor)
	check(abilities.bound_bodies().size() == 1,
		"binding one body twice leaves one connection, got %d"
		% abilities.bound_bodies().size())

	# A stock bow carries nothing: slot 0 is empty and its key starts nothing.
	actor.rig.apply_loadout(State.build_loadout("bow_short", "", ARMOR))
	check(AbilityRules.definition_for(actor.rig, 0).is_empty(), "a stock shortbow grants no skill")
	actor.stamina = actor.max_stamina
	actor.combat.grounded = true
	check(not bool(actor.try_ability(0).get("ok", true)), "the stock bow's key starts nothing")

	# Anointed, the same bow wakes into the Barrage, whose cue spawns arrows.
	actor.rig.apply_loadout(State.build_loadout("bow_short", "", ARMOR, {}, ["bow_short"]))
	check(str(AbilityRules.definition_for(actor.rig, 0).get("id", "")) == "barrage",
		"the anointed shortbow grants the Barrage")
	var outcome: Dictionary = actor.try_ability(0)
	check(bool(outcome.get("ok", false)), "the Barrage starts")
	actor.ability.cue.emit("barrage", "shot", 0)
	check(abilities.missiles().size() == 1,
		"one cue spawns one arrow, got %d" % abilities.missiles().size())

	# A body that does not own the simulation must not spawn a second one, even
	# if its runner is still holding the skill.
	actor.authoritative = false
	actor.ability.cue.emit("barrage", "shot", 1)
	check(abilities.missiles().size() == 1,
		"a replica's cue spawns nothing, got %d" % abilities.missiles().size())
	actor.authoritative = true
	actor.ability.cancel()

	# A staff cast resolves through the same node: the spell projectile is the
	# second missile, and its blast is wired to the body's own combat.
	actor.rig.apply_loadout(State.build_loadout("staff_fire", "", ARMOR, {}, ["staff_fire"]))
	check(str(AbilityRules.definition_for(actor.rig, 0).get("id", "")) == "fireball",
		"the anointed ember staff grants the Fireball")
	actor.stamina = actor.max_stamina
	actor.combat.grounded = true
	check(bool(actor.try_ability(0).get("ok", false)), "the Fireball starts")
	actor.ability.advance(0.6)
	check(abilities.missiles().size() == 2,
		"the cast cue spawns the spell, got %d missiles" % abilities.missiles().size())
	actor.ability.cancel()
	abilities.queue_free()
