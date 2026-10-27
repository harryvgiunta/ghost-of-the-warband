extends SceneTree
## Presence bubbles and the passive duel choreography.
##
## Owns the contract the feature was asked for: a body further than thirty
## metres from every human-possessed body is simulated at 10% damage and a body
## inside one fights for real, coverage grows with the number of humans rather
## than with any per-group configuration, a body pacing the edge cannot chatter
## between the two ("hysteresis"), the manager hands bodies back untouched when
## it is done with them, and a body under `PassiveDuelBrain` visibly gives up
## most of its attack windows while still taking the occasional swing.
##
## The drama is proven with real `_physics_process` ticks on real devil-family
## bodies, not by calling the internals: the brain's rhythm has to survive the
## mob's own state machine and cooldowns to be worth anything.

const Manager = preload("res://scripts/warband/combat_bubble.gd")
const Brain = preload("res://scripts/warband/passive_duel_brain.gd")
const Damage = preload("res://scripts/warband/damage_scaler.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const DevilMob = preload("res://scripts/devil_mob.gd")
const ForestMob = preload("res://scripts/forest_mob.gd")
const Actor = preload("res://scripts/arena_actor.gd")
const Combat = preload("res://scripts/combat.gd")

## Far outside the town's safe ring, so a body in the test world is free to hunt.
const SAFE_OFFSET := Vector3(1000.0, 0.0, 1000.0)
## Simulated duel length. The passive brain commits to one swing every five
## 1.1 s exchanges, so this window holds two of them and six active ones.
const DUEL_SECONDS := 16.0
## An identical blow used to compare a guarded fighter against an unguarded one.
const PROBE_DAMAGE := 16.0

var checks := 0
var failures := 0
var world_root: Node3D
## Every `sim_changed` the manager emitted, in order.
var sim_events: Array[int] = []
## Set when a driven archer actually releases an arrow.
var arrow_released := false


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("BUBBLE_FAIL  ", message)


func run() -> void:
	world_root = Node3D.new()
	world_root.name = "BubbleTestWorld"
	root.add_child(world_root)
	_build_floor()
	Damage.reset()
	await _check_far_pair()
	await _check_hysteresis()
	await _check_handoff()
	await _check_freed_body()
	await _check_duel_choreography()
	await _check_arena_pair()
	await _check_bow_window()
	Damage.reset()
	print("COMBAT_BUBBLE_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


# --- the requested behaviours ----------------------------------------------

## Two bodies of one far pair, two metres apart and forty from the only human:
## both simulated at 10%. A second human standing with them makes them fight for
## real - the same pair, no reconfiguration, just more coverage.
func _check_far_pair() -> void:
	var human := _human(Vector3(0.0, 0.0, 0.0))
	var far = _mob("hell_goat", Vector3(40.0, 0.05, 0.0))
	var mate = _mob("ossuary_stalker", Vector3(40.0, 0.05, 2.0))
	far.set_physics_process(false)
	mate.set_physics_process(false)
	check(_flat(far, mate) < 2.5, "the far pair stands about two metres apart (%.2f)"
		% _flat(far, mate))
	check(_flat(far, human) > Contracts.BUBBLE_EXIT_RADIUS,
		"the far pair is outside every bubble to start with")

	var manager = Manager.new()
	world_root.add_child(manager)
	sim_events.clear()
	manager.sim_changed.connect(_record_sim)
	manager.set_humans([human])
	manager.track(far)
	manager.track(mate)
	await _sweeps(2)

	check(manager.sim_state_of(far) == Contracts.CombatSimState.PASSIVE_SIM,
		"a body forty metres from the only human is simulated")
	check(manager.sim_state_of(mate) == Contracts.CombatSimState.PASSIVE_SIM,
		"its pair two metres away is simulated by the same bubble")
	check(is_equal_approx(Damage.scale(100.0, far), 10.0),
		"the far body takes 10%% of a hit (%.2f)" % Damage.scale(100.0, far))
	check(manager.active_count() == 0 and manager.passive_count() == 2,
		"the manager counts both bodies as simulated")

	# A second human walks up to the pair: their bubble makes it a real fight.
	var ally := _human(Vector3(40.0, 0.0, 4.0))
	manager.set_humans([human, ally])
	await _sweeps(2)
	check(manager.sim_state_of(far) == Contracts.CombatSimState.ACTIVE,
		"a second human at the pair flips it to a real fight")
	check(is_equal_approx(Damage.scale(100.0, far), 100.0),
		"the same hit now lands for 100%% (%.2f)" % Damage.scale(100.0, far))
	check(is_equal_approx(Damage.scale(100.0, mate), 100.0),
		"the second body of the pair is live too")
	check(manager.active_count() == 2 and manager.passive_count() == 0,
		"coverage follows the humans, not a group")
	check(sim_events.size() >= 2
		and sim_events.back() == Contracts.CombatSimState.ACTIVE,
		"`sim_changed` reported the flip (%d events)" % sim_events.size())

	# The ally leaves: only the distant human remains, so the fight simulates.
	ally.global_position = Vector3(200.0, 0.0, 200.0)
	manager.set_humans([human, ally])
	await _sweeps(2)
	check(manager.sim_state_of(far) == Contracts.CombatSimState.PASSIVE_SIM,
		"walking the second human away returns the pair to simulation")
	manager.clear()
	check(Damage.registered_count() == 0, "clear leaves no body in the registry")
	check(Damage.sim_state_of(far) == Contracts.CombatSimState.ACTIVE,
		"clear gives every tracked body its real damage back")
	_clear(manager)
	_clear(far)
	_clear(mate)
	_clear(ally)


## A body already in a bubble keeps fighting at 31 m because it has not reached
## the 34 m exit; a body that only just arrived at 31 m from far away is still
## simulated, because 31 m is outside the 30 m entry radius.
func _check_hysteresis() -> void:
	Damage.reset()
	var human := _human(Vector3(0.0, 0.0, 0.0))
	var live = _mob("hell_goat", Vector3(29.0, 0.05, 0.0))
	var simulated = _mob("ossuary_stalker", Vector3(40.0, 0.05, 0.0))
	live.set_physics_process(false)
	simulated.set_physics_process(false)
	var manager = Manager.new()
	world_root.add_child(manager)
	manager.set_humans([human])
	manager.track(live)
	manager.track(simulated)
	await _sweeps(2)
	check(manager.sim_state_of(live) == Contracts.CombatSimState.ACTIVE,
		"a body inside the entry radius fights for real")
	check(manager.sim_state_of(simulated) == Contracts.CombatSimState.PASSIVE_SIM,
		"a body outside every bubble is simulated")

	# 31 m: past the entry radius, still inside the exit radius.
	live.global_position = Vector3(31.0, 0.05, 0.0)
	simulated.global_position = Vector3(31.0, 0.05, 0.0)
	await _sweeps(2)
	check(manager.sim_state_of(live) == Contracts.CombatSimState.ACTIVE,
		"an already-active body stays active at 31 m")
	check(manager.sim_state_of(simulated) == Contracts.CombatSimState.PASSIVE_SIM,
		"a body that starts passive at 31 m stays passive")

	# Past the exit radius the bubble finally lets go, and only the entry radius
	# can bring the fight back.
	live.global_position = Vector3(Contracts.BUBBLE_EXIT_RADIUS + 0.5, 0.05, 0.0)
	await _sweeps(2)
	check(manager.sim_state_of(live) == Contracts.CombatSimState.PASSIVE_SIM,
		"the fight falls back to simulation past the exit radius")
	live.global_position = Vector3(Contracts.DEFAULT_BUBBLE_RADIUS - 0.5, 0.05, 0.0)
	await _sweeps(2)
	check(manager.sim_state_of(live) == Contracts.CombatSimState.ACTIVE,
		"re-entering the entry radius wakes the fight again")
	manager.clear()
	_clear(manager)
	_clear(live)
	_clear(simulated)


## `untrack` and `clear` hand a body back at full damage with no registry entry
## left behind, and leaving the scene tree does the same.
func _check_handoff() -> void:
	Damage.reset()
	var human := _human(Vector3(0.0, 0.0, 0.0))
	var tracked = _mob("hell_goat", Vector3(40.0, 0.05, 0.0))
	var other = _mob("hell_goat", Vector3(42.0, 0.05, 0.0))
	tracked.set_physics_process(false)
	other.set_physics_process(false)
	var manager = Manager.new()
	world_root.add_child(manager)
	manager.set_humans([human])
	manager.track(tracked)
	manager.track(other)
	await _sweeps(2)
	check(Damage.registered_count() == 2, "both simulated bodies hold a registry slot")
	check(manager.passive_count() == 2, "both bodies are counted as simulated")

	manager.untrack(tracked)
	check(Damage.sim_state_of(tracked) == Contracts.CombatSimState.ACTIVE,
		"untrack restores full damage at once, not on the next sweep")
	check(Damage.registered_count() == 1, "untrack leaves no registry entry")
	check(manager.passive_count() == 1 and manager.active_count() == 0,
		"the manager stopped counting the untracked body")
	await _sweeps(2)
	check(Damage.sim_state_of(tracked) == Contracts.CombatSimState.ACTIVE,
		"the sweep does not nerf a body it no longer decides")

	manager.clear()
	check(Damage.registered_count() == 0, "clear empties this manager's registry")
	check(manager.active_count() == 0 and manager.passive_count() == 0,
		"clear empties the tracked list")
	check(Damage.sim_state_of(other) == Contracts.CombatSimState.ACTIVE,
		"clear restores the body it was still deciding")

	# Leaving the scene tree is a hand-off too: nothing may stay at 10%.
	manager.set_humans([human])
	manager.track(other)
	await _sweeps(2)
	check(Damage.registered_count() == 1, "the second body is simulated again")
	world_root.remove_child(manager)
	check(Damage.registered_count() == 0,
		"leaving the tree releases every body from the registry")
	check(Damage.sim_state_of(other) == Contracts.CombatSimState.ACTIVE,
		"leaving the tree restores full damage")
	manager.free()
	_clear(tracked)
	_clear(other)


## A body that dies mid-sweep is pruned instead of being dereferenced.
func _check_freed_body() -> void:
	Damage.reset()
	var human := _human(Vector3(0.0, 0.0, 0.0))
	var doomed = _mob("hell_goat", Vector3(45.0, 0.05, 0.0))
	doomed.set_physics_process(false)
	var manager = Manager.new()
	world_root.add_child(manager)
	manager.set_humans([human])
	manager.track(doomed)
	await _sweeps(2)
	check(manager.passive_count() == 1, "the body is simulated before it is freed")
	check(Damage.registered_count() == 1, "and it holds a registry slot")

	doomed.queue_free()
	await _frames(2)
	check(not is_instance_valid(doomed), "the tracked body is really gone")
	# Sweeping a freed body must neither throw nor keep its stale instance id.
	await _sweeps(2)
	check(manager.passive_count() == 0 and manager.active_count() == 0,
		"a freed body is pruned from the bubble")
	check(Damage.registered_count() == 0,
		"its instance id leaves the damage registry as well")
	manager.clear()
	_clear(manager)


## The choreography: one live pair and one simulated pair, driven by the real
## state machines for the same sixteen seconds. The passive body must give up
## most of its attack windows, keep its distance, and still swing.
func _check_duel_choreography() -> void:
	Damage.reset()
	var manager = Manager.new()
	world_root.add_child(manager)
	# The live pair sits inside this human's bubble; the far pair does not.
	var human := _human(Vector3(0.0, 0.0, -1.2))
	var active_target := _human(Vector3(0.0, 0.0, 3.0))
	var passive_target := _human(Vector3(40.0, 0.0, 3.0))
	var active_mob = _mob("hell_goat", Vector3(0.0, 0.05, 0.0), active_target)
	var passive_mob = _mob("hell_goat", Vector3(40.0, 0.05, 0.0), passive_target)
	manager.set_humans([human])
	manager.track(active_mob)
	manager.track(passive_mob)
	var brain = Brain.new()
	brain.attach(passive_mob, passive_target)
	check(brain.get_parent() == passive_mob,
		"the brain ticks with the body it was attached to")

	# Warm-up: one sweep to settle both bodies into their bubble state, and the
	# brain's first parry, so the measured window is pure behaviour.
	await _sweeps(1)
	check(not Damage.is_passive(active_mob), "the near body fights for real")
	check(Damage.is_passive(passive_mob), "the far body is simulated")
	check(passive_mob.warband_passive, "the brain put the far body in its guard stance")
	check(not active_mob.warband_passive, "the live body keeps its own stance")

	var duel := await _measure_duel(active_mob, passive_mob, active_target,
		passive_target, DUEL_SECONDS)
	var active_windups: int = duel.active_windups
	var passive_windups: int = duel.passive_windups
	var active_strikes: int = duel.active_strikes
	var passive_strikes: int = duel.passive_strikes
	print("BUBBLE_DUEL active=%d/%d passive=%d/%d distance %.2f vs %.2f"
		% [active_windups, active_strikes, passive_windups, passive_strikes,
			duel.active_min, duel.passive_min])

	check(active_windups >= 3, "the live body keeps attacking (windups=%d)"
		% active_windups)
	check(passive_windups >= 1,
		"the simulated body still takes the occasional swing (windups=%d)"
		% passive_windups)
	check(passive_windups * 2 < active_windups,
		"the simulated body gives up most attack windows (%d vs %d)"
		% [passive_windups, active_windups])
	check(passive_strikes * 2 < active_strikes,
		"and most of the blows that actually land (%d vs %d)"
		% [passive_strikes, active_strikes])
	check(float(duel.passive_min) > float(duel.active_min),
		"the simulated body holds its spacing (%.2f vs %.2f m)"
		% [duel.passive_min, duel.active_min])

	# The scene's own override: a fight forced live drops the guard on the spot.
	brain.set_active(true)
	check(not passive_mob.warband_passive,
		"set_active(true) hands the body back its own behaviour")
	brain.set_active(false)
	await _frames(4)
	check(passive_mob.warband_passive,
		"set_active(false) returns the body to the bubble's choreography")
	brain.detach()
	check(brain.get_parent() == null, "detach takes the brain out of the body")
	check(not passive_mob.warband_passive,
		"detach leaves the body with no stance")
	_clear(active_mob)
	_clear(passive_mob)
	_clear(brain)
	manager.clear()
	_clear(manager)


## The same choreography on the bodies the Admin Arena actually fields: two
## `ArenaActor` pairs, one inside a human bubble and one forty metres out. Both
## pairs live for real every frame, the far defender is driven by the brain, and
## identical blows land on both defenders. The far one must take almost nothing
## (its guard resolves the blows, the bubble pays 10%), guard at least once, and
## still take its own swing on a later window.
func _check_arena_pair() -> void:
	Damage.reset()
	var manager = Manager.new()
	world_root.add_child(manager)
	var human := _human(Vector3(0.0, 0.0, -1.0))
	var live_attacker = _fighter(0, Vector3(0.0, 0.0, 0.0), true)
	var live_defender = _fighter(1, Vector3(0.0, 0.0, 2.4), true)
	# `ArenaActor.bounds` clamps a body to +-31.5 m, so a pair outside the bubble
	# has to stand in the diagonal corner to clear the 34 m exit radius.
	var far_attacker = _fighter(2, Vector3(28.0, 0.0, 28.0), true)
	var far_defender = _fighter(3, Vector3(28.0, 0.0, 30.4), true)
	manager.set_humans([human])
	manager.track(live_defender)
	manager.track(far_defender)
	var brain = Brain.new()
	brain.attach(far_defender, far_attacker)

	var pair: Array = [live_attacker, live_defender, far_attacker, far_defender]
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	await _sweeps(1)
	check(not Damage.is_passive(live_defender),
		"the arena pair inside the bubble fights for real")
	check(Damage.is_passive(far_defender),
		"the arena pair forty metres out is simulated")
	# The first brain frame is what takes the body off the bot AI.
	for _frame in 2:
		await physics_frame
		brain.step(delta)
		for actor in pair:
			actor.step(delta, pair)
	check(not bool(far_defender.is_bot) and bool(live_defender.is_bot),
		"the brain takes the far fighter off the bot AI, the live one keeps it")

	# Damage is accumulated per probe, not read off the final health: a fighter
	# that dies on the third blow respawns on the eighth second at full health.
	var live_taken := 0.0
	var far_taken := 0.0
	var blocked := 0
	var far_swings := 0
	var far_was_swinging := false
	var damage_frames := int(round(3.0 * Engine.physics_ticks_per_second))
	var total_frames := int(round(8.0 * Engine.physics_ticks_per_second))
	for frame in total_frames:
		await physics_frame
		# The order the arena must use: the brain writes the intents and the
		# guard, then the body's own step consumes them.
		brain.step(delta)
		for actor in pair:
			actor.step(delta, pair)
		if frame < damage_frames and frame % 36 == 18:
			var live_probe_hp: float = live_defender.health
			var far_probe_hp: float = far_defender.health
			var live_outcome: int = live_defender.receive_melee(PROBE_DAMAGE,
				live_attacker.slot, live_attacker.global_position)
			var far_outcome: int = far_defender.receive_melee(PROBE_DAMAGE,
				far_attacker.slot, far_attacker.global_position)
			check(live_outcome == Combat.DEFENSE_NONE,
				"an unguarded live fighter takes the blow")
			live_taken += maxf(0.0, live_probe_hp - live_defender.health)
			far_taken += maxf(0.0, far_probe_hp - far_defender.health)
			if far_outcome in [Combat.DEFENSE_BLOCK, Combat.DEFENSE_PARRY,
					Combat.DEFENSE_WEAK_BLOCK]:
				blocked += 1
		var swinging: bool = bool(far_defender.rig.is_melee())
		if swinging and not far_was_swinging:
			far_swings += 1
		far_was_swinging = swinging

	print("BUBBLE_ARENA live_taken=%.1f far_taken=%.1f blocked=%d swings=%d"
		% [live_taken, far_taken, blocked, far_swings])
	check(blocked >= 1,
		"the far fighter's guard resolves as a real block or parry (blocked=%d)"
		% blocked)
	check(far_taken * 4.0 < live_taken,
		"the far fighter takes a fraction of the same blows (%.1f vs %.1f)"
		% [far_taken, live_taken])
	check(far_swings >= 1, "the far fighter still opens a real swing (swings=%d)"
		% far_swings)
	check(not brain.active(), "the brain reports it owns the far fighter's intents")

	# Handing the body back and taking it again, the two calls the arena makes.
	brain.set_active(true)
	check(bool(far_defender.is_bot),
		"set_active(true) hands the fighter back to the bot AI")
	check(brain.active(), "active() reports the body drives itself again")
	brain.set_active(false)
	for _frame in 4:
		await physics_frame
		brain.step(delta)
		far_defender.step(delta, pair)
	check(not bool(far_defender.is_bot),
		"set_active(false) returns the fighter to the brain")
	brain.detach()
	check(bool(far_defender.is_bot), "detach leaves the fighter on its own AI")
	check(not far_defender.combat.blocking, "detach drops the fighter's guard")
	for actor in pair:
		_clear(actor)
	_clear(brain)
	manager.clear()
	_clear(manager)


## A bow body past blade reach has no guard to set: the brain keeps the bow, does
## not sprint into a fist fight, and spends its window on an arrow.
func _check_bow_window() -> void:
	Damage.reset()
	var manager = Manager.new()
	world_root.add_child(manager)
	# The bubble stands in the opposite corner: the archer circles its mark at a
	# twelve metre radius, and the whole circle has to stay outside 34 m.
	var human := _human(Vector3(-28.0, 0.0, -28.0))
	var archer = _fighter(0, Vector3(28.0, 0.0, 26.0), false)
	var mark = _fighter(1, Vector3(28.0, 0.0, 14.0), false)
	archer.rig.set_weapon("bow")
	manager.set_humans([human])
	manager.track(archer)
	var brain = Brain.new()
	brain.attach(archer, mark)
	arrow_released = false
	archer.fired.connect(_on_fired)

	var pair: Array = [archer, mark]
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	for _frame in int(round(9.0 * Engine.physics_ticks_per_second)):
		await physics_frame
		brain.step(delta)
		for actor in pair:
			actor.step(delta, pair)
	check(Damage.is_passive(archer), "the far archer is simulated")
	check(not bool(archer.is_bot), "the brain drives the far archer")
	check(str(archer.rig.weapon) == "bow",
		"the brain keeps a bow past blade reach (weapon=%s)" % archer.rig.weapon)
	check(not archer.combat.blocking, "a bow never sets a guard")
	check(arrow_released,
		"the far archer's window becomes a released arrow, not a frozen draw")
	_clear(archer)
	_clear(mark)
	brain.detach()
	_clear(brain)
	manager.clear()
	_clear(manager)


# --- helpers ---------------------------------------------------------------

## One 16 s duel, polled every physics frame: a state is counted when it is
## entered, which is exactly what the animator and the damage event see.
func _measure_duel(active_mob, passive_mob, active_target, passive_target,
		seconds: float) -> Dictionary:
	var duel := {
		"active_windups": 0, "passive_windups": 0,
		"active_strikes": 0, "passive_strikes": 0,
		"active_min": INF, "passive_min": INF,
	}
	var active_state := str(active_mob.state)
	var passive_state := str(passive_mob.state)
	var frames := int(round(seconds * Engine.physics_ticks_per_second))
	for _frame in frames:
		await physics_frame
		var now_active := str(active_mob.state)
		if now_active != active_state:
			if now_active == "WINDUP":
				duel["active_windups"] += 1
			elif now_active == "STRIKE":
				duel["active_strikes"] += 1
			active_state = now_active
		var now_passive := str(passive_mob.state)
		if now_passive != passive_state:
			if now_passive == "WINDUP":
				duel["passive_windups"] += 1
			elif now_passive == "STRIKE":
				duel["passive_strikes"] += 1
			passive_state = now_passive
		duel["active_min"] = minf(duel.active_min, _flat(active_mob, active_target))
		duel["passive_min"] = minf(duel.passive_min, _flat(passive_mob, passive_target))
	return duel


func _record_sim(_node: Node3D, state: int) -> void:
	sim_events.append(state)


func _on_fired(_slot: int, _origin: Vector3, _direction: Vector3, _speed: float,
		_charge: float) -> void:
	arrow_released = true


func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = Vector3(600.0, 1.0, 600.0)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(shape)
	world_root.add_child(body)


## A human-possessed body as the manager sees it: a body peers are inside. No
## collision shape, so the fighters cannot lean on it and the distances stay
## honest.
func _human(at: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	body.position = at
	world_root.add_child(body)
	return body


## A real arena fighter: authoritative, bladed, and either a bot or a body the
## brain drives. A blade because `start_block()` refuses to guard with a bow.
func _fighter(index: int, at: Vector3, bot: bool):
	var actor = Actor.new()
	actor.slot = index
	actor.authoritative = true
	world_root.add_child(actor)
	actor.configure(index + 1, bot, "Probe%d" % index, at)
	actor.rig.set_weapon("sword")
	return actor


## A real wilderness body: a devil or the forest family that inherits its state
## machine. `hunter` is the ranger it fights, when the test needs a duel.
func _mob(mob_id: String, at: Vector3, hunter: Node3D = null):
	var mob
	if ForestMob.FOREST_PROFILES.has(mob_id):
		mob = ForestMob.new()
	else:
		mob = DevilMob.new()
	mob.mob_id = mob_id
	if is_instance_valid(hunter):
		mob.player = hunter
	# Town peace is anchored far away: a body in this test world may hunt.
	mob.safe_center = SAFE_OFFSET
	mob.position = at
	world_root.add_child(mob)
	return mob


func _flat(a: Node3D, b: Node3D) -> float:
	var offset: Vector3 = a.global_position - b.global_position
	offset.y = 0.0
	return offset.length()


## Physics frames for `count` manager sweeps (0.2 s each), plus the frame the
## sweep lands on.
func _sweeps(count: int) -> void:
	await _frames(int(ceil(count * Manager.SWEEP_SECONDS
		* Engine.physics_ticks_per_second)) + 2)


func _frames(count: int) -> void:
	for _frame in count:
		await physics_frame


func _clear(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()
