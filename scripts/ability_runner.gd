extends Node
## Per-actor ability lifecycle: eligibility, stamina spend, cooldown, committed
## travel, timed effect cues and the rig's ability animation.
##
## The runner never applies damage. A cue is a named beat in the definition
## (`cues`); the scene that owns authority turns it into arrows, a blast or a
## sector of damage. Item-granted definitions are resolved from the rig's
## current hands, so equipping a different weapon changes the skill.

signal activated(id: String, definition: Dictionary)
signal cue(id: String, cue: String, index: int)
signal finished(id: String)

const AbilityRules = preload("res://scripts/ability_rules.gd")

var actor
var rig
var combat
var base_speed := 5.5
var active := false
var active_id := ""
var active_slot := -1
var active_definition: Dictionary = {}
var elapsed := 0.0
var duration := 0.0
var speed := 0.0
var travel_seconds := 0.0
var direction := Vector3.FORWARD
## Bodies already struck during this activation. A travelling skill sweeps the
## lane every tick and shares this set with its closing beat, so each body is
## only ever hit once per activation.
var active_victims: Dictionary = {}
var cooldowns := PackedFloat32Array()
var _cue_index := 0
var _grant_ids: Array[String] = []


func setup(owner_actor, owner_rig, owner_combat, walk_speed: float) -> void:
	actor = owner_actor
	rig = owner_rig
	combat = owner_combat
	base_speed = maxf(walk_speed, 0.1)
	cooldowns.resize(AbilityRules.SLOT_COUNT)
	cooldowns.fill(0.0)
	_grant_ids.resize(AbilityRules.SLOT_COUNT)
	_grant_ids.fill("")
	_refresh_grants()


func definition(slot: int) -> Dictionary:
	return AbilityRules.definition_for(rig, slot)


func blocker(slot: int = 0) -> String:
	var definition := definition(slot)
	if definition.is_empty():
		return "That hand grants no skill."
	return _blocker(definition, slot)


func activate(slot: int = 0) -> Dictionary:
	_refresh_grants()
	var definition := definition(slot)
	var reason := blocker(slot)
	if not reason.is_empty():
		return {"ok": false, "message": reason}
	# A blade skill or a committed dash needs an upright stance: cancel the
	# crouch first and only spend the cost once the body can actually stand.
	if AbilityRules.needs_standing(definition) and not _stand_before_melee():
		return {"ok": false, "message": "Not enough headroom to stand for %s."
			% str(definition.name).capitalize()}
	var cost := float(definition.stamina_cost)
	var facing := _facing(definition)
	actor.stamina = maxf(0.0, float(actor.stamina) - cost)
	if slot >= 0 and slot < cooldowns.size():
		cooldowns[slot] = float(definition.cooldown) * AbilityRules.cooldown_scale(rig)
	active = true
	active_id = str(definition.id)
	active_slot = slot
	active_definition = definition
	active_victims.clear()
	elapsed = 0.0
	duration = maxf(float(definition.duration), 0.01)
	travel_seconds = clampf(float(definition.get("travel_seconds", definition.duration)), 0.0, duration)
	speed = base_speed * maxf(float(definition.get("speed_scale", 0.0)), 0.0)
	direction = facing
	_cue_index = 0
	# A timed body state (the energy shield) starts with the activation; the
	# owner applies it so the reward and the bubble cannot disagree.
	if actor != null and is_instance_valid(actor) and actor.has_method("start_ward"):
		actor.start_ward(definition)
	rig.begin_ability(definition, direction)
	activated.emit(active_id, definition)
	_emit_due_cues()
	return {"ok": true, "definition": definition}


## The line the skill is performed down. A travelling skill follows the live
## crosshair, so the dash lands where the player is looking; everything else
## keeps the heading the key was pressed from. The direction is locked for the
## activation, so the committed step never curves with the mouse.
func _facing(definition: Dictionary) -> Vector3:
	var facing: Vector3 = -rig.global_basis.z
	facing.y = 0.0
	if AbilityRules.follows_aim(definition) and is_instance_valid(combat):
		var offset: Vector3 = combat.aim_point - rig.global_position
		offset.y = 0.0
		if offset.length_squared() > 0.000001:
			facing = offset
	if facing.length_squared() < 0.000001:
		return Vector3.FORWARD
	return facing.normalized()


## A skill that cannot be performed from a crouch stands the owner up first. The rig drops its own crouch blend in `begin_ability`;
## the controller owns the capsule, the camera height and the crouch intent.
func _stand_before_melee() -> bool:
	if is_instance_valid(combat) and is_instance_valid(combat.cover):
		return combat.cover.force_stand()
	return true


func _blocker(definition: Dictionary, slot: int) -> String:
	var ability_name := str(definition.name).capitalize()
	if active:
		return "Already using %s." % ability_name
	if actor.get("alive") == false:
		return "You are down."
	if is_instance_valid(combat) and not combat.grounded:
		return "Land before using %s." % ability_name
	if is_instance_valid(combat) and combat.stagger_time > 0.0:
		return "Recover your footing before using %s." % ability_name
	if is_instance_valid(combat) and combat.blocking:
		return "Drop your guard before using %s." % ability_name
	if is_instance_valid(combat) and is_instance_valid(combat.cover) and combat.cover.active:
		return "Leave cover before using %s." % ability_name
	if float(rig._roll_progress) >= 0.0 or float(rig.slide_progress) >= 0.0 \
			or float(rig._step_progress) >= 0.0:
		return "Finish the movement before using %s." % ability_name
	if str(rig.phase) != "READY" or rig.is_consuming():
		return "Finish the current action before using %s." % ability_name
	if slot >= 0 and slot < cooldowns.size() and cooldowns[slot] > 0.0:
		return "%s ready in %.1f s." % [ability_name, cooldowns[slot]]
	if float(actor.stamina) < float(definition.stamina_cost):
		return "Not enough stamina for %s." % ability_name
	return ""


func advance(delta: float) -> void:
	for index in cooldowns.size():
		cooldowns[index] = maxf(0.0, cooldowns[index] - delta)
	_refresh_grants()
	if not active:
		return
	if not is_instance_valid(rig) or not rig.is_ability() \
			or (is_instance_valid(combat) and combat.stagger_time > 0.0) \
			or actor.get("alive") == false:
		_finish()
		return
	elapsed += delta
	_emit_due_cues()
	if elapsed >= duration:
		if rig.is_ability():
			rig.cancel_ability()
		_finish()


## A weapon swap cancels the trailing cooldown of the weapon being put away.
## That keeps a testing session able to fire every skill back to back; the
## cost prevents swap-spam from being a free damage loop.
func _refresh_grants() -> void:
	if not is_instance_valid(rig):
		return
	var grants := AbilityRules.granted(rig)
	for slot in mini(AbilityRules.SLOT_COUNT, _grant_ids.size()):
		var id := str(grants[slot].get("id", ""))
		if id != _grant_ids[slot]:
			_grant_ids[slot] = id
			if slot < cooldowns.size():
				cooldowns[slot] = 0.0


func _emit_due_cues() -> void:
	var cues: Array = active_definition.get("cues", [])
	while _cue_index < cues.size() and elapsed >= float(cues[_cue_index].get("at", 0.0)):
		var beat: Dictionary = cues[_cue_index]
		cue.emit(active_id, str(beat.get("cue", "")), _cue_index)
		_cue_index += 1


func cancel() -> void:
	if not active:
		return
	if is_instance_valid(rig) and rig.is_ability():
		rig.cancel_ability()
	_finish()


func reset() -> void:
	active = false
	active_id = ""
	active_slot = -1
	active_definition = {}
	active_victims.clear()
	elapsed = 0.0
	duration = 0.0
	speed = 0.0
	travel_seconds = 0.0
	_cue_index = 0
	cooldowns.fill(0.0)
	if is_instance_valid(rig) and rig.is_ability():
		rig.cancel_ability()


func velocity() -> Vector3:
	return direction * speed if active and elapsed <= travel_seconds else Vector3.ZERO


## Melee skills keep the owner's walking input; ranged casts, the unarmed
## charge and the backstab blink plant the feet for the duration. Controllers
## ask this instead of `active` before they drop the movement intent.
func allows_movement() -> bool:
	return active and bool(active_definition.get("move", false))


func hud_state(slot: int = 0) -> Dictionary:
	var definition := definition(slot)
	if definition.is_empty():
		return {}
	var cost := float(definition.stamina_cost)
	return {
		"slot": slot,
		"id": str(definition.id),
		"name": str(definition.name),
		"key": str(definition.key),
		"item": str(definition.get("item", "")),
		"active": active and active_slot == slot,
		"elapsed": elapsed if active_slot == slot else 0.0,
		"duration": duration if active_slot == slot else float(definition.duration),
		"cooldown": cooldowns[slot] if slot < cooldowns.size() else 0.0,
		"stamina_cost": cost,
		"affordable": float(actor.stamina) >= cost if is_instance_valid(actor) else true,
	}


func snapshot() -> Dictionary:
	var index := AbilityRules.index_of(active_id) if active else -1
	return {
		"active": active,
		"slot": active_slot,
		"ability": index,
		"time": elapsed,
		"duration": duration,
		"cooldowns": Array(cooldowns),
	}


func apply_snapshot(state: Dictionary) -> void:
	active = bool(state.get("active", false))
	active_slot = int(state.get("slot", -1))
	active_id = ""
	active_definition = {}
	if active:
		var index := int(state.get("ability", -1))
		if index >= 0:
			active_definition = AbilityRules.by_index(index)
			active_id = str(active_definition.get("id", ""))
	elapsed = float(state.get("time", 0.0))
	duration = float(state.get("duration", 0.0))
	# A replica must not replay cues the host already fired before the first
	# snapshot of this activation arrived.
	_cue_index = 0
	if active:
		var cues: Array = active_definition.get("cues", [])
		while _cue_index < cues.size() and elapsed >= float(cues[_cue_index].get("at", 0.0)):
			_cue_index += 1
	var values: Variant = state.get("cooldowns", [])
	if values is Array:
		for index in mini(cooldowns.size(), values.size()):
			cooldowns[index] = float(values[index])


func _finish() -> void:
	if not active:
		return
	var ended := active_id
	active = false
	active_id = ""
	active_slot = -1
	active_definition = {}
	active_victims.clear()
	elapsed = 0.0
	duration = 0.0
	speed = 0.0
	travel_seconds = 0.0
	_cue_index = 0
	finished.emit(ended)
