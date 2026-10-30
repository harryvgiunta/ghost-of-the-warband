class_name WarbandLootHand
extends Node
## The click that loots: aim at a body or a drop, work it, and the warband takes
## everything on it in one go.
##
## This is the one gesture - click the corpse, the body ducks, the stash fills -
## instead of a feed of pieces. A click on lootable ground starts a short channel
## on the body (it crouches, the HUD says so); when the channel ends the whole
## container is emptied through the loot vacuum's one booking path, the body
## straightens, and a single line says what came back. Nothing here books a piece
## itself, so a click cannot pay twice: the corpse record empties and the drop
## node leaves the tree.
##
## The channel is a body's work, so it breaks the moment the work stops being
## possible: a blow that puts the body down, a walk off the spot it started from,
## or `cancel()` from the world for the cases only it can see (a panel opening, a
## wipe). A cancelled channel takes nothing, and the corpse is untouched.
##
## A guest owns no loot: the host's world spawns the kills and books them, so a
## click on this machine is refused before a channel opens.

const SummaryScript = preload("res://scripts/warband/loot_summary.gd")

## How long the body works the ground before the pieces come up.
const CHANNEL_SECONDS := 0.9
## The gap after a sweep, so a held mouse button cannot open a second one on the
## frame the first closed.
const COOLDOWN_SECONDS := 0.25
## How far from the clicked drop a second drop is swept in: a pile of spoils off
## one kill is one take.
const PILE_RADIUS := 2.0
## Walking further than this from where the channel began breaks it.
const LEAVE_DISTANCE := 1.5
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

## What the channel is working, and where the body started from. Null actor means
## no channel is open; nothing else in this node is read while it is.
var _actor = null
var _kind := ""
var _corpse_id := 0
var _pickup: WarbandPickup = null
var _from := Vector3.ZERO
var _elapsed := 0.0
var _cool := 0.0
var _summary := ""


## Adopt the world's loot plumbing. Every part is optional: a world without a
## controller still loots, it just has no body to re-dress afterwards.
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


## The click. True when a channel began - the caller must let the click be a loot,
## not an attack. False means there is nothing lootable at `point` (or this
## machine does not own the loot), and the caller is free to swing.
func try_click(actor, point: Vector3) -> bool:
	if _loot == null or not is_instance_valid(_loot):
		return false
	if _is_client():
		return false
	if _cool > 0.0 or active():
		return false
	if not _can_work(actor):
		return false
	# The channel is the body's own work, so the piece has to be in the body's
	# reach as well as under the crosshair. Measuring only from `point` let a
	# click aimed at a fighter standing over a corpse loot that corpse from
	# across the field - the click crouched and worked the ground instead of
	# swinging, which is the report "I cannot attack any more".
	var body_at: Vector3 = (actor as Node3D).global_position
	var corpse_id: int = _loot.corpse_at(point, _reach)
	if corpse_id != 0 and body_at.distance_to(_loot.corpse_position(corpse_id)) <= _reach:
		_begin(actor, KIND_CORPSE, corpse_id, null)
		return true
	var pickup: WarbandPickup = _drop_at(point)
	if pickup != null and body_at.distance_to(pickup.global_position) <= _reach:
		_begin(actor, KIND_DROP, 0, pickup)
		return true
	return false


## Break the channel without taking anything. The world calls this for what only it
## can see - a panel going up, a wipe - and the body's own `downed_started` and
## `killed` signals call it when a blow ends the fight; `tick` catches the body
## that walked off the spot it started on.
func cancel() -> void:
	if not active():
		return
	_stand_up()
	_say_prompt("")
	_kind = ""
	_corpse_id = 0
	_pickup = null
	_actor = null
	_from = Vector3.ZERO
	_elapsed = 0.0


## Advance the channel by `delta` and run the cooldown. The world (or a test) owns
## the clock, so a paused tree never loots and a tick is worth exactly the time it
## is told.
func tick(delta: float) -> void:
	if _cool > 0.0:
		_cool = maxf(0.0, _cool - delta)
	if not active():
		return
	if not _still_working():
		cancel()
		return
	_elapsed += delta
	if _elapsed >= CHANNEL_SECONDS:
		_finish()


func active() -> bool:
	return _actor != null


## How far through the channel the body is, 0 to 1. Zero when nothing is running,
## so a prompt drawn from this never lies about a finished take.
func progress() -> float:
	if not active():
		return 0.0
	return clampf(_elapsed / CHANNEL_SECONDS, 0.0, 1.0)


## What is being worked: "corpse", "drop", or "" for nothing.
func target_kind() -> String:
	return _kind if active() else ""


## The line the last finished take raised, "" until one has finished.
func last_summary() -> String:
	return _summary


# --- internals -------------------------------------------------------------

func _begin(actor, kind: String, corpse_id: int, pickup) -> void:
	_actor = actor
	_kind = kind
	_corpse_id = corpse_id
	_pickup = pickup
	_from = (actor as Node3D).global_position
	_elapsed = 0.0
	_watch(actor)
	actor.set_crouch(true)
	_say_prompt("LOOTING...")


## The body's own word on the two things that end a channel before `tick` next
## runs: a blow that puts it down, and a blow that finishes it. The connections
## outlive the channel, so a body that loots twice is only ever wired once.
func _watch(actor) -> void:
	if actor.has_signal("downed_started") and not actor.downed_started.is_connected(_on_body_down):
		actor.downed_started.connect(_on_body_down)
	if actor.has_signal("killed") and not actor.killed.is_connected(_on_body_killed):
		actor.killed.connect(_on_body_killed)


func _on_body_down(_slot: int = 0) -> void:
	cancel()


func _on_body_killed(_slot: int = 0, _source: int = 0) -> void:
	cancel()


## The whole container, then the body straightens. A corpse is emptied through the
## vacuum's bulk take; a drop is taken with every other drop piled on it, so one
## click on the spoils of a kill gathers the pile instead of one piece of it.
func _finish() -> void:
	var ids: Array[String] = []
	if _kind == KIND_CORPSE:
		var taken: Dictionary = _loot.take_all_from_corpse(_corpse_id, LOCAL_PEER)
		for entry in taken.get("ids", []):
			ids.append(str(entry))
	elif _kind == KIND_DROP:
		ids = _take_drop_batch()
	_stand_up()
	_refresh_gear()
	_summary = SummaryScript.describe(ids)
	_say_prompt("")
	if _hud != null and is_instance_valid(_hud) and _hud.has_method("set_status"):
		_hud.set_status(_summary, SUMMARY_SECONDS)
	_kind = ""
	_corpse_id = 0
	_pickup = null
	_actor = null
	_from = Vector3.ZERO
	_elapsed = 0.0
	_cool = COOLDOWN_SECONDS


## Everything a body could believe is lootable at `point`: the nearest registered
## corpse still holding something, else the nearest open drop. A drop locked
## against this peer by its own dropper is not offered.
func _drop_at(point: Vector3) -> WarbandPickup:
	var best: WarbandPickup = null
	var best_distance := maxf(_reach, 0.0)
	for pickup in _loot.pickups():
		if not is_instance_valid(pickup) or pickup.collected:
			continue
		if pickup.blocked_for(LOCAL_PEER):
			continue
		var distance: float = pickup.global_position.distance_to(point)
		if distance <= best_distance:
			best_distance = distance
			best = pickup
	return best


## Take the clicked drop and everything piled with it. Each piece is booked by
## `quick_loot`, which also dresses the body that took it, so a looted blade lands
## in the hand it belongs in - there is no second hand-off here.
func _take_drop_batch() -> Array[String]:
	var ids: Array[String] = []
	if _pickup == null or not is_instance_valid(_pickup):
		return ids
	var centre: Vector3 = _pickup.global_position
	var batch: Array[WarbandPickup] = [_pickup]
	for pickup in _loot.pickups():
		if not is_instance_valid(pickup) or pickup.collected or batch.has(pickup):
			continue
		if pickup.global_position.distance_to(centre) <= PILE_RADIUS:
			batch.append(pickup)
	for pickup in batch:
		var result: Dictionary = _loot.quick_loot(pickup, LOCAL_PEER)
		if bool(result.get("ok", false)):
			ids.append(str(result.get("item_id", "")))
	return ids


## Whether the channel can still honestly be running: the body is up, alive, and
## standing where it started.
func _still_working() -> bool:
	if _actor == null or not is_instance_valid(_actor):
		return false
	if bool(_actor.get("downed")) or _actor.get("alive") == false:
		return false
	return (_actor as Node3D).global_position.distance_to(_from) <= LEAVE_DISTANCE


## A live warband body: one that can duck to work the ground. Anything without the
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


func _stand_up() -> void:
	if _actor != null and is_instance_valid(_actor) and _actor.has_method("set_crouch"):
		_actor.set_crouch(false)


## Re-dress the body that looted: a piece taken into an empty hand is on the rig
## only once the controller has re-read the roster.
func _refresh_gear() -> void:
	if _controller == null or not is_instance_valid(_controller):
		return
	if not _controller.has_method("refresh_gear"):
		return
	var merc_id := _merc_id()
	if merc_id > 0:
		_controller.refresh_gear(merc_id)


func _merc_id() -> int:
	if _controller == null or not is_instance_valid(_controller):
		return -1
	if _controller.has_method("merc_for_peer"):
		var answer: Variant = _controller.merc_for_peer(LOCAL_PEER)
		if typeof(answer) == TYPE_INT:
			return int(answer)
	if _actor != null and _controller.has_method("merc_of"):
		var other: Variant = _controller.merc_of(_actor)
		if typeof(other) == TYPE_INT:
			return int(other)
	return -1


func _say_prompt(text: String) -> void:
	if _hud != null and is_instance_valid(_hud) and _hud.has_method("set_prompt"):
		_hud.set_prompt(text)


## A guest's world is the host's: its corpses and drops were booked on the other
## machine, so a click here must fall through to an ordinary swing.
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
