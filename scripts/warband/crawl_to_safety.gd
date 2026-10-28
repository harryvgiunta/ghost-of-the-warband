class_name CrawlToSafety
extends Node
## GHOST OF THE WARBAND: the backwards crawl a downed body makes toward safety.
##
## The node owns no lifecycle of its own: it reads whether the body it is
## attached to is downed every physics frame and, while it is, drags it at
## `WarbandContracts.DOWNED_CRAWL_SPEED` toward `ArenaActor.downed_crawl_target()`
## - away from the blow that put it down, biased toward an explicit safe anchor
## or the nearest standing friend.
##
## The move goes through the actor's own capsule (`ArenaActor.crawl_step`), so a
## wall, a tree or a crate stops the crawl instead of letting it pass through;
## this node never touches `global_position` itself. A standing body, a revived
## body and a corpse are all left exactly where they are.
##
## Add the node to the tree (any parent will do - the actor's own scene is the
## natural one) and call `attach()`; without a tree no physics frame arrives and
## nothing moves.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")

## The body being dragged. Set through `attach()`; null when detached.
var actor = null
## Contract pace; the crawl never runs faster than this.
var speed := Contracts.DOWNED_CRAWL_SPEED
## True: the body keeps its head toward the blow and drags itself backwards, so
## it can still see the thing that put it down. False: it turns and crawls
## forwards along the same bearing.
var reverse := true
## True while a soul is inside this body: the crawl then reads the player's own
## intent (`ArenaActor.move_direction`) instead of dragging the body to safety,
## and it stands still when no key is held. A body that keeps sliding under a
## player's hands is the one thing a downed body must never do.
var manual := false

var _anchor := Vector3.ZERO
var _has_anchor := false
## Bodies a downed fighter will crawl toward when no explicit anchor is given.
var _friends: Array = []

## Start dragging `body` (an `ArenaActor`). Returns whether the body can be
## crawled at all, so a caller can report "that one is past help".
func attach(body) -> bool:
	actor = body
	return is_instance_valid(actor)

## Stop dragging. The body keeps whatever ground it covered and its horizontal
## velocity is cleared, so a detached crawl does not slide on afterwards.
func detach() -> void:
	if is_instance_valid(actor):
		actor.velocity.x = 0.0
		actor.velocity.z = 0.0
	actor = null

func attached() -> bool:
	return is_instance_valid(actor)

## A patch of cover, a friendly body, a lit doorway: the crawl aims here when
## the blow's own bearing alone is not the safest line. Finiteness is the test,
## so a caller never has to pass a second flag.
func set_anchor(point: Vector3) -> void:
	_anchor = point
	_has_anchor = point.is_finite()

func clear_anchor() -> void:
	_has_anchor = false

## Bodies the crawl may treat as friends when no anchor is set.
func set_friends(list: Array) -> void:
	_friends = list

## The point the crawl aims at this frame: the explicit anchor when there is
## one, otherwise the nearest standing friend. `{point, known}` - `known` is
## false when there is nothing safe to crawl toward.
func safe_point() -> Dictionary:
	if _has_anchor:
		return {"point": _anchor, "known": true}
	var nearest := Vector3.ZERO
	var best := INF
	for friend in _friends:
		if not is_instance_valid(friend) or friend == actor:
			continue
		if not bool(friend.get("alive")) or bool(friend.get("downed")):
			continue
		var distance: float = actor.global_position.distance_squared_to(friend.global_position)
		if distance < best:
			best = distance
			nearest = friend.global_position
	return {"point": nearest, "known": best < INF}

func _physics_process(delta: float) -> void:
	if not is_instance_valid(actor) or not bool(actor.downed) or not bool(actor.alive):
		return
	if manual:
		_manual_step(delta)
		return
	var safe := safe_point()
	# The actor computes the destination so its own `downed_crawl_target()` and
	# this node can never disagree about where the body is going.
	if bool(safe.known):
		actor.set_safe_anchor(safe.point)
	else:
		actor.clear_safe_anchor()
	var target: Vector3 = actor.downed_crawl_target()
	var travel := Vector3(target.x - actor.global_position.x, 0.0, target.z - actor.global_position.z)
	if travel.length() <= DownedRules.CRAWL_ARRIVAL:
		actor.crawl_step(actor.global_position, speed, delta)
		return
	actor.crawl_step(target, speed, delta)
	_face(travel)

## The soul's own crawl: the keys are the whole of the intent, and no key means no
## movement. It runs at the same contract pace through the same capsule, so a wall
## or a trunk still stops it.
func _manual_step(delta: float) -> void:
	var intent: Vector2 = actor.move_direction
	if intent.length() < 0.05:
		actor.crawl_step(actor.global_position, 0.0, delta)
		return
	var here: Vector3 = actor.global_position
	var travel := Vector3(intent.x, 0.0, intent.y).normalized()
	actor.crawl_step(here + travel * 2.0, speed, delta)
	_face(travel)


## Point the model along the crawl. The rig's forward is `-basis.z`, which is
## the same `atan2` the locomotion code feeds `Basis(UP, yaw)`.
func _face(travel: Vector3) -> void:
	if not is_instance_valid(actor.rig):
		return
	var yaw := atan2(-travel.x, -travel.z)
	if reverse:
		# Dragging backwards: the head stays on the killer, the body moves away.
		yaw += PI
	actor.rig.global_rotation.y = yaw
