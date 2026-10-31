class_name CrawlToSafety
extends Node
## GHOST OF THE WARBAND: the crawl a downed body makes under a soul's own keys.
##
## The node owns no lifecycle of its own: it reads whether the body it is
## attached to is downed every physics frame and, while it is, drags it at
## `WarbandContracts.DOWNED_CRAWL_SPEED` in the direction its soul is holding.
##
## Only a body with a soul inside it crawls. A mercenary the AI drives stays
## exactly where it fell: the squad's rescue walks to it, stands over it and
## holds the five second channel, and a patient that kept dragging itself round
## the field walked out of that reach every frame the channel was open - which
## is why an AI squad could never pick one of its own up. The ground a still
## body holds is also the one thing a revive channel can be aimed at.
##
## The move goes through the actor's own capsule (`WarbandBody.crawl_step`), so a
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
## True: the body keeps its head toward where it is going and drags itself
## backwards. False: it turns and crawls forwards along the same bearing.
var reverse := true
## True while a soul is inside this body: the crawl then reads the player's own
## intent (`WarbandBody.move_direction`). False for every AI-driven body, which
## holds its ground. A body that keeps sliding under a player's hands is the one
## thing a downed body must never do; a body that slides out from under a
## rescuer's hands is the one thing a rescue must never face.
var manual := false

## Start dragging `body` (a `WarbandBody`). Returns whether the body can be
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

func _physics_process(delta: float) -> void:
	if not is_instance_valid(actor) or not bool(actor.downed) or not bool(actor.alive):
		return
	# Nobody inside: the body holds the ground it fell on, and that is the point
	# of the rule. The squad's rescue is the only thing that moves it from here,
	# and it moves the rescuer to the body instead.
	if not manual:
		return
	_manual_step(delta)

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
