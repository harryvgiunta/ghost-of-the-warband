extends Node
## The one sweep that parks the wilderness.
##
## A body past `MobLod.DORMANT_DISTANCE` from every ranger cannot be seen and
## cannot see: at that range the frontier's fog is already opaque. Left on its
## tick budget it still costs a tick twenty-four frames in three, for a body
## nobody is looking at. This node is what replaces that cost: three sweeps a
## second over the `wild_mobs` group, and a parked body has no physics process,
## no draw call and no state change until a ranger walks back inside
## `MobLod.WAKE_DISTANCE`.
##
## The rule stays with the body (`mob_lod_sweep`): only a body knows its
## rangers, whether something is hunting it, whether its feet are down and
## which node to hide. This node owns the clock, so a new mob family only has
## to answer that one call.

const MobSenses = preload("res://scripts/mob_senses.gd")

## Seconds between sweeps. A sprinting ranger covers 2.5 m in this time and the
## hysteresis band is 20 m wide, so nothing can pass through the band unseen.
const INTERVAL := 0.35

## Sweeps run so far, and bodies found parked by the last one: diagnostics for
## the budget regression and the session log.
var sweeps := 0
var parked := 0

var _elapsed := 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < INTERVAL:
		return
	_elapsed = fmod(_elapsed, INTERVAL)
	sweep()


## One pass over every wilderness body: each works out for itself whether it
## parks or wakes. Bodies from other families (a sealed delve wave, an arena
## bot) simply do not answer `mob_lod_sweep` and are left alone.
func sweep() -> void:
	sweeps += 1
	var sleeping := 0
	for body in get_tree().get_nodes_in_group(MobSenses.GROUP):
		if not is_instance_valid(body):
			continue
		if not body.has_method("mob_lod_sweep"):
			continue
		body.mob_lod_sweep()
		if bool(body.get("dormant")):
			sleeping += 1
	parked = sleeping
