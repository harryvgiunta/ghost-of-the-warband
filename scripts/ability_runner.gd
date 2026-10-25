extends Node
## Per-actor ability lifecycle: eligibility, stamina spend, cooldown, committed
## travel and the rig's ability animation.
##
## The runner never applies damage. An ability effect belongs to the definition
## and the scene that owns authority; this class only owns the shared state that
## the frontier, arena and delve must agree on.

signal activated(id: String, definition: Dictionary)
signal finished(id: String)

const AbilityRules = preload("res://scripts/ability_rules.gd")

var actor
var rig
var combat
var base_speed := 5.5
var active := false
var active_id := ""
var active_slot := -1
var elapsed := 0.0
var duration := 0.0
var speed := 0.0
var direction := Vector3.FORWARD
var cooldowns := PackedFloat32Array()


func setup(owner_actor, owner_rig, owner_combat, walk_speed: float) -> void:
	actor = owner_actor
	rig = owner_rig
	combat = owner_combat
	base_speed = maxf(walk_speed, 0.1)
	cooldowns.resize(AbilityRules.SLOT_COUNT)
	cooldowns.fill(0.0)


func blocker(slot: int = 0) -> String:
	var definition := AbilityRules.by_slot(slot)
	if definition.is_empty():
		return "No ability is bound to that slot."
	return _blocker(definition, slot)


func activate(slot: int = 0) -> Dictionary:
	var definition := AbilityRules.by_slot(slot)
	var reason := blocker(slot)
	if not reason.is_empty():
		return {"ok": false, "message": reason}
	var cost := float(definition.stamina_cost)
	var facing: Vector3 = -rig.global_basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.000001:
		facing = Vector3.FORWARD
	actor.stamina = maxf(0.0, float(actor.stamina) - cost)
	if slot >= 0 and slot < cooldowns.size():
		cooldowns[slot] = float(definition.cooldown)
	active = true
	active_id = str(definition.id)
	active_slot = slot
	elapsed = 0.0
	duration = maxf(float(definition.duration), 0.01)
	speed = base_speed * maxf(float(definition.speed_scale), 0.0)
	direction = facing.normalized()
	rig.begin_ability(slot, active_id, str(definition.animation), duration, direction)
	activated.emit(active_id, definition)
	return {"ok": true, "definition": definition}


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
	if not active:
		return
	if not is_instance_valid(rig) or not rig.is_ability() \
			or (is_instance_valid(combat) and combat.stagger_time > 0.0) \
			or actor.get("alive") == false:
		_finish()
		return
	elapsed += delta
	if elapsed >= duration:
		if rig.is_ability():
			rig.cancel_ability()
		_finish()


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
	elapsed = 0.0
	duration = 0.0
	speed = 0.0
	cooldowns.fill(0.0)
	if is_instance_valid(rig) and rig.is_ability():
		rig.cancel_ability()


func velocity() -> Vector3:
	return direction * speed if active else Vector3.ZERO


func hud_state(slot: int = 0) -> Dictionary:
	var definition := AbilityRules.by_slot(slot)
	if definition.is_empty():
		return {}
	var cost := float(definition.stamina_cost)
	return {
		"slot": slot,
		"id": str(definition.id),
		"name": str(definition.name),
		"key": str(definition.key),
		"active": active and active_slot == slot,
		"elapsed": elapsed if active_slot == slot else 0.0,
		"duration": duration if active_slot == slot else float(definition.duration),
		"cooldown": cooldowns[slot] if slot < cooldowns.size() else 0.0,
		"stamina_cost": cost,
		"affordable": float(actor.stamina) >= cost if is_instance_valid(actor) else true,
	}


func snapshot() -> Dictionary:
	return {
		"active": active,
		"slot": active_slot,
		"time": elapsed,
		"duration": duration,
		"cooldowns": Array(cooldowns),
	}


func apply_snapshot(state: Dictionary) -> void:
	active = bool(state.get("active", false))
	active_slot = int(state.get("slot", -1))
	active_id = str(AbilityRules.by_slot(active_slot).get("id", "")) if active else ""
	elapsed = float(state.get("time", 0.0))
	duration = float(state.get("duration", 0.0))
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
	elapsed = 0.0
	duration = 0.0
	speed = 0.0
	finished.emit(ended)
