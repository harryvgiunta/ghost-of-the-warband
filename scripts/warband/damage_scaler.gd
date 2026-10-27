class_name WarbandDamage
extends RefCounted
## The one place a damage number is scaled by the proximity bubble.
##
## Phase 0 contract: every damage funnel (`main.gd::take_damage`,
## `arena_actor.gd::take_damage`, `devil_mob.gd::take_damage`,
## `enemy.gd::take_damage`) calls `WarbandDamage.scale(amount, self)` as its first
## statement, so no worktree has to edit a shared combat file. A victim inside a
## human presence bubble returns `ACTIVE` (x1.0); a victim beyond every bubble
## returns `PASSIVE_SIM` (x0.10). Ownership of the state itself (the distance
## tracker that decides it) lives in `scripts/warband/combat_bubble.gd`.
##
## The registry is keyed by `instance_id` so a freed body leaves no reference
## behind; `prune()` runs on every write.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")

## instance_id -> CombatSimState. Absent means ACTIVE: an unregistered body is
## never silently nerfed.
static var _states: Dictionary = {}

static func set_sim_state(node: Object, state: int) -> void:
	if node == null or not is_instance_valid(node):
		return
	var key := node.get_instance_id()
	if state == Contracts.CombatSimState.ACTIVE:
		_states.erase(key)
	else:
		_states[key] = state

static func sim_state_of(node: Object) -> int:
	if node == null or not is_instance_valid(node):
		return Contracts.CombatSimState.ACTIVE
	return int(_states.get(node.get_instance_id(), Contracts.CombatSimState.ACTIVE))

static func is_passive(node: Object) -> bool:
	return sim_state_of(node) == Contracts.CombatSimState.PASSIVE_SIM

## Scale one incoming hit for a victim. Multiplies once; callers must not scale
## twice, which is why this is the only public damage hook in the subsystem.
static func scale(amount: float, victim: Object) -> float:
	var multiplier := Contracts.damage_multiplier(sim_state_of(victim))
	return amount * multiplier

## Drop dead instance ids so the registry cannot grow across a long session.
static func prune() -> void:
	if _states.is_empty():
		return
	for key in _states.keys():
		if not is_instance_id_valid(int(key)):
			_states.erase(key)

static func registered_count() -> int:
	return _states.size()

## Called by tests and by every scene hand-off: state never leaks between runs.
static func reset() -> void:
	_states.clear()
