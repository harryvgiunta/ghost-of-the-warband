class_name EnemyWaves
extends Node
## Expedition waves of cultist guards, and the field step that makes them fight.
##
## A wave is a count and a kit tier, both derived from the wave index alone, so
## the same expedition always fields the same cultists: wave 0 is three guards
## with shivs, wave 1 is four with steel, wave 2 is five mixing bows and shields,
## and the count caps at six. Nothing here rolls a global RNG.
##
## ## The call order a scene needs
##
## Guards are their own `ArenaActor` bodies, so they integrate themselves:
##   1. `waves.step(delta, bodies, tick)` - every guard picks its target, swings
##      or shoots, and moves. Call it BEFORE the warband's own step so a guard
##      swing lands in the tick the warband is about to resolve;
##   2. `controller.physics_step(delta)` - the warband bodies integrate.
## Every guard is handed `field(bodies)`, which is `bodies + guards`. The cultist
## class filters its own faction out of that list, so a guard never turns on a
## fellow while the shared separation still keeps the pack from stacking in one
## spot. A scene that steps bodies itself should hand them the same
## `field(bodies)` array, for the same reason.

signal wave_started(index: int, count: int)
signal wave_cleared(index: int)

const GuardScript = preload("res://scripts/warband/cultist_guard.gd")
const ArrowScript = preload("res://scripts/arrow.gd")
const CombatRules = preload("res://scripts/combat.gd")
const State = preload("res://scripts/player_state.gd")

const BASE_GUARDS := 3
const MAX_GUARDS := 6
## Guard slots start above the warband's own body slots (the controller numbers
## bodies from 0) so `take_damage` never reads a cultist as the body that hit it.
const FIRST_GUARD_SLOT := 100
## Fixed per-wave seed: same index, same kits, on every machine and every run.
const WAVE_SEED := 70510
## Kit escalation, one tier per wave until the last one holds. Wave 0 is knives
## and salvage, wave 1 draws forged steel behind a buckler, wave 2 adds archers
## behind kite shields.
const KITS := [
	{"mains": ["dagger_makeshift", "dagger_iron"], "offs": ["", ""], "armor": "makeshift"},
	{"mains": ["sword_short", "sword_arming"], "offs": ["", "shield_buckler"], "armor": "leather"},
	{"mains": ["bow_short", "sword_short", "sword_arming"],
		"offs": ["", "shield_buckler", "shield_kite"], "armor": "mail"},
]

var _controller = null
var _parent: Node3D = null
var _spawn_points: Array[Vector3] = []
var _player_provider := Callable()
var _guards: Array[CultistGuard] = []
## Guards already counted as cleared, by instance id, so a kill is tallied once.
var _counted: Dictionary = {}
var _wave := -1
var _wave_size := 0
var _cleared := false
var _total_cleared := 0
var _tick := 0

## Point the waves at a scene: the soul controller that owns the warband bodies,
## the node guards are parented to, the ring of spawn points, and a callable that
## answers with the warband bodies when a step is called with an empty list.
func setup(controller, parent_node: Node3D, spawn_points: Array[Vector3],
		player_provider: Callable) -> void:
	_controller = controller
	_parent = parent_node
	_spawn_points = spawn_points.duplicate()
	_player_provider = player_provider

## Field a wave. Whatever is left of the previous wave is retired first, so a
## scene can restart or skip ahead without stacking two waves in one yard.
func start_wave(index: int = 0) -> Array[CultistGuard]:
	if _parent == null:
		push_error("EnemyWaves: setup() before start_wave()")
		var empty: Array[CultistGuard] = []
		return empty
	_retire()
	_wave = maxi(index, 0)
	_cleared = false
	var rng := RandomNumberGenerator.new()
	rng.seed = WAVE_SEED + _wave * 7919
	var count := mini(BASE_GUARDS + _wave, MAX_GUARDS)
	var tier: Dictionary = KITS[mini(_wave, KITS.size() - 1)]
	var spawned: Array[CultistGuard] = []
	for index_in_wave in count:
		var guard := _spawn_guard(index_in_wave, tier, rng)
		_guards.append(guard)
		spawned.append(guard)
	_wave_size = spawned.size()
	wave_started.emit(_wave, _wave_size)
	return spawned

## Advance the cult half of the field. `bodies` is the warband the guards hate;
## an empty list falls back to the provider the scene was set up with.
func step(delta: float, bodies: Array = [], tick: int = 0) -> void:
	_tick += 1
	var simulation_tick := tick if tick > 0 else _tick
	var field := field(bodies)
	for guard in _live_guards():
		guard.step(delta, field, simulation_tick)
	_reap()
	_refresh_cleared()

## The living cultists, in spawn order, so a scene can act on them (loot, waves,
## an admin kill switch) without reaching into the spawner.
func guards() -> Array[CultistGuard]:
	return _live_guards()

## The array a body should be stepped with while guards are on the field:
## the opponents first, then the cultists, so both factions separate properly.
func field(bodies: Array = []) -> Array:
	var out := _opponents(bodies)
	out.append_array(_live_guards())
	return out

## Guards still on their feet.
func living() -> int:
	return _standing_count()

## The wave on the field, or -1 before the first one.
func wave() -> int:
	return _wave

## Cultists put down across every wave this node has fielded.
func total_cleared() -> int:
	return _total_cleared

## Empty the yard. The tally survives, because it is the expedition's record.
func clear() -> void:
	_retire()
	_wave = -1
	_wave_size = 0
	_cleared = false

# --- internals -------------------------------------------------------------

func _spawn_guard(index_in_wave: int, tier: Dictionary, rng: RandomNumberGenerator) -> CultistGuard:
	var guard := GuardScript.new()
	guard.name = "CultistGuard%02d" % (index_in_wave + 1)
	# The slot is assigned before the tree sees it: `_ready` reads it for the
	# label colour and `combat.source_id`, and the waves own a slot block of
	# their own so no body refuses a cultist's blow as its own.
	guard.slot = FIRST_GUARD_SLOT + _wave * MAX_GUARDS + index_in_wave
	_parent.add_child(guard)
	guard.authoritative = true
	guard.combat.damage_enabled = true
	var name_index := rng.randi_range(0, GuardScript.NAMES.size() - 1)
	guard.configure(0, true, str(GuardScript.NAMES[name_index]), _spawn_point(index_in_wave))
	var kit := _roll_kit(index_in_wave, tier, rng)
	guard.apply_kit(str(kit["main"]), str(kit["off"]), str(kit["armor"]))
	guard.killed.connect(_on_guard_killed.bind(guard))
	guard.downed_started.connect(_on_guard_state_changed)
	guard.downed_ended.connect(_on_guard_state_changed)
	guard.fired.connect(_on_guard_fired.bind(guard))
	return guard

## One guard's kit from a tier. The main hands rotate through the tier's pool
## with the roll as the offset, so a tier that offers bows behind a shield wall
## really fields both: with five guards and three mains every main appears. The
## off hand is rolled separately, and `apply_kit` drops one the main cannot
## legally hold.
func _roll_kit(index_in_wave: int, tier: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var mains: Array = tier.get("mains", ["dagger_makeshift"])
	var offset := rng.randi_range(0, mains.size() - 1)
	var main_id := str(mains[(offset + index_in_wave) % mains.size()])
	var offs: Array = tier.get("offs", [])
	var off_id := "" if offs.is_empty() else str(offs[rng.randi_range(0, offs.size() - 1)])
	if str(State.ITEMS.get(main_id, {}).get("category", "")) == "bow":
		off_id = ""
	return {"main": main_id, "off": off_id, "armor": str(tier.get("armor", "makeshift"))}

## Spawn points are handed out in order; a wave wider than the ring wraps around
## it on a widening circle so two guards never share a point.
func _spawn_point(index: int) -> Vector3:
	if _spawn_points.is_empty():
		return Vector3(2.0 * float(index), 0.0, 0.0)
	if index < _spawn_points.size():
		return _spawn_points[index]
	var slot := index % _spawn_points.size()
	var lap := float(index / _spawn_points.size())
	var angle := TAU * float(slot) / float(_spawn_points.size())
	return _spawn_points[slot] + Vector3(cos(angle), 0.0, sin(angle)) * 1.8 * lap

## The warband bodies a guard is allowed to see: whatever the caller passed, else
## the scene's provider, else the bodies the soul controller owns.
func _opponents(bodies: Array) -> Array:
	var source: Array = bodies
	if source.is_empty() and _player_provider.is_valid():
		var provided: Variant = _player_provider.call()
		if provided is Array:
			source = provided
	if source.is_empty() and _controller != null and is_instance_valid(_controller):
		source = _controller.bodies()
	var foes: Array = []
	for other in source:
		if other is Node3D and other.has_method("take_damage"):
			foes.append(other)
	return foes

func _live_guards() -> Array[CultistGuard]:
	var out: Array[CultistGuard] = []
	for guard in _guards:
		if is_instance_valid(guard):
			out.append(guard)
	return out

func _standing_count() -> int:
	var count := 0
	for guard in _live_guards():
		if guard.standing():
			count += 1
	return count

## Drop freed guards from the roster so a scene that clears the yard itself does
## not leave the wave counting phantoms.
func _reap() -> void:
	var live: Array[CultistGuard] = []
	for guard in _guards:
		if is_instance_valid(guard):
			live.append(guard)
	_guards = live

func _retire() -> void:
	for guard in _guards:
		if is_instance_valid(guard):
			guard.queue_free()
	_guards.clear()
	_counted.clear()

func _on_guard_killed(_slot: int, _source: int, guard: CultistGuard) -> void:
	if is_instance_valid(guard):
		var id := guard.get_instance_id()
		if not _counted.has(id):
			_counted[id] = true
			_total_cleared += 1
	_refresh_cleared()

func _on_guard_state_changed(_slot: int) -> void:
	_refresh_cleared()

## A wave is cleared the moment nothing is left standing in it. Downed cultists
## do not hold a wave open; they bleed out where they crawled.
func _refresh_cleared() -> void:
	if _wave < 0 or _cleared or _wave_size == 0:
		return
	if _standing_count() > 0:
		return
	_cleared = true
	wave_cleared.emit(_wave)

## A cult archer's release becomes a real shaft. The waves own the projectiles
## because they own the guard bodies, and the arena's arrow already resolves
## terrain, armor and the victim's own damage funnel.
func _on_guard_fired(_slot: int, origin: Vector3, direction: Vector3, speed: float,
		charge: float, guard: CultistGuard) -> void:
	if _parent == null or not is_instance_valid(guard) or not guard.alive:
		return
	var arrow := ArrowScript.new()
	arrow.source_id = guard.slot
	arrow.hit_mask = 1 | 4 | 8
	arrow.authoritative_damage = true
	_parent.add_child(arrow)
	var excluded: Array[RID] = [guard.get_rid()]
	if is_instance_valid(guard.rig.active_shield):
		excluded.append(guard.rig.active_shield.get_rid())
	arrow.launch(origin, direction, speed,
		CombatRules.damage_for(guard.rig.bow_index, charge), excluded)
