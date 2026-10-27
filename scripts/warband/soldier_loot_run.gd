class_name SoldierLootRun
extends Node
## The visible end-of-battle loot run: survivors physically jog to the drops.
##
## The shared stash is the only inventory the warband has, so this node owns no
## items at all - it walks a soldier to a piece and hands the piece to
## `WarbandLoot.quick_loot()`, which books it into the stash exactly as a human
## pick does. What it adds is the half-second of legs between the two: each
## survivor gets the nearest drop nobody else claimed, travels to it at a jog
## pace while the rig cycles its step cycle, and only then takes it.
##
## A body that is downed or dead is never moved. Downed bodies belong to the
## crawl and the revive channel; a loot run that dragged them across the field
## would undo both.

signal finished(collected: int)

## Jog pace. A drop one to two metres away (the usual battlefield case) is
## reached in 0.3-0.5 s; a piece further out simply takes proportionally longer
## instead of teleporting the body.
const JOG_SPEED := 5.0
const JOG_MIN_SECONDS := 0.3
## How close a body must be to a piece to take it. A drop inside this radius at
## the start of a run is picked up where the soldier stands; a jog ends here.
const ARRIVE_REACH := 1.0

var _loot = null
var _bodies: Array = []
## Live jobs: {actor, pickup, from, to, elapsed, seconds}.
var _jobs: Array = []
var _running := false
var _done := true
var _collected := 0

## Point the run at the battlefield's loot vacuum and the bodies it may use. The
## warband itself is not held: every stash row, value and notification is booked
## by `WarbandLoot`, so nothing here can disagree with the shared stash. The
## bodies are re-checked every frame, never trusted once.
func setup(_warband, loot, bodies: Array) -> void:
	_loot = loot
	_bodies = bodies.duplicate()

## Send every standing soldier to its nearest unclaimed drop. A piece already at
## a soldier's feet is taken where the body stands; everything else gets a jog.
func run(pickups: Array) -> void:
	_jobs.clear()
	_collected = 0
	_done = false
	_running = true
	if _loot == null:
		push_error("SoldierLootRun: setup() needs the loot vacuum before run()")
		_finish()
		return
	var open := _open_pickups(pickups)
	for soldier in _soldiers():
		if open.is_empty():
			break
		var pickup = _nearest(soldier, open)
		if pickup == null:
			continue
		open.erase(pickup)
		if _ground_gap(soldier.global_position, pickup.global_position) <= ARRIVE_REACH:
			_take(pickup)
			continue
		_jobs.append(_begin_job(soldier, pickup))
	if _jobs.is_empty():
		_finish()

## True while soldiers are still walking or reaching for a piece.
func running() -> bool:
	return _running

## True once a run has completed and nothing is left in flight.
func done() -> bool:
	return _done and not _running

func _process(delta: float) -> void:
	if not _running:
		return
	var current := _jobs
	_jobs = []
	for job in current:
		if _advance(job, delta):
			_jobs.append(job)
	if _jobs.is_empty():
		_finish()

# --- internals -------------------------------------------------------------

func _begin_job(soldier: Node3D, pickup: WarbandPickup) -> Dictionary:
	var from := soldier.global_position
	var to := pickup.global_position
	# The drop lies on the ground; the body keeps its own footing on the way.
	to.y = from.y
	return {"actor": soldier, "pickup": pickup, "from": from, "to": to,
		"elapsed": 0.0,
		"seconds": maxf(JOG_MIN_SECONDS, _ground_gap(from, to) / JOG_SPEED)}

## One tick of one jog. Answers whether the job is still in flight; a soldier who
## fell, or a drop somebody else took, ends the job without a pickup.
func _advance(job: Dictionary, delta: float) -> bool:
	var actor = job.get("actor")
	if not _is_soldier(actor):
		return false
	var pickup = job.get("pickup")
	if not is_instance_valid(pickup) or bool(pickup.collected) or str(pickup.item_id).is_empty():
		_rest(actor)
		return false
	job["elapsed"] = float(job["elapsed"]) + delta
	var seconds := maxf(float(job["seconds"]), 0.0001)
	var progress := clampf(float(job["elapsed"]) / seconds, 0.0, 1.0)
	var from: Vector3 = job["from"]
	var to: Vector3 = job["to"]
	var next: Vector3 = from.lerp(to, progress)
	next.y = from.y
	var travel: Vector3 = next - (actor as Node3D).global_position
	(actor as Node3D).global_position = next
	# The jog is this body's work for the moment: the rig is told the travel so
	# the legs cycle, and the body's own walking intent is pinned so nothing else
	# drives it out from under the run.
	actor.move_direction = Vector2.ZERO
	actor.run_requested = false
	var rig = actor.get("rig")
	if is_instance_valid(rig):
		rig.set_locomotion(travel / maxf(delta, 0.0001), true)
	if progress < 1.0:
		return true
	_take(pickup)
	_rest(actor)
	return false

## Hand the piece to the shared vacuum. Every stash row, value and notification
## stays `WarbandLoot`'s business; a refused pick (already taken, missing stash)
## simply collects nothing.
func _take(pickup) -> void:
	if not is_instance_valid(pickup):
		return
	var result: Dictionary = _loot.quick_loot(pickup, 1)
	if bool(result.get("ok", false)):
		_collected += 1

func _rest(actor) -> void:
	if not is_instance_valid(actor):
		return
	actor.move_direction = Vector2.ZERO
	actor.run_requested = false
	var rig = actor.get("rig")
	if is_instance_valid(rig):
		rig.set_locomotion(Vector3.ZERO, true)

func _finish() -> void:
	_jobs.clear()
	_running = false
	_done = true
	finished.emit(_collected)

## A body the run may use: on its feet and still on the field.
func _is_soldier(actor) -> bool:
	if not is_instance_valid(actor) or not (actor is Node3D):
		return false
	if not bool(actor.get("alive")) or bool(actor.get("downed")):
		return false
	if not is_instance_valid(actor.get("rig")):
		return false
	return true

func _soldiers() -> Array:
	var out: Array = []
	for body in _bodies:
		if _is_soldier(body):
			out.append(body)
	return out

## The drops still lying in the world, pruned of anything already taken.
func _open_pickups(pickups: Array) -> Array:
	var out: Array = []
	for pickup in pickups:
		if not is_instance_valid(pickup) or not (pickup is WarbandPickup):
			continue
		if bool(pickup.collected) or str(pickup.item_id).is_empty():
			continue
		out.append(pickup)
	return out

## Nearest by ground distance, so a body never picks a drop it would have to
## climb or swim to instead of the piece beside its boots.
func _nearest(soldier: Node3D, open: Array):
	var best = null
	var best_distance := INF
	for pickup in open:
		var distance := _ground_gap(soldier.global_position, (pickup as Node3D).global_position)
		if distance < best_distance:
			best_distance = distance
			best = pickup
	return best

## Horizontal distance, which is the distance a walking body actually covers.
func _ground_gap(point: Vector3, other: Vector3) -> float:
	return Vector2(other.x - point.x, other.z - point.z).length()
