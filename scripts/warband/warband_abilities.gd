class_name WarbandAbilities
extends Node
## The scene half of the item skills: turns one body's ability cues into
## arrows, spells, blinks and blade beats.
##
## `AbilityRunner` owns *when* a skill fires; the scene owns *what a beat does*.
## The warband therefore has exactly one of these for the whole possession
## campaign, playing the part `main.gd` plays for the frontier: `setup()` keeps
## the world it spawns into, `bind_body()` wires one spawned `ArenaActor` once,
## and every cue is resolved from that body's own active definition, so a looted
## weapon changes the effect without a second ability table.
##
## Only the authoritative, standing body acts. A replica learns its ability from
## the wire and must never spawn a second arrow for the same beat.

const AbilityRules = preload("res://scripts/ability_rules.gd")
const AbilityFx = preload("res://scripts/ability_fx.gd")
const Archer = preload("res://scripts/archer.gd")
const Arrow = preload("res://scripts/arrow.gd")
const SpellProjectile = preload("res://scripts/spell_projectile.gd")
const BackstabAbility = preload("res://scripts/backstab_ability.gd")

## World plus bodies: a shot stops on terrain and on the wood's mobs, the same
## pair the possession camera's crosshair ray aims through.
const TARGET_MASK := 1 | 2
## A backstab needs a live body under the crosshair, at the frontier's reach,
## before its blink means anything.
const BACKSTAB_RANGE := 8.0
## Missiles are real damage nodes owned by the authority. The cap is a leak
## guard, not a gameplay limit: the oldest shot goes before the tree grows.
const MAX_MISSILES := 32

var _world: Node3D
var _controller
var _bodies: Array = []
var _missiles: Array = []


## Wire the node to the world it spawns into. The controller is kept because a
## cue resolves its aim from the body the soul is actually inside.
func setup(world: Node3D, controller) -> void:
	_world = world
	_controller = controller


## The possession bridge this node was set up with. Exposed so a scene does not
## have to keep a second reference to it.
func controller():
	return _controller


## Wire one spawned body. Idempotent: the world may bind the same body again
## after a re-seat, and a second connection would fire every beat twice.
func bind_body(actor) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	_prune_bodies()
	if _bodies.has(actor):
		return
	var runner = actor.get("ability")
	if runner == null or not is_instance_valid(runner):
		return
	runner.cue.connect(_on_cue.bind(actor))
	# The backstab has to know which body it will land behind *before* its first
	# cue, exactly as the frontier preflights it: the blink and the stab must
	# agree on one body even if the crosshair has moved by the second beat.
	runner.activated.connect(_on_activated.bind(actor))
	_bodies.append(actor)


## Bodies with live cue wiring, for tests and for a scene that wants to rescan.
func bound_bodies() -> Array:
	_prune_bodies()
	return _bodies.duplicate()


## The shots and spells still flying, for tests and for a scene's cleanup.
func missiles() -> Array:
	_prune_missiles()
	return _missiles.duplicate()


# --- cues ------------------------------------------------------------------

## One performed beat. The definition is re-read from the runner every cue so a
## weapon swapped mid-skill can never leave the wrong effect behind.
func _on_cue(id: String, cue: String, index: int, actor) -> void:
	if not _can_act(actor):
		return
	var runner = actor.ability
	if runner == null or not is_instance_valid(runner) or not runner.active:
		return
	if str(runner.active_id) != id:
		return
	var definition: Dictionary = runner.active_definition
	if definition.is_empty():
		return
	var rig = actor.rig
	if rig == null or not is_instance_valid(rig):
		return
	var effect: Dictionary = definition.get("effect", {})
	var damage: float = AbilityRules.damage_for(definition, rig)
	match str(effect.get("kind", "")):
		"barrage", "volley", "piercing_shot":
			_fire_arrows(actor, runner, definition, index, damage)
		"projectile":
			_launch_spell(actor, runner, definition, damage)
		"backstab":
			_backstab(actor, cue, damage)
		"melee_arc", "melee_ring":
			_melee(actor, runner, definition, cue, index, damage)
	# A travelling skill's lane is swept by `ArenaActor._sweep_ability_path`;
	# a ward is a body state the runner has already started. Neither needs a
	# beat here, and neither may be applied twice.


## The preflight for the one skill that moves the body: resolve the body behind
## which the dagger will land and keep it on the actor. An empty crosshair drops
## any target from a previous activation instead of blinking behind a corpse.
func _on_activated(_id: String, definition: Dictionary, actor) -> void:
	if not _can_act(actor):
		return
	if actor.has_meta("backstab_target"):
		actor.remove_meta("backstab_target")
	if str(definition.get("effect", {}).get("kind", "")) != "backstab":
		return
	var target := _backstab_target(actor)
	if target != null:
		actor.set_meta("backstab_target", target)


## Only a body that owns its own simulation and is still standing may put a
## hit into the world.
func _can_act(actor) -> bool:
	return actor != null and is_instance_valid(actor) \
		and bool(actor.get("authoritative")) and bool(actor.get("alive")) \
		and not bool(actor.get("downed"))


# --- ranged ----------------------------------------------------------------

## Barrage / fan volley / piercing shot: one arrow per beat (a volley spawns its
## fan from a single cue), aimed down the live crosshair with the authored
## spread. The arrow's own `pierce` budget carries the piercing shot through
## three bodies.
func _fire_arrows(actor, runner, definition: Dictionary, index: int, damage: float) -> void:
	var effect: Dictionary = definition.get("effect", {})
	var kind := str(effect.get("kind", ""))
	var rig = actor.rig
	var aim: Vector3 = runner.combat.aim_point
	# The cue lands before this rig's own pose step, so aim and resample the bow
	# before reading the hand: the arrow leaves on the live crosshair line.
	rig.aim_at(aim)
	rig.refresh_bow_pose()
	var origin: Vector3 = rig.get_arrow_origin()
	var base := aim - origin
	if base.length_squared() < 0.0001:
		base = -rig.global_basis.z
	var profile: Dictionary = Archer.BOW_DATA[
		clampi(int(rig.bow_index), 0, Archer.BOW_DATA.size() - 1)]
	var speed := float(profile.speed) * float(effect.get("arrow_speed_scale", 1.0))
	var pierce := int(effect.get("pierce", 0))
	var shots := int(effect.get("shots", 1)) if kind == "volley" else 1
	var excluded: Array[RID] = []
	if actor is CollisionObject3D:
		excluded.append(actor.get_rid())
	for shot in shots:
		# A skill looses arrows like a bow does: one shaft out of the party quiver
		# each. A volley that outruns the quiver fires only what is left in it, so
		# no skill can spend the count past zero.
		if not _take_arrow():
			break
		# A barrage spreads by beat, a volley by arrow in the same beat.
		var pattern_index := index if kind == "barrage" else shot
		var offsets: Vector2 = AbilityFx.shot_offsets(definition, pattern_index)
		var direction := AbilityFx.rotate_direction(base, offsets.x, offsets.y)
		var arrow := Arrow.new()
		arrow.source_id = int(actor.slot)
		arrow.shooter = actor
		arrow.hit_mask = TARGET_MASK
		arrow.authoritative_damage = true
		add_child(arrow)
		arrow.launch(origin, direction, speed, damage, excluded, origin, pierce)
		_track(arrow)


## One shaft out of the party quiver, through the world's own spend funnel so the
## co-op peers are told about it too. A node with no world behind it - a harness
## that stands this one up on its own - looses free rather than guessing at a
## quiver it was never handed.
func _take_arrow() -> bool:
	if _world == null or not _world.has_method("spend_arrow"):
		return true
	return bool(_world.call("spend_arrow"))


## Fireball / bone spear: the projectile owns its flight and presentation, and
## the owning combat resolves the blast so armour, blocks and blood behave like
## every other hit.
func _launch_spell(actor, runner, definition: Dictionary, damage: float) -> void:
	var effect: Dictionary = definition.get("effect", {})
	var rig = actor.rig
	var origin: Vector3 = rig.cast_origin()
	var aim: Vector3 = runner.combat.aim_point
	var direction := aim - origin
	if direction.length_squared() < 0.0001:
		direction = -rig.global_basis.z
	var spell := SpellProjectile.new()
	spell.kind = str(effect.get("projectile", "fireball"))
	spell.hit_mask = TARGET_MASK
	spell.shooter = actor
	spell.authoritative_damage = true
	add_child(spell)
	var excluded: Array[RID] = []
	if actor is CollisionObject3D:
		excluded.append(actor.get_rid())
	spell.launch(origin, direction, float(effect.get("speed", 22.0)), damage,
		excluded, spell.hit_mask, true, rig.global_position,
		float(effect.get("radius", 0.0)), int(effect.get("pierce", 0)))
	spell.source_rig = rig
	spell.set_meta("stagger", float(effect.get("stagger", 0.0)))
	spell.detonated.connect(_on_spell_detonated.bind(spell, actor.combat))
	_track(spell)


func _on_spell_detonated(centre: Vector3, _direction: Vector3, spell, combat_ref) -> void:
	if not is_instance_valid(spell) or not is_instance_valid(combat_ref):
		return
	if spell.blast_radius <= 0.0:
		return
	combat_ref.ability_blast(centre, spell.blast_radius, spell.damage,
		float(spell.get_meta("stagger", 0.0)))


# --- backstab --------------------------------------------------------------

## The blink smokes the old spot and, on the authority only, moves the body
## behind the preflight target; the stab spends the doubled dagger damage on the
## body the caster is now behind.
func _backstab(actor, cue: String, damage: float) -> void:
	var rig = actor.rig
	var target: Node3D = null
	if actor.has_meta("backstab_target"):
		var resolved = actor.get_meta("backstab_target")
		if is_instance_valid(resolved) and resolved is Node3D:
			target = resolved
	var forward: Vector3 = actor.combat.aim_point - rig.global_position
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -rig.global_basis.z
		forward.y = 0.0
	forward = forward.normalized()
	if cue == "blink":
		_puff(rig.global_position)
		if target == null:
			return
		var spot: Dictionary = BackstabAbility.behind_spot(_space(), target)
		if not bool(spot.get("ok", false)):
			return
		BackstabAbility.blink(actor, spot.position, float(spot.yaw))
		_puff(rig.global_position)
		return
	if cue != "stab":
		return
	if target == null:
		target = _backstab_target(actor)
	if target != null and target.get("alive") != false:
		BackstabAbility.strike(actor, target, damage, int(actor.slot))
	if target != null:
		_fx_call("backstab_flash", [target.global_position - forward * 0.35
			+ Vector3.UP * 1.15, forward])
	if actor.has_meta("backstab_target"):
		actor.remove_meta("backstab_target")


func _backstab_target(actor) -> Node3D:
	var exclude: Array[RID] = []
	if actor is CollisionObject3D:
		exclude.append(actor.get_rid())
	return BackstabAbility.find_target(_space(), actor.global_position,
		actor.combat.aim_point, TARGET_MASK, BACKSTAB_RANGE, exclude)


# --- melee -----------------------------------------------------------------

## The blade beats. The hit itself goes through the body's own combat so blocks,
## armour, blood and damage numbers are the authored swing's; the presentation is
## the frontier's, one branch per skill shape.
func _melee(actor, runner, definition: Dictionary, cue: String, index: int,
		damage: float) -> void:
	var effect: Dictionary = definition.get("effect", {})
	var rig = actor.rig
	var id := str(definition.get("id", ""))
	var radius := float(effect.get("radius", 1.7))
	var arc := float(effect.get("arc_degrees", 360.0))
	var ring := str(effect.get("kind", "")) == "melee_ring" or arc >= 359.0
	var forward: Vector3 = runner.combat.aim_point - rig.global_position
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -rig.global_basis.z
		forward.y = 0.0
	forward = forward.normalized()
	# The greatsword's wind-up is presentation only: the blade gathers speed
	# before the ring cue spends the hit.
	if cue == "wind":
		_fx_call("blade_trail", [rig, 0.55])
		return
	# The lunge's dash beat marks the takeoff with its wake; the thrust cue, not
	# the dash, spends the hit.
	if cue == "dash":
		_fx_call("lunge_wake", [rig, 0.40])
		return
	# A travelling skill already swept its lane, so the closing beat shares that
	# victim set and never hits a body the dash passed through twice.
	var victims: Dictionary = {}
	if bool(effect.get("path_damage", false)):
		victims = runner.active_victims
	runner.combat.ability_strike(radius, arc, damage,
		float(effect.get("stagger", 0.0)), ring, not ring, victims)
	if id.begins_with("shield_"):
		# The shield face is the weapon, so the impact sits on the boss instead
		# of a crescent that never matched the hands.
		_fx_call("shield_impact", [rig.global_position + forward * 0.95
			+ Vector3.UP * 1.05, forward, radius, id == "shield_slam"])
		if ring:
			_fx_call("ground_shockwave", [rig.global_position, radius])
		return
	if ring:
		_fx_call("spin_burst", [rig.global_position, radius])
		_fx_call("blade_trail", [rig, 0.30])
	elif id == "double_slash":
		_fx_call("blade_trail", [rig, 0.24])
	elif id == "lunge_thrust":
		_fx_call("blade_trail", [rig, 0.18])
	else:
		var cues: Array = definition.get("cues", [])
		var alternate := 1.0 if index % 2 == 0 else -1.0
		if cues.size() <= 1:
			alternate = 0.0
		_fx_call("slash_arc", [rig.global_position,
			forward.rotated(Vector3.UP, 0.32 * alternate), radius,
			minf(arc, 200.0), AbilityFx.STEEL])


# --- helpers ---------------------------------------------------------------

## One `AbilityFx` beat with the world as its parent. The FX helpers add Node3D
## children, so a missing world (a bare test harness) silently skips the show
## instead of erroring on a `Node` parent. The dispatch is spelled out because
## these are static functions on a script resource, not methods of an object.
func _fx_call(method: String, args: Array) -> void:
	var parent := _fx_parent()
	if parent == null:
		return
	match method:
		"blade_trail":
			AbilityFx.blade_trail(parent, args[0], float(args[1]))
		"lunge_wake":
			AbilityFx.lunge_wake(parent, args[0], float(args[1]))
		"smoke_puff":
			AbilityFx.smoke_puff(parent, args[0], float(args[1]), bool(args[2]))
		"shield_impact":
			AbilityFx.shield_impact(parent, args[0], args[1], float(args[2]), bool(args[3]))
		"ground_shockwave":
			AbilityFx.ground_shockwave(parent, args[0], float(args[1]))
		"spin_burst":
			AbilityFx.spin_burst(parent, args[0], float(args[1]))
		"slash_arc":
			AbilityFx.slash_arc(parent, args[0], args[1], float(args[2]),
				float(args[3]), args[4])
		"backstab_flash":
			AbilityFx.backstab_flash(parent, args[0], args[1])


func _fx_parent() -> Node3D:
	if _world != null and is_instance_valid(_world):
		return _world
	return get_parent() as Node3D


func _space() -> PhysicsDirectSpaceState3D:
	var parent := _fx_parent()
	if parent == null or not parent.is_inside_tree():
		return null
	var world: World3D = parent.get_world_3d()
	if world == null:
		return null
	return world.direct_space_state


func _puff(at: Vector3) -> void:
	_fx_call("smoke_puff", [at, 1.0, true])


## Keep the missile list valid and bounded: a shot that freed itself (an impact,
## a timeout) is dropped, and the oldest still-listed shot pays for a new one.
func _track(missile: Node) -> void:
	_prune_missiles()
	_missiles.append(missile)
	while _missiles.size() > MAX_MISSILES:
		var oldest = _missiles.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


func _prune_missiles() -> void:
	for index in range(_missiles.size() - 1, -1, -1):
		if not is_instance_valid(_missiles[index]):
			_missiles.remove_at(index)


func _prune_bodies() -> void:
	for index in range(_bodies.size() - 1, -1, -1):
		if not is_instance_valid(_bodies[index]):
			_bodies.remove_at(index)
