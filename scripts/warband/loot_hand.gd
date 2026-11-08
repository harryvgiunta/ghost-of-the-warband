class_name WarbandLootHand
extends Node
## The take: a **right click** on a body or a drop, and what is on it comes up at
## once.
##
## One gesture, no window and no channel. The press resolves what is under the
## crosshair and in the body's own reach through `target_at`, and `take_now` books
## it: a corpse gives its whole list, and a drop gives itself and every piece
## piled beside it (a kill's spoils are one pile). Nothing is dressed onto the body
## that searched - a take is a take, and `K` is the armorer's verb
## (`world_scene._try_loot`: the piece snaps into the hand it belongs in).
##
## Below, in the delve, the same verb empties the container into the delve's own
## inventory rather than the town's pool; `loot_vacuum` reads where it is by the
## body's feet, so this node books nothing itself. Every piece goes through the
## vacuum's one booking path, so a press cannot pay twice.
##
## A guest owns no booking: the host's world spawns the kills and books them, so a
## guest's click resolves the target here and sends the take as an intent. The host
## empties its corpse or drop and copies the record back.

const SummaryScript = preload("res://scripts/warband/loot_summary.gd")

## How far from the clicked drop a second drop is swept in: a pile of spoils off
## one kill is one take.
const PILE_RADIUS := 2.0
## What a world that publishes no `LOOT_REACH` gets: the campaign's own reach.
const DEFAULT_REACH := 2.6
## How long the finished line stays up.
const SUMMARY_SECONDS := 3.5
## The local peer, the one the world's own loot keys take for.
const LOCAL_PEER := 1

const KIND_CORPSE := "corpse"
const KIND_DROP := "drop"

## The world this hand acts in - read for its loot vacuum, HUD, controller and
## reach. Kept untyped because the world scene has no class name of its own.
var world = null

var _loot = null
var _hud = null
var _controller = null
var _reach := DEFAULT_REACH

## The line the last take raised, "" until one has been made.
var _summary := ""


## Adopt the world's loot plumbing. Every part is optional: a world without a
## controller still loots, it just has no peer to name.
func setup(world_ref) -> void:
	world = world_ref
	if world == null or not is_instance_valid(world):
		return
	_loot = world.get("loot")
	_hud = world.get("hud")
	_controller = world.get("controller")
	var published: Variant = _constant("LOOT_REACH")
	if typeof(published) == TYPE_INT or typeof(published) == TYPE_FLOAT:
		_reach = float(published)


## The right click, resolved and taken in one call. True when something came up -
## the caller must let the press be a loot, not a guard or a swing. False means
## there is nothing lootable at `point` (or this machine does not own the loot), and
## the press is the caller's.
##
## `aim_target` is the collider the crosshair ray met, when the caller has one. A
## fighter under the reticle is the thing the player aimed at, so a press on it is
## a cut and never a loot - even when the corpse it stands over, or the blade that
## fell beside it, is inside the same arm's reach. Measuring only the distance from
## the aim point let a drop lying within a step of a mob steal every click aimed at
## that mob: the body ducked, the fight went on, and the report was "I cannot
## attack any more".
func try_click(actor, point: Vector3, aim_target: Variant = null) -> bool:
	return not take_now(actor, target_at(actor, point, aim_target)).is_empty()


## What a press at `point` would take, without taking it: `{kind, corpse_id,
## pickup}` for the nearest body with something left on it, else the nearest open
## drop, or `{}`.
func target_at(actor, point: Vector3, aim_target: Variant = null) -> Dictionary:
	if _loot == null or not is_instance_valid(_loot):
		return {}
	if not _can_work(actor):
		return {}
	if _aims_at_a_living_body(aim_target):
		return {}
	# The take is the body's own work, so the piece has to be in the body's reach
	# as well as under the crosshair. Measuring only from `point` let a click aimed
	# at a fighter standing over a corpse loot that corpse from across the field -
	# the click crouched and worked the ground instead of swinging, which is the
	# report "I cannot attack any more".
	var body_at: Vector3 = (actor as Node3D).global_position
	var corpse_id: int = _loot.corpse_at(point, _reach)
	# A body already emptied is ground, not a container: it must never shadow the
	# blade that fell beside it, or a right click on that weapon would take the
	# empty corpse and nothing would come up.
	if corpse_id != 0 and not _loot.corpse_items(corpse_id).is_empty() \
			and body_at.distance_to(_loot.corpse_position(corpse_id)) <= _reach:
		return {"kind": KIND_CORPSE, "corpse_id": corpse_id, "pickup": null}
	var pickup: WarbandPickup = _drop_at(point)
	if pickup != null and body_at.distance_to(pickup.global_position) <= _reach:
		return {"kind": KIND_DROP, "corpse_id": 0, "pickup": pickup}
	return {}


## Take everything `target` names, at once. A corpse gives its whole list; a drop
## gives itself and every open drop within `PILE_RADIUS` of it, so one click
## gathers a kill's spoils. Nothing is booked onto the body that took it: the pool
## is the armorer, and `K` is the verb that dresses a piece.
##
## Answers what came up, in booking order; empty when there was nothing to take.
func take_now(actor, target: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	if _is_client():
		return ids
	if target.is_empty() or not _can_work(actor) or _loot == null:
		return ids
	var anchor := Vector3.ZERO
	var kind := str(target.get("kind", ""))
	if kind == KIND_CORPSE:
		var corpse_id := int(target.get("corpse_id", 0))
		anchor = _loot.corpse_position(corpse_id)
		var taken: Dictionary = _loot.take_all_from_corpse(corpse_id, _local_peer(), false)
		for entry in taken.get("ids", []):
			ids.append(str(entry))
	elif kind == KIND_DROP and target.get("pickup") != null and is_instance_valid(target.get("pickup")):
		anchor = (target.get("pickup") as Node3D).global_position
	else:
		return ids
	for pickup in _loot.pickups():
		if not is_instance_valid(pickup) or pickup.collected or pickup.blocked_for(_local_peer()):
			continue
		if pickup.global_position.distance_to(anchor) > PILE_RADIUS:
			continue
		var result: Dictionary = _loot.quick_loot(pickup, _local_peer(), false)
		if bool(result.get("ok", false)):
			ids.append(str(result.get("item_id", "")))
	if ids.is_empty():
		return ids
	_summary = SummaryScript.describe(ids)
	if _hud != null and is_instance_valid(_hud) and _hud.has_method("set_status"):
		_hud.set_status(_summary, SUMMARY_SECONDS)
	return ids


## The line the last take raised, "" until one has been made.
func last_summary() -> String:
	return _summary


# --- internals -------------------------------------------------------------

## Whether the press was aimed at a body that can still fight. A corpse in the
## same ray - `alive` false - is ground to work, which is what makes looting the
## body you just put down a click and not a swing.
func _aims_at_a_living_body(target: Variant) -> bool:
	if target == null or not is_instance_valid(target) or not (target is Node):
		return false
	var node := target as Node
	if not node.has_method("take_damage"):
		return false
	return node.get("alive") == true


## The nearest open drop to `point` inside the reach, or null. A drop locked
## against this peer by its own dropper is not offered.
func _drop_at(point: Vector3) -> WarbandPickup:
	var best: WarbandPickup = null
	var best_distance := maxf(_reach, 0.0)
	for pickup in _loot.pickups():
		if not is_instance_valid(pickup) or pickup.collected:
			continue
		if pickup.blocked_for(_local_peer()):
			continue
		var distance: float = pickup.global_position.distance_to(point)
		if distance <= best_distance:
			best_distance = distance
			best = pickup
	return best


## A live warband body: one that can search the ground. Anything without the
## crouch (a mob, a prop, a corpse) is not a hand that loots, and a downed body is
## somebody else's problem.
func _can_work(actor) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	if not (actor as Object).has_method("set_crouch"):
		return false
	if bool(actor.get("downed")) or actor.get("alive") == false:
		return false
	return true


## The peer this machine's own press belongs to. The host is 1; a guest is its
## ENet id, and a local take named after the wrong soul would dress the wrong
## body even if the booking itself were right.
func _local_peer() -> int:
	if _controller != null and is_instance_valid(_controller):
		var raw: Variant = _controller.get("local_peer_id")
		if typeof(raw) == TYPE_INT and int(raw) > 0:
			return int(raw)
	return LOCAL_PEER


func _is_client() -> bool:
	if world == null or not is_instance_valid(world):
		return false
	return bool(world.get("_client"))


## A number the world publishes as a script constant. `Object.get` answers
## variables and not constants, so the constant map is asked directly.
func _constant(key: String) -> Variant:
	if world == null or not is_instance_valid(world):
		return null
	var script: Script = world.get_script()
	if script == null:
		return null
	return script.get_script_constant_map().get(key)
