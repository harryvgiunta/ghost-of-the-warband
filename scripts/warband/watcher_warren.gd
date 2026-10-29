class_name WatcherWarren
extends Node3D
## The hollow watchers' camps in the wood past the town's wall: the hunting ground
## the quartermaster's second order is counted on.
##
## The road's cult holds the lane, the camp's watchers hold the opening, and
## neither is a place the warband goes to on purpose. The warren is: three camps
## of wardens standing off the way, each a fireless patch of totems and skull
## stakes with seven antlered bodies in it, 78-96 m out from the lane - past
## twice a warden's 60 m sight, so a body walking the road is never pulled into a
## fight it did not go looking for - and clear of the square's wall by a wall and
## a half. What makes them findable is the map's markers and the dressing itself:
## a place a body can see from the lane and walk to.
##
## A camp is a real camp because the dressing is real: `VillageKit` totems and
## skull stakes on their own collision, so the place reads as somewhere people
## live before the first body turns. The watchers are the wood's own creature
## (`cage_watcher.gd`: `hollow_warden`, the makeshift tier in its hand, the shared
## mob state machine), appended to `host.guards` - the world's one hostile list -
## and wired to the world's one kill handler, so a corpse here pays the bounty
## through `host.note_kill` exactly as a road cultist's does.
##
## The warren owns only what is different from the rest of the frontier: the
## posts, its dressing, the 0.5 s aim refresh (the warband changes what it is
## driving, and a body seated later must be huntable) and the one shared territory
## per camp.

const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const VillageKit = preload("res://scripts/world/village_kit.gd")
const MobWander = preload("res://scripts/mob_wander.gd")
const TerrainScript = preload("res://scripts/warband/terrain.gd")

## Three camps, each a lane fraction and a side. The fractions are the last third
## of the walk, so a warband on its way to town passes all three before the gate;
## the offsets are deep wood, 78-96 m out. They used to stand 18-40 m off the
## lane, which is inside a warden's sight: seven bodies a camp came off their
## marks the moment the squad walked past and met it in the middle of the road.
## A hunting ground the road cannot see is the only hunting ground a warband can
## choose to walk into.
const CAMPS := [
	{"fraction": 0.72, "side": 1.0, "offset": 78.0, "yaw": 0.4, "seed": 611},
	{"fraction": 0.80, "side": -1.0, "offset": 96.0, "yaw": 2.1, "seed": 617},
	{"fraction": 0.90, "side": 1.0, "offset": 86.0, "yaw": 4.6, "seed": 619},
]
## Seven watchers a camp. Three camps of seven is one order's worth of bodies and
## then some: twenty is the quartermaster's count, and a hunting ground that
## exactly met it would leave a squad that lost one kill short with nowhere to go.
const CAMP_SIZE := 7
## Every body the camps field: three camps of seven, by the table above.
const TOTAL := 21
## Members stand on this ring around the camp's dressing: inside the totem's
## reach and clear of its collider.
const RING_INNER := 3.4
const RING_STEP := 1.3
## The makeshift tier in their hands, by camp and by body, so a camp is not seven
## copies of one warden.
const ARMS := ["club_makeshift", "dagger_ironwood", "branch_heavy", "dagger_ironwood"]
## The same 12 cm every body in this world is spawned clear of its ground by.
const SPAWN_LIFT := 0.12
## The warband can seat, down or hand over a body at any moment; half a second is
## fast enough that a warden never hunts a body that has left, and cheap enough
## that the wood's hosts do not notice it.
const REFRESH_SECONDS := 0.5
## `main.gd`'s pack radius. Each camp's seven stand inside it of one another, so
## `assign_all` hands that camp one territory to roam.
const PACK_RADIUS := 14.0
## How far from its own camp a warden will take a target: past this it is a body in
## a place, not a patrol, and the road belongs to whoever walks it.
const LEASH_METRES := 55.0

## The world this warren is built into.
var host: Node3D = null

## One entry per camp, in `CAMPS` order: `{node, centre, mobs}`.
var _camps: Array[Dictionary] = []
## Every warden this node fielded, in spawn order.
var _mobs: Array = []
var _elapsed := 0.0


## Build the three camps into `world`. The node parents itself under the world if
## the caller has not done it yet: the bodies have to be in the tree for their
## global positions, their pack and their tick.
##
## A co-op guest builds nothing. The wood is the host's: a guest that spawned its
## own three camps would stand twenty-one wardens beside the twenty-one replicas
## the session already streams it, and a second mob on the same ground is a fight
## with itself.
func setup(world: Node3D) -> void:
	if not is_instance_valid(world):
		push_error("WatcherWarren.setup() needs the world")
		return
	host = world
	_elapsed = 0.0
	if not is_inside_tree() and world.is_inside_tree():
		world.add_child(self)
	_clear()
	if _is_guest():
		return
	_build()


func _process(delta: float) -> void:
	if _mobs.is_empty():
		return
	_elapsed += delta
	if _elapsed < REFRESH_SECONDS:
		return
	_elapsed = fmod(_elapsed, REFRESH_SECONDS)
	_refresh()


# --- reading ---------------------------------------------------------------

## The three camps, in camp order: `{node, centre, mobs}`.
func camps() -> Array:
	return _camps.duplicate()


## Every warden this node fielded, whether it still stands or not.
func mobs() -> Array:
	return _mobs.duplicate()


## Wardens still on their feet.
func living() -> int:
	var count := 0
	for mob in _mobs:
		if is_instance_valid(mob) and bool(mob.get("alive")):
			count += 1
	return count


## Where each camp stands, for the map: the dressing's own ground.
func camp_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for camp in _camps:
		out.append(camp["centre"])
	return out


## The camp table's count, not the living one: what the warren was built to hold.
func total() -> int:
	return TOTAL


# --- the build -------------------------------------------------------------

func _build() -> void:
	var path = _path()
	if path == null:
		push_error("WatcherWarren: the world has no lane to stand the camps off")
		return
	var mats: Dictionary = VillageKit.materials()
	for index in CAMPS.size():
		var spec: Dictionary = CAMPS[index]
		var frame: Dictionary = path.sample(path.total * float(spec["fraction"]))
		var right: Vector3 = frame["right"]
		var side := float(spec["side"])
		var at: Vector3 = (frame["position"] as Vector3) + right * side * float(spec["offset"])
		at = TerrainScript.grounded(Vector3(at.x, 0.0, at.z))
		var camp := _build_camp(index, at, float(spec["yaw"]), mats)
		var members: Array = []
		for member in CAMP_SIZE:
			members.append(_spawn_watcher(index, member, at, int(spec["seed"])))
		# One patch of wood per camp: the seven spawned inside `PACK_RADIUS` of one
		# another, so `assign_all` hands the camp one shared territory instead of
		# seven private ones.
		MobWander.assign_all(members, PACK_RADIUS)
		_camps.append({"node": camp, "centre": at, "mobs": members})
		_mobs.append_array(members)
	_refresh()


## One camp's dressing and its collision: a warden totem and a row of skull
## stakes, with a bone heap between them, authored in the camp's own frame so a
## moved camp takes its furniture with it.
func _build_camp(index: int, at: Vector3, yaw: float, mats: Dictionary) -> Node3D:
	var camp := Node3D.new()
	camp.name = "Warcamp%d" % (index + 1)
	camp.position = at
	camp.rotation.y = yaw
	add_child(camp)
	var solids := StaticBody3D.new()
	solids.name = "CampSolids"
	solids.collision_layer = 1
	solids.collision_mask = 0
	camp.add_child(solids)
	# The totem is the camp's one solid piece. `VillageKit` places it from the
	# host's own transform, so it stands in the camp node's frame and its collider
	# follows the same numbers.
	var pole := Node3D.new()
	pole.name = "WardenTotem"
	pole.position = Vector3(2.0, 0.0, 1.4)
	camp.add_child(pole)
	VillageKit.totem(pole, mats, solids, 4.2, 600 + index * 7)
	# Stakes and a heap are one batch: the clutter of a place somebody has been
	# living in, at the price of one draw call and no collider.
	var clutter := VillageKit.Merged.new()
	VillageKit.skull_stakes(clutter, mats, Vector3(-2.6, 0.0, 1.2), 0.0, 4, 0.85,
		610 + index * 5)
	VillageKit.bone_heap(clutter, mats, Vector3(0.6, 0.0, -2.6), 1.3, 620 + index * 3)
	clutter.commit(camp, "WarcampDressing")
	return camp


## One warden: the wood's own creature, armed off the makeshift tier, aimed at
## whichever body is nearest right now, and booked into the world's hostile list
## and its one kill handler.
func _spawn_watcher(camp_index: int, member: int, centre: Vector3, seed: int) -> Node:
	var watcher := WatcherScript.new()
	watcher.name = "HollowWarden%d_%d" % [camp_index + 1, member + 1]
	# Named before the tree sees it: `cage_watcher.gd::_init` sets the warden id,
	# and `_ready` keeps whatever name the scene gave it.
	watcher.mob_id = WatcherScript.WARDEN_ID
	var point := _post(centre, camp_index, member, seed)
	watcher.position = point
	add_child(watcher)
	# `_ready` read the local transform; a container with its own transform must
	# still leave the body standing on the world point, with that point as home.
	watcher.global_position = point
	watcher.home = point
	# The town's own ring is the one piece of ground nobody hunts on, exactly as it
	# is for the camp's watchers and the road's cult.
	watcher.safe_center = _safe_center()
	watcher.player = _nearest(point)
	watcher.targets = _standing_bodies()
	if host.has_method("_on_enemy_defeated"):
		watcher.defeated.connect(Callable(host, "_on_enemy_defeated"))
	elif _mobs.is_empty():
		push_warning("WatcherWarren: the world has no _on_enemy_defeated; kills go uncounted")
	if host.has_method("_on_enemy_attack"):
		watcher.attacked.connect(Callable(host, "_on_enemy_attack"))
	elif _mobs.is_empty():
		push_warning("WatcherWarren: the world has no _on_enemy_attack; blows land nowhere")
	watcher.arm(str(ARMS[(camp_index + member) % ARMS.size()]))
	var guards = host.get("guards")
	if guards is Array:
		(guards as Array).append(watcher)
	return watcher


## A body's post: on a loose ring around the camp's dressing, on the ground.
func _post(centre: Vector3, camp_index: int, member: int, seed: int) -> Vector3:
	var angle := TAU * float(member) / float(CAMP_SIZE) + float(seed % 7) * 0.37 \
		+ float(camp_index) * 0.21
	var radius := RING_INNER + float(member % 3) * RING_STEP
	var at := centre + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	return TerrainScript.grounded(Vector3(at.x, 0.0, at.z)) + Vector3(0.0, SPAWN_LIFT, 0.0)


# --- the aim ---------------------------------------------------------------

## Put the camps' aim back on the bodies that are standing right now - but only
## while they are the camp's own quarry.
##
## A warcamp is a place the warband goes to, not a patrol of the road: handed the
## nearest body unconditionally, twenty-one wardens leave their patches and walk
## the kilometre and a third of lane behind a squad that never turned off it,
## which peels the escort off one fight at a time and is not what an order about
## hunting grounds means. Past `LEASH_METRES` from its own camp a warden is given
## nothing, and its pack's `MobWander` territory keeps it at home; walk within the
## leash and the camp wakes as one.
func _refresh() -> void:
	if not is_instance_valid(host):
		return
	var standing := _standing_bodies()
	for watcher in _mobs:
		if not is_instance_valid(watcher) or not bool(watcher.get("alive")):
			continue
		var home: Vector3 = _home_of(watcher)
		var prey = _nearest(watcher.global_position)
		if prey == null or (prey as Node3D).global_position.distance_to(home) > LEASH_METRES:
			watcher.player = null
			# `targets` is a typed `Array[CharacterBody3D]`: an untyped empty array is
			# a refused assignment, and a refused one leaves the old quarry standing.
			var none: Array[CharacterBody3D] = []
			watcher.targets = none
			continue
		watcher.player = prey
		watcher.targets = standing


## The camp a body belongs to: the post it was spawned on, read back off the group
## it was named for. A warden carries no camp reference of its own.
func _home_of(watcher) -> Vector3:
	var nearest := (watcher as Node3D).global_position
	var best := INF
	for camp in _camps:
		var centre: Vector3 = camp.get("centre", Vector3.ZERO)
		var distance: float = (watcher as Node3D).global_position.distance_to(centre)
		if distance < best:
			best = distance
			nearest = centre
	return nearest


func _standing_bodies() -> Array[CharacterBody3D]:
	var standing: Array[CharacterBody3D] = []
	var bodies = host.get("bodies")
	if not (bodies is Array):
		return standing
	for body in bodies:
		if not is_instance_valid(body):
			continue
		if not bool(body.get("alive")) or bool(body.get("downed")):
			continue
		standing.append(body)
	return standing


func _nearest(point: Vector3):
	if host != null and host.has_method("nearest_standing_body"):
		return host.nearest_standing_body(point)
	var best = null
	var best_distance := INF
	for body in _standing_bodies():
		var distance := (body as Node3D).global_position.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = body
	return best


## The ring the camp's own mobs use: the town's end of the trail.
func _safe_center() -> Vector3:
	if host != null and host.has_method("lane_end"):
		return host.lane_end()
	return Vector3(0.0, 0.0, -100000.0)


# --- the world -------------------------------------------------------------

func _path():
	if host == null:
		return null
	var trail = host.get("trail")
	if trail == null:
		return null
	var forest = trail.get("forest")
	if not (forest is Dictionary):
		return null
	return (forest as Dictionary).get("path")


func _is_guest() -> bool:
	return host != null and bool(host.get("_client"))


## A second setup replaces the camps rather than stacking two on the same ground.
func _clear() -> void:
	var guards = host.get("guards") if host != null else null
	for watcher in _mobs:
		if not is_instance_valid(watcher):
			continue
		if guards is Array:
			(guards as Array).erase(watcher)
		(watcher as Node).queue_free()
	_mobs.clear()
	for camp in _camps:
		var node = camp.get("node")
		if is_instance_valid(node):
			(node as Node).queue_free()
	_camps.clear()
