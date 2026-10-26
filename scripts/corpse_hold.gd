extends RefCounted
## How long a defeated mob stays where it fell.
##
## Every mob kind shares one lifetime so a fight leaves a battlefield instead of
## a row of four-second ghosts; the corpse keeps its settled ragdoll pose (or
## its authored collapse for procedural bodies) and its final blood pools for
## the whole five minutes, then dissolves. The dissolve shrinks a presentation
## container, never the CharacterBody root, so any late ray or loot query on
## the root keeps its identity transform.

## Five minutes by default. Callers may pass a shorter delay for a scripted
## encounter, but the shared default is what the frontier, delve and arena
## corpses use.
const SECONDS := 300.0
const DISSOLVE_SECONDS := 0.6

## Starts a tween on `host` that holds, dissolves `shrink` and frees the body.
static func hold(host: Node, shrink: Node3D, delay: float = SECONDS) -> Tween:
	var tween := host.create_tween()
	append(tween, host, shrink, delay)
	return tween

## Adds the hold/dissolve/free steps to an existing tween, after whatever
## collapse animation the caller already queued.
static func append(tween: Tween, host: Node, shrink: Node3D,
		delay: float = SECONDS) -> void:
	if delay > 0.0:
		tween.tween_interval(delay)
	if is_instance_valid(shrink):
		tween.tween_property(shrink, "scale", Vector3.ONE * 0.01, DISSOLVE_SECONDS)
	tween.tween_callback(host.queue_free)
