class_name WarbandBubbleManager
extends Node
## Server-side presence bubbles: the authority for who fights for real.
##
## One manager serves every human in the session. A body's state is decided by
## the distance to the *nearest* human-possessed body, so two players standing
## forty metres apart each hold their own live zone for free - there is no
## per-group configuration to keep in sync, coverage simply grows with the
## number of humans.
##
## The decision is written through `WarbandDamage.set_sim_state()`, the single
## registry every `take_damage` funnel already reads. Nothing here touches a
## damage number: the funnels scale once, this node only says which way.
##
## The manager knows no scene. A session adds it, `track()`s the bodies that
## fight and `set_humans()`s the bodies a peer is currently inside.
##
## Hysteresis: `bubble_radius` (30 m) makes a fight real, `bubble_exit_radius`
## (34 m) lets it fall back to simulation. A body pacing the edge therefore
## cannot chatter between full and 10% damage on every sweep.

## Emitted when a tracked body crosses into or out of a bubble, so the scene can
## flip its duel brain in the same frame the damage changes.
signal sim_changed(node: Node3D, state: int)

## A body crossing a thirty-metre line is a design decision, not an input: five
## sweeps a second is enough, and it keeps the cost independent of body count.
const SWEEP_SECONDS := 0.2

## Radius a body must come inside to fight for real, and the radius it must
## leave before it falls back to simulation.
var bubble_radius := WarbandContracts.DEFAULT_BUBBLE_RADIUS
var bubble_exit_radius := WarbandContracts.BUBBLE_EXIT_RADIUS

var _humans: Array[Node3D] = []
var _bodies: Array[Node3D] = []
## Instance ids parallel to `_bodies`: a freed body can no longer be asked for
## its id, so the id is captured once at `track()` time instead.
var _body_ids: Array[int] = []
## instance_id -> CombatSimState: the last decision *this* manager made. Kept
## beside the global registry so the hysteresis reads its own history and an
## untracked body can never inherit a stale verdict.
var _states: Dictionary = {}
var _elapsed := 0.0


func _exit_tree() -> void:
	clear()


## Override the radii; the exit radius can never end up smaller than the entry
## radius or hysteresis would invert.
func setup(radius: float = WarbandContracts.DEFAULT_BUBBLE_RADIUS,
		exit_radius: float = WarbandContracts.BUBBLE_EXIT_RADIUS) -> void:
	bubble_radius = maxf(0.0, radius)
	bubble_exit_radius = maxf(bubble_radius, exit_radius)


## The bodies peers are inside right now - the whole configuration there is.
## Freed entries are ignored here and dropped on the next sweep.
func set_humans(humans: Array) -> void:
	_humans.clear()
	for human in humans:
		if human is Node3D and is_instance_valid(human):
			_humans.append(human)


## A body that fights: a patrol, a mercenary, a mob. Tracking twice is a no-op.
func track(node) -> void:
	if not (node is Node3D) or not is_instance_valid(node):
		return
	var id: int = node.get_instance_id()
	if _body_ids.has(id):
		return
	_bodies.append(node)
	_body_ids.append(id)
	# Start from whatever the scaler holds, so handing a body between managers
	# cannot resurrect a stale PASSIVE from the previous session.
	_states[id] = WarbandDamage.sim_state_of(node)


## Stop deciding this body, and give it back its real damage. A node that was
## freed on the way here needs nothing: the prune already dropped it.
func untrack(node) -> void:
	_prune()
	if not (node is Node3D) or not is_instance_valid(node):
		return
	var id: int = node.get_instance_id()
	var index := _body_ids.find(id)
	if index < 0:
		return
	_bodies.remove_at(index)
	_body_ids.remove_at(index)
	_states.erase(id)
	WarbandDamage.set_sim_state(node, WarbandContracts.CombatSimState.ACTIVE)


## Forget every body and every human, leaving the scaler clean: called on scene
## hand-off and on exit so no body inherits a 10% nerf from the last fight.
func clear() -> void:
	for body in _bodies:
		if is_instance_valid(body):
			WarbandDamage.set_sim_state(body, WarbandContracts.CombatSimState.ACTIVE)
	_bodies.clear()
	_body_ids.clear()
	_states.clear()
	_humans.clear()
	_elapsed = 0.0
	WarbandDamage.prune()


## The state the damage funnel will use for this body right now.
func sim_state_of(node) -> int:
	return WarbandDamage.sim_state_of(node)


func active_count() -> int:
	var total := 0
	for body in _bodies:
		if is_instance_valid(body) and not WarbandDamage.is_passive(body):
			total += 1
	return total


func passive_count() -> int:
	var total := 0
	for body in _bodies:
		if is_instance_valid(body) and WarbandDamage.is_passive(body):
			total += 1
	return total


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < SWEEP_SECONDS:
		return
	# Keep the cadence rather than restarting it, so a slow frame cannot drift
	# the sweep off the clock.
	_elapsed = fmod(_elapsed, SWEEP_SECONDS)
	_sweep()


## One pass: drop what died, then decide every survivor against the nearest
## human. With no human in the session every body is simulated, which is the
## honest answer - nothing is being watched.
func _sweep() -> void:
	_prune()
	for index in _bodies.size():
		var body: Node3D = _bodies[index]
		var id: int = _body_ids[index]
		var previous := int(_states.get(id, WarbandContracts.CombatSimState.ACTIVE))
		var decided := previous
		var nearest := _nearest_human(body)
		if previous == WarbandContracts.CombatSimState.PASSIVE_SIM:
			if nearest <= bubble_radius:
				decided = WarbandContracts.CombatSimState.ACTIVE
		elif nearest > bubble_exit_radius:
			decided = WarbandContracts.CombatSimState.PASSIVE_SIM
		if decided == previous:
			continue
		_states[id] = decided
		WarbandDamage.set_sim_state(body, decided)
		sim_changed.emit(body, decided)


## Horizontal distance to the closest human, ignoring height: a bubble is the
## ground a human holds, and a gargoyle perched on a wall above the player is
## still in the same fight. `INF` when nobody is in the session.
func _nearest_human(body: Node3D) -> float:
	var at := body.global_position
	var best := INF
	for human in _humans:
		var offset := human.global_position - at
		offset.y = 0.0
		best = minf(best, offset.length())
	return best


func _prune() -> void:
	for index in range(_humans.size() - 1, -1, -1):
		if not is_instance_valid(_humans[index]):
			_humans.remove_at(index)
	var dropped := false
	for index in range(_bodies.size() - 1, -1, -1):
		if is_instance_valid(_bodies[index]):
			continue
		_states.erase(_body_ids[index])
		_bodies.remove_at(index)
		_body_ids.remove_at(index)
		dropped = true
	if dropped:
		# The scaler is keyed by instance id as well; a freed body must not keep
		# a slot there or `registered_count()` would count the dead forever.
		WarbandDamage.prune()
