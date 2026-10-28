class_name SoldierLootRun
extends Node
## The visible end-of-battle loot run: survivors physically jog to the drops and
## to the bodies.
##
## The shared stash is the only inventory the warband has, so this node owns no
## items at all - it walks a soldier to a piece and hands the piece to
## `WarbandLoot`, which books it into the stash exactly as a human take does. What
## it adds is the half-second of legs between the two: each survivor gets the
## nearest target nobody else claimed, travels to it at a jog pace while the rig
## cycles its step cycle, and only then takes it.
##
## A corpse is one target, not a pile. One soldier walks to the body and strips
## everything still on it through `WarbandLoot.claim_corpse()`, so two soldiers can
## never book the same corpse piece twice, and a body beyond `BATTLE_REACH` is
## another squad's work rather than a reason to cross the field.
##
## A body that is downed or dead is never moved. Downed bodies belong to the
## crawl and the revive channel; a loot run that dragged them across the field
## would undo both.

signal finished(collected: int)

const LootScript = preload("res://scripts/warband/loot_vacuum.gd")

## Jog pace. A drop one to two metres away (the usual battlefield case) is
## reached in 0.3-0.5 s; a piece further out simply takes proportionally longer
## instead of teleporting the body.
const JOG_SPEED := 5.0
const JOG_MIN_SECONDS := 0.3
## How close a body must be to a piece to take it. A drop inside this radius at
## the start of a run is picked up where the soldier stands; a jog ends here.
const ARRIVE_REACH := 1.0
## Job kinds. A drop is a node in the world; a corpse is an id into the vacuum's
## corpse records, which is what makes a body one target instead of a pile.
const TARGET_DROP := "drop"
const TARGET_CORPSE := "corpse"

var _loot = null
var _bodies: Array = []
## Live jobs: `{kind, actor, pickup | corpse_id, from, to, elapsed, seconds}`.
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

## Send every standing soldier to its nearest unclaimed target. A piece or a body
## already at a soldier's feet is taken where the body stands; everything else
## gets a jog.
func run(pickups: Array) -> void:
	_jobs.clear()
	_collected = 0
	_done = false
	_running = true
	if _loot == null:
		push_error("SoldierLootRun: setup() needs the loot vacuum before run()")
		_finish()
		return
	var targets := _targets(pickups)
	for soldier in _soldiers():
		if targets.is_empty():
			break
		var index := _nearest_index(soldier, targets)
		if index < 0:
			continue
		var target: Dictionary = targets[index]
		targets.remove_at(index)
		if _ground_gap(soldier.global_position, target["at"]) <= ARRIVE_REACH:
			_claim(target)
			continue
		_jobs.append(_begin_job(soldier, target))
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

## Everything worth walking to: the open drops of the world and every body the
## vacuum still holds gear on. One list, so the nearest-target rule is the same
## for a piece on the ground and a piece on a corpse.
func _targets(pickups: Array) -> Array:
	var out: Array = []
	for pickup in pickups:
		if not is_instance_valid(pickup) or not (pickup is WarbandPickup):
			continue
		if bool(pickup.collected) or str(pickup.item_id).is_empty():
			continue
		out.append({"kind": TARGET_DROP, "pickup": pickup,
			"at": (pickup as Node3D).global_position})
	for corpse_id in _loot.corpse_ids():
		var id := int(corpse_id)
		out.append({"kind": TARGET_CORPSE, "corpse_id": id,
			"at": _loot.corpse_position(id)})
	return out

## The nearest target a soldier may take. A corpse is offered only inside
## `BATTLE_REACH`: a body across the field is another squad's work.
func _nearest_index(soldier: Node3D, targets: Array) -> int:
	var best := -1
	var best_distance := INF
	for index in targets.size():
		var target: Dictionary = targets[index]
		var distance := _ground_gap(soldier.global_position, target["at"])
		if str(target["kind"]) == TARGET_CORPSE and distance > LootScript.BATTLE_REACH:
			continue
		if distance < best_distance:
			best_distance = distance
			best = index
	return best

func _begin_job(soldier: Node3D, target: Dictionary) -> Dictionary:
	var from := soldier.global_position
	var to: Vector3 = target["at"]
	# Loot lies on the ground; the body keeps its own footing on the way.
	to.y = from.y
	var job := {"actor": soldier, "from": from, "to": to, "elapsed": 0.0,
		"kind": str(target["kind"]),
		"seconds": maxf(JOG_MIN_SECONDS, _ground_gap(from, to) / JOG_SPEED)}
	if job["kind"] == TARGET_CORPSE:
		job["corpse_id"] = int(target["corpse_id"])
	else:
		job["pickup"] = target["pickup"]
	return job

## One tick of one jog. Answers whether the job is still in flight; a soldier who
## fell, a drop somebody else took, or a body another soldier already stripped
## ends the job without a take.
func _advance(job: Dictionary, delta: float) -> bool:
	var actor = job.get("actor")
	if not _is_soldier(actor):
		return false
	if not _target_open(job):
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
	_claim(job)
	_rest(actor)
	return false

## Whether the thing the soldier is walking to is still worth the walk.
func _target_open(job: Dictionary) -> bool:
	if str(job.get("kind", TARGET_DROP)) == TARGET_CORPSE:
		return not _loot.corpse_items(int(job.get("corpse_id", 0))).is_empty()
	var pickup = job.get("pickup")
	if not is_instance_valid(pickup):
		return false
	return not bool(pickup.collected) and not str(pickup.item_id).is_empty()

## Hand the target to the vacuum. Every stash row, value and notification stays
## `WarbandLoot`'s business. Peer 0 says these are a squad's hands, not the
## player's body, so nothing snaps into a soul's gear behind their back - which is
## also why nothing here announces what it took.
func _claim(job: Dictionary) -> void:
	if str(job.get("kind", TARGET_DROP)) == TARGET_CORPSE:
		var claimed: Dictionary = _loot.claim_corpse(int(job.get("corpse_id", 0)), 0)
		_collected += int(claimed.get("count", 0))
		return
	var pickup = job.get("pickup")
	if not is_instance_valid(pickup):
		return
	var result: Dictionary = _loot.quick_loot(pickup, 0)
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

## Horizontal distance, which is the distance a walking body actually covers.
func _ground_gap(point: Vector3, other: Vector3) -> float:
	return Vector2(other.x - point.x, other.z - point.z).length()
