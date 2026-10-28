extends Node3D
## GHOST OF THE WARBAND: the blood a body on the ground is losing.
##
## A downed body keeps dripping until it is either stood back up or dead, and the
## drips come faster and heavier as the thirty second bleed clock runs out. That
## quickening is the only sign of the timer the player gets in the world, so the
## rate is read from `Archer.blood_loss`, which the body writes from its own
## clock - this node never keeps a clock of its own.
##
## Presentation only, and deliberately so: it asks the shared blood field
## (`BloodFx`) for the pulse, which means the stains, the spray and the render
## budget all belong to the one blood system the rest of the game uses. Nothing
## here reads or writes health, damage or authority, so a peer that never applied
## the damage drips exactly like the host that did.
##
## `ArenaActor` builds one with the body and parks it; `attach()` on the fall and
## `detach()` on the revive and the death are the whole lifecycle. The pulse also
## stops itself the moment it finds its body standing or dead, so no path - host
## step, revive channel, replicated snapshot - can leave a corpse dripping over
## the pool its death laid.

const BloodFx = preload("res://scripts/blood_fx.gd")

## How far from the body's centre a drip may start. The wound is somewhere on the
## chest, not a line of spots straight down the spine.
const WOUND_RADIUS := 0.32
## The downed lie is a hand's width off the floor, so the blood leaves the body
## rather than the ground under its boots.
const WOUND_HEIGHT := 0.16

## The body being drained; null while parked. Set through `attach()`.
var actor = null

## Seconds banked toward the next pulse.
var _elapsed := 0.0
## One wound pattern per body, so two bodies bleeding side by side do not drip in
## step with each other.
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = get_instance_id()
	set_physics_process(false)

## Start dripping for `body` (an `ArenaActor`). Returns whether it took, so a
## caller can tell "that one is bleeding" from "that one is not down".
func attach(body) -> bool:
	actor = body
	_elapsed = 0.0
	var draining := is_instance_valid(actor) and bool(actor.downed) \
		and bool(actor.alive)
	set_physics_process(draining)
	return draining

## Stop dripping. The body keeps the blood it already lost; nothing emits after
## this call.
func detach() -> void:
	actor = null
	_elapsed = 0.0
	set_physics_process(false)

## True while this node is actually dripping for a body on the ground. A parked
## drip holds no body, so nothing can read "attached" off a corpse.
func attached() -> bool:
	return is_instance_valid(actor) and is_physics_processing()

## Physics, not idle: the bleed clock the rate follows is a physics clock, and a
## fixed step keeps the pulse spacing the same on every machine - the same reason
## the crawl runs its drag on this clock.
func _physics_process(delta: float) -> void:
	if not is_instance_valid(actor) or not bool(actor.downed) \
			or not bool(actor.alive):
		detach()
		return
	var fraction := _blood_loss()
	var interval := DownedRules.drip_interval(fraction)
	_elapsed += maxf(delta, 0.0)
	if _elapsed < interval:
		return
	# One pulse per frame at most: a long frame banks its remainder instead of
	# firing every pulse it skipped at once, which would read as a splash.
	_elapsed = minf(_elapsed - interval, interval)
	_pulse(fraction)

## The fraction of the bleed clock this body has spent, as the body itself last
## wrote it. A body with no rig drips at the slowest rate rather than guessing.
func _blood_loss() -> float:
	if not is_instance_valid(actor):
		return 0.0
	var rig = actor.rig
	if not is_instance_valid(rig):
		return 0.0
	return clampf(float(rig.blood_loss), 0.0, 1.0)

## One drip: blood wells out of the body and falls back to the ground under and
## around it. The field's own spray does the falling and leaves the stains, so
## the ground this body marks is the same blood the fight already spilled.
func _pulse(fraction: float) -> void:
	if not is_inside_tree():
		return
	var angle := _rng.randf() * TAU
	var offset := Vector3(cos(angle), 0.0, sin(angle)) \
		* _rng.randf_range(0.0, WOUND_RADIUS)
	var at: Vector3 = actor.global_position + offset + Vector3.UP * WOUND_HEIGHT
	BloodFx.impact(self, at, Vector3.UP, DownedRules.drip_volume(fraction), false)
