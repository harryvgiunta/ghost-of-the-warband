extends "res://scripts/arena_actor.gd"
## Player body for the Sunken Delve.
##
## Inherits the whole arena fighter (rig, combat, dodging, snapshots) but the
## delve has no round resets: a downed player stays down until the run ends or a
## survivor is raised at the surface. The inherited respawn countdown is pushed
## out of reach and `step` never advances a dead body.

signal fell(slot: int, source_id: int)


func _ready() -> void:
	super()
	# Devils live on collision layer 2; the arena default (4) would let a player
	# swing through them without ever producing a hit.
	combat.target_mask = 2
	combat.damage_enabled = authoritative


func step(delta: float, actors: Array, simulation_tick: int = 0) -> void:
	if not alive:
		return
	combat.damage_enabled = authoritative
	super.step(delta, actors, simulation_tick)


func take_damage(amount: float, source_id: int, headshot: bool = false, react: bool = true) -> void:
	if not authoritative or not alive or source_id == slot:
		return
	var applied: float = amount * Hitbox.damage_multiplier(headshot) * (1.0 - rig.armor_reduction())
	health = maxf(0,health - applied)
	DamageNumbers.spawn(get_parent(),global_position,applied,"self" if is_local else "hit",headshot,health <= 0.0)
	if react:
		var seconds: float = combat.stagger_from_damage(applied)
		rig.set_hit_react(seconds)
		dodge.reset()
	if health <= 0:
		alive = false
		deaths += 1
		# Keep the inherited countdown from ever firing; revival is an explicit
		# `respawn_at` call from the run controller instead.
		respawn = 1.0e9
		combat.stop()
		reset_stance()
		roll.reset()
		collision_layer = 0
		collision_mask = 0
		rig.visible = false
		fell.emit(slot,source_id)
		killed.emit(slot,source_id)


func respawn_at(point: Vector3) -> void:
	spawn_point = point
	revive()
	position = point + Vector3(0,0.08,0)
	combat.damage_enabled = authoritative


func is_downed() -> bool:
	return not alive
