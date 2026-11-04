extends SceneTree
## Warband abilities and HUD: a possessed body's three skills are reachable from
## the number row, the HUD reads stamina and the grants from that same body, stock
## steel carries no skill until the altar anoints it, the right mouse button
## guards and peeks out of cover, and the scene-level ability node resolves a cue
## into exactly one projectile on the authority only.

const Actor = preload("res://scripts/warband/warband_body.gd")
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


## The skill a tile is currently drawing, "" for an empty tile.
func tile_id(tile) -> String:
	var definition = tile.get("_definition")
	return str(definition.get("id", "")) if definition is Dictionary else ""


## A real arena body with its own rig, built the way the campaign spawns one.
func fighter(parent: Node3D, index: int, at: Vector3) -> Node3D:
	var actor := Actor.new()
	actor.slot = index
	actor.authoritative = true
	parent.add_child(actor)
	actor.configure(index + 1, "Probe", at)
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


## The number row is the warband's binding, and the tenth slot rides the 0 key.
## The key travels through the real input pump, so the controller's own
## `_unhandled_input` is what answers.
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

	# The kit's skills take the first eight keys; the bandage and the potion keep
	# the last two. A bow with every bow weld plus the shield pool and the amulet's
	# ward is more grants than the eight keys before the consumables, so the
	# surplus waits and the two consumables are always on the bar.
	actor.rig.apply_loadout(State.build_loadout("bow_short", "", ARMOR))
	actor.rig.anointed = {"main": AbilityRules.skill_ids([
		"barrage", "triple_volley", "piercing_shot", "rain_of_ash", "skewer",
		"shield_bash", "shield_charge", "shield_slam", "rebuke", "energy_shield",
	]), "off": []}
	var grants: Array = AbilityRules.granted(actor.rig)
	check(grants.size() == AbilityRules.SLOT_COUNT,
		"ten grants fill ten slots")
	check(not grants[7].is_empty(),
		"the eighth key is the kit's last skill, got %s" % str(grants[7].get("id", "")))
	check(str(grants[8].get("id", "")) == "bandage"
			and str(grants[9].get("id", "")) == "healing_potion",
		"the last two keys are the bandage and the potion, got %s / %s"
		% [str(grants[8].get("id", "")), str(grants[9].get("id", ""))])

	# A whole body is refused its dressing and its draught with the line the
	# player can act on. The channel itself belongs to the body (`try_consume`);
	# this harness has no floor to stand on, so only the refusal is exercised.
	actor.health = actor.max_health
	var dressing: Dictionary = actor.ability.activate(8)
	check(not bool(dressing.get("ok", true))
			and str(dressing.get("message", "")).contains("not wounded"),
		"key 9 answers a whole body, got %s" % str(dressing.get("message", "")))
	var draught: Dictionary = actor.ability.activate(9)
	check(not bool(draught.get("ok", true))
			and str(draught.get("message", "")).contains("not wounded"),
		"key 0 answers a whole body, got %s" % str(draught.get("message", "")))
	actor.ability.cancel()
	actor.ability.reset()
	actor.rig.apply_loadout(State.build_loadout("", "", ARMOR))
	actor.stamina = actor.max_stamina


## The HUD reads the possessed body: stamina beside health, and one hotbar tile
## per slot labelled with the key that actually fires it.
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
		"the hotbar has one tile per slot, got %d" % tiles.size())
	check(tiles.size() == 10, "the hotbar is ten keys, got %d" % tiles.size())
	for index in tiles.size():
		check(str(tiles[index].name) == "Ability%d" % (index + 1),
			"tile %d is named Ability%d" % [index, index + 1])
	check(tiles[0].visible and tile_id(tiles[0]) == "charge",
		"the granted slot is shown")
	check(tile_key(tiles[0]) == "1", "the first tile is labelled 1, got %s"
		% tile_key(tiles[0]))
	check(tiles[1].visible and tile_id(tiles[1]).is_empty(),
		"a hand with no grant keeps an empty numbered slot")

	# Stock steel carries no skill: a dagger and a buckler off the shelf leave the
	# hand slots empty, while the amulet's worn grant takes the first free slot.
	actor.rig.apply_loadout(State.build_loadout("dagger_iron", "shield_buckler", ARMOR,
		{"neck": "neck_shield"}))
	actor.stamina = actor.max_stamina
	hud.set_body(actor, "Probe", 1)
	check(tile_id(tiles[0]) == "energy_shield",
		"the worn amulet's grant takes slot 1, got %s" % tile_id(tiles[0]))
	check(tile_id(tiles[1]).is_empty() and tile_key(tiles[1]) == "2",
		"stock steel in both hands leaves the second slot empty and numbered")

	# The same kit anointed grants three skills: main hand, shield and amulet.
	actor.rig.apply_loadout(State.build_loadout("dagger_iron", "shield_buckler", ARMOR,
		{"neck": "neck_shield"}, ["dagger_iron", "shield_buckler"]))
	hud.set_body(actor, "Probe", 1)
	var anointed_ids := ["backstab", "shield_bash", "energy_shield"]
	check(_granted(tiles) == anointed_ids.size() + 2,
		"an anointed kit fills three slots and the two consumables fill the last two, got %d"
		% _granted(tiles))
	for index in anointed_ids.size():
		check(tile_id(tiles[index]) == anointed_ids[index],
			"slot %d draws %s, got %s" % [index, anointed_ids[index],
			tile_id(tiles[index])])
		check(tile_key(tiles[index]) == str(index + 1),
			"tile %d is labelled %d, got %s" % [index, index + 1,
			tile_key(tiles[index])])

	# The bug this exists for: a piece can carry several welded skills and every
	# worn trinket can grant one, so each has to take its own hotbar slot instead
	# of being hidden behind the first.
	actor.rig.apply_loadout(State.build_loadout("bow_short", "", ARMOR,
		{"neck": "neck_shield", "ring1": "ring_dash"}))
	actor.rig.anointed = {"main": AbilityRules.skill_ids(["barrage", "triple_volley"]),
		"off": []}
	hud.set_body(actor, "Probe", 1)
	var welded_ids := ["barrage", "triple_volley", "energy_shield", "dash"]
	check(_granted(tiles) == welded_ids.size() + 2,
		"two welded skills, two trinkets and the two consumables fill six slots, got %d"
		% _granted(tiles))
	for index in welded_ids.size():
		check(tile_id(tiles[index]) == welded_ids[index],
			"slot %d draws %s, got %s" % [index, welded_ids[index],
			tile_id(tiles[index])])
		check(tile_key(tiles[index]) == str(index + 1),
			"hotbar slot %d keeps its number, got %s" % [index + 1,
			tile_key(tiles[index])])
	check(tile_id(tiles[welded_ids.size()]).is_empty(),
		"the rest of the kit's keys stay empty")
	check(tile_id(tiles[AbilityRules.SLOT_COUNT - 2]) == "bandage"
			and tile_id(tiles[AbilityRules.SLOT_COUNT - 1]) == "healing_potion",
		"the bandage and the potion keep the last two keys")
	check(tile_key(tiles[AbilityRules.SLOT_COUNT - 1]) == "10",
		"the tenth slot is labelled 10, got %s"
		% tile_key(tiles[AbilityRules.SLOT_COUNT - 1]))

	# Hand the later checks a melee kit back: the guard checks below need a blade
	# in the hand, and this test's last kit is a bow.
	actor.rig.apply_loadout(State.build_loadout("dagger_iron", "shield_buckler", ARMOR,
		{"neck": "neck_shield"}, ["dagger_iron", "shield_buckler"]))
	actor.stamina = actor.max_stamina

	hud.set_body(null, "", -1)
	check(not tiles[0].visible, "no body hides every tile")
	hud.queue_free()


## How many hotbar slots are drawing a skill this frame.
func _granted(tiles: Array) -> int:
	var out := 0
	for tile in tiles:
		if not tile_id(tile).is_empty():
			out += 1
	return out


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
	_check_necklace(world, actor, abilities)
	abilities.queue_free()


## The necklace's three words on a real rig and a real victim: a landed blow is
## the attack-side edge (Quick Hit asks for a five-times swing on the next tick),
## a poison walks the body it opened, and the welded three-strike is a skill of
## three waves that each stop at three bodies.
func _check_necklace(world: Node3D, actor, abilities) -> void:
	var catalog = preload("res://scripts/warband/annoint_catalog.gd")
	var victim := fighter(world, 4, Vector3(0.0, 0.0, -1.7))
	victim.health = 900.0
	victim.max_health = 900.0
	actor.rig.apply_loadout(State.build_loadout("sword_short", "", ARMOR,
		{"neck": "neck_bone"}))
	actor.combat.aim_point = victim.global_position + Vector3.UP * 1.0
	actor.stamina = actor.max_stamina
	actor.combat.grounded = true

	# --- Quick Hit: the blow lands, the body is asked for a fast second swing
	var normal := 0.0
	if actor.rig.begin_melee("right"):
		normal = float(actor.rig.melee_seconds("right"))
		actor.rig.abort_melee("right")
	check(normal > 0.05, "the rig could not raise a plain swing to time against")
	actor.apply_annointments({}, [catalog.by_id("j_quick_hit")])
	check(actor.annoint_playback.armed_count() == 1, "the necklace proc did not arm")
	var before_health: float = victim.health
	for i in 200:
		# A landed blow named by `Combat`, exactly as a real contact names it.
		actor.note_attack_landed(victim, "right")
	check(victim.health <= before_health, "naming a blow must not wound the victim twice")
	check(actor.annoint_playback._strikes.size() > 0,
		"the 20% beak never queued a second swing")
	# The queue is walked on the tick, and the swing it raises is five times as
	# fast as the plain one it interrupts.
	var began := false
	for i in 4:
		actor.annoint_playback.tick(0.016)
		if actor.rig.melee_seconds("right") < normal * 0.5:
			began = true
			break
	check(began, "the queued quick strike never raised a faster swing")

	# --- Poison Hit: a landed blow lays a dot on the body it opened
	var poison_victim := fighter(world, 5, Vector3(0.9, 0.0, -1.7))
	poison_victim.health = 900.0
	poison_victim.max_health = 900.0
	actor.apply_annointments({}, [catalog.by_id("j_poison_hit")])
	var start: float = poison_victim.health
	for i in 300:
		actor.note_attack_landed(poison_victim, "right")
	check(actor.annoint_playback._dots.size() == 1,
		"the poison never landed on a real body")
	for i in 120:
		actor.annoint_playback.tick(0.05)
	check(poison_victim.health < start - 5.0,
		"the poison dealt %.1f to a real body" % (start - poison_victim.health))

	# --- Stone Skin: a ward the cord itself performs, on any hand
	actor.rig.apply_loadout(State.build_loadout("sword_short", "", ARMOR,
		{"neck": "neck_bone"}))
	actor.rig.anointed = {"main": [], "off": [], "neck": ["stone_skin"]}
	actor.stamina = actor.max_stamina
	actor.combat.grounded = true
	var ward_slot := -1
	var ward_grants: Array = AbilityRules.granted(actor.rig)
	for index in ward_grants.size():
		if str(ward_grants[index].get("id", "")) == "stone_skin":
			ward_slot = index
	check(ward_slot >= 0, "the cord's ward never reached the hotbar")
	check(bool(actor.try_ability(ward_slot).get("ok", false)), "Stone Skin starts")
	check(float(actor.ward_seconds) > 0.0, "Stone Skin never started a ward")
	check(absf(float(actor.ward_absorb) - 0.33) < 0.001,
		"Stone Skin absorbed %.2f, expected a third" % float(actor.ward_absorb))
	actor.ability.cancel()

	# --- the welded three-strike: three waves, three bodies apiece
	actor.apply_annointments({}, [])
	# Five bodies packed inside the 2.4 m reach and the 130 degree arc, so the
	# only thing that can spare two of them is the wave's own three-body cap.
	var spots := [Vector3(0.0, 0.0, -1.0), Vector3(-0.5, 0.0, -1.2),
		Vector3(0.5, 0.0, -1.2), Vector3(0.0, 0.0, -1.8), Vector3(-0.8, 0.0, -1.6)]
	var lineup: Array = []
	for index in spots.size():
		var dummy := fighter(world, 10 + index, spots[index])
		dummy.health = 1200.0
		dummy.max_health = 1200.0
		lineup.append(dummy)
	actor.rig.apply_loadout(State.build_loadout("sword_short", "dagger_iron", ARMOR,
		{"neck": "neck_bone"}))
	actor.rig.anointed = {"main": [], "off": [], "neck": ["three_strike"]}
	var grants: Array = AbilityRules.granted(actor.rig)
	var slot := -1
	for index in grants.size():
		if str(grants[index].get("id", "")) == "three_strike":
			slot = index
	check(slot >= 0, "a welded necklace skill never reached the hotbar")
	# The harness's own bodies ride layer 4 and the arena's mask is "world and
	# mobs"; the wave has to be asked to cut the bodies standing in it.
	actor.combat.target_mask = 1 | 4
	actor.combat.aim_point = Vector3(0.0, 0.0, -2.8)
	actor.stamina = actor.max_stamina
	actor.combat.grounded = true
	check(bool(actor.try_ability(slot).get("ok", false)), "the three-strike starts")
	# The skill plays its own three-cut clip, not the two-cut double slash it
	# used to share, and the clip authors both wrists: the rig keeps the off arm
	# so a dual pair sweeps two blades.
	check(str(actor.rig.ability_clip) == "Sword_Three_Strike",
		"the three-strike plays its own sweep clip, got %s" % str(actor.rig.ability_clip))
	check(actor.rig.has_clip("Sword_Three_Strike"),
		"the shipped rig carries the three-strike's sweep clip")
	check(bool(actor.rig.ability_offhand_authored),
		"the sweep clip keeps its authored off hand on a dual pair")
	# The wave lands on the frame its cut does: the clip's impacts are at 0.20,
	# 0.50 and 0.80 of its length and the three cues divide by the duration to
	# exactly those beats.
	var definition := AbilityRules.by_id("three_strike")
	var seconds := maxf(float(definition.get("duration", 0.0)), 0.01)
	var cue_beats: Array = definition.get("cues", [])
	check(is_equal_approx(float(cue_beats[0].get("at", 0.0)) / seconds, 0.20)
			and is_equal_approx(float(cue_beats[1].get("at", 0.0)) / seconds, 0.50)
			and is_equal_approx(float(cue_beats[2].get("at", 0.0)) / seconds, 0.80),
		"the three cues sit on the clip's cut beats (0.20, 0.50, 0.80)")
	# Every wave sends its own ripple out to the arc it cut.
	var ripples: Array[int] = []
	for beat in 4:
		actor.ability.advance(0.24)
		ripples.append(world.find_children("AbilityWaveRipple*", "Node3D", true, false).size())
	check(ripples[0] == 1 and ripples[1] == 2 and ripples[2] == 3,
		"each wave sends one ripple, got %s" % str(ripples))
	# And each wave carries a real floor wavefront instead of a hoop: the cut's
	# own arc, laid on the ground and opened out to the wave's reach. A ring
	# around the body is exactly what this effect must never be.
	var hoops := 0
	var wavefronts := 0
	for node in world.find_children("AbilityWaveRipple*", "Node3D", true, false):
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh is TorusMesh or mesh.mesh is SphereMesh:
				hoops += 1
		wavefronts += node.find_children("Wavefront*", "Node3D", true, false).size()
	check(hoops == 0, "a wave must not draw a hoop around the body, got %d" % hoops)
	check(wavefronts >= 3, "each wave sends a floor wavefront, got %d" % wavefronts)
	var hurt: int = 0
	var per_body: Array[float] = []
	for dummy in lineup:
		var lost: float = 1200.0 - float(dummy.health)
		per_body.append(lost)
		if lost > 0.0:
			hurt += 1
	check(hurt == 3, "a wave reached %d bodies, the cap is three" % hurt)
	check(per_body[0] > 0.0 and per_body[1] > 0.0 and per_body[2] > 0.0,
		"the wave skipped one of the three nearest: %s" % str(per_body))
	check(per_body[3] == 0.0 and per_body[4] == 0.0,
		"a body past the third of the rank was cut: %s" % str(per_body))
	# Every one of the three waves went into that rank, so each of the three took
	# three cuts rather than one.
	check(per_body[0] > per_body[1] * 0.9 and per_body[1] > 0.0,
		"the three were not cut alike: %s" % str(per_body))
	# The clip authors both wrists; with the flag off the rig would re-solve the
	# off hand to the neutral carry and the left blade would hang at the hip
	# instead of sweeping. Same clip, same beat, two poses: the authored one lifts
	# the off hand away from the carry line.
	actor.ability.cancel()
	var carried: Dictionary = definition.duplicate(true)
	carried["offhand_authored"] = false
	actor.rig.begin_ability(carried, Vector3.FORWARD)
	actor.rig.advance_animation(0.40)
	var carry_wrist: Vector3 = actor.rig.get_joint_positions()["left_wrist"]
	actor.rig.cancel_ability()
	actor.rig.begin_ability(definition.duplicate(true), Vector3.FORWARD)
	actor.rig.advance_animation(0.40)
	var authored_wrist: Vector3 = actor.rig.get_joint_positions()["left_wrist"]
	check(authored_wrist.distance_to(carry_wrist) > 0.15,
		"the sweep keeps its authored off arm, %.2f m from the carry pose"
		% authored_wrist.distance_to(carry_wrist))
	actor.rig.cancel_ability()
	actor.ability.cancel()
	print("  necklace: quick hit %.2fs -> %.2fs, poison, three-strike %s" % [
		normal, normal / 5.0, str(per_body)])
