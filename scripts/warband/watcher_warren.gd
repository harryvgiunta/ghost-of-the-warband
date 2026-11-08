class_name WatcherWarren
extends Node3D
## The hollow watchers' camps in the wood past the town's wall: the hunting ground
## the quartermaster's second order is counted on.
##
## The road's cult holds the lane, the camp's watchers hold the opening, and
## neither is a place the warband goes to on purpose. The warren is: seven camps
## standing off the way, each a fireless patch of totems and skull stakes - a
## hunting ground a squad can walk to all the way up the road, from the dark end
## where the demon stands (lane fraction 0.06) to the last bend before the town's
## gate (0.90). Every camp stands 78-96 m out from the lane, past twice a
## warden's 30 m sight, so a body walking the road is never pulled into a fight it
## did not go looking for, and clear of the square's wall by a wall and a half.
## What makes them findable is the map's markers and the dressing itself: a place a
## body can see from the lane and walk to.
##
## **One body a camp, and the first three are runts.** A camp of three wardens is
## not a hunting ground a band with a club walks out of, and a squad that has just
## picked its first weapon off a corpse has nowhere else to go: the road's cult
## fights in pairs and the wolves in packs. So every camp fields a single watcher -
## one body, one duel - and the three camps nearest the town (fractions 0.62, 0.76,
## 0.90, the end a warband reaches first) field the wood's older children, the
## `hollow_runt`: the warden's shape at 0.58-0.70 of its height with a third of a
## hard body's pool and a third of its blow (`cage_watcher.RUNT_SHARE`). Its corpse
## still carries a rag, so the runts are how a band arms itself: three bodies a
## camp, a three-minute clock each, and a kit that arrives one piece at a time.
## The four deeper camps are the same duel against a full warden - the next step a
## grind is supposed to have.
##
## A camp is a real camp because the dressing is real: `VillageKit` totems and
## skull stakes on their own collision, so the place reads as somewhere people
## live before the first body turns. The watchers are the wood's own creature
## (`cage_watcher.gd`: `hollow_warden` or `hollow_runt`, the makeshift tier in its
## hand, the shared mob state machine), appended to `host.guards` - the world's one
## hostile list - and wired to the world's one kill handler, so a corpse here pays
## exactly as a road cultist's does.
##
## A camp that is cut down comes back. The clock is one per camp, never one per
## warden: the camp's first death arms it, and when `RESPAWN_SECONDS` have run,
## every warden of that camp which is not still on its feet is put back on its own
## post - a wipe of one camp refills that camp and leaves the other six exactly as
## they stood. A refill waits while any party body stands within `RESPAWN_QUIET`
## metres of the camp's posts, so a squad never has bodies appear inside its own
## sight, and the wood refills behind a party that has left. A warden that
## survived the clock is left exactly where it stands - a fight is never teleported
## - and a camp with nothing dead has no clock, so nothing can spawn twice. A body
## that comes back is asleep on its post exactly like a fresh one: it wakes when a
## party comes near.
##
## The warren owns only what is different from the rest of the frontier: the
## posts, its dressing, the 0.5 s refill/aim tick (the warband changes what it is
## driving, and a body seated later must be huntable) and the one shared territory
## per camp.

const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const VillageKit = preload("res://scripts/world/village_kit.gd")
const MobWander = preload("res://scripts/mob_wander.gd")
const TerrainScript = preload("res://scripts/warband/terrain.gd")
const Perf = preload("res://scripts/perf_probe.gd")

## Seven camps, each a lane fraction and a side, spread the whole walk: the first
## on the dark end where the demon stands, the last on the bend before the town's
## gate. The offsets are deep wood, 78-96 m out. They used to stand 18-40 m off the
## lane, which is inside a warden's sight: seven bodies a camp came off their marks
## the moment the squad walked past and met it in the middle of the road. A hunting
## ground the road cannot see is the only hunting ground a warband can choose to
## walk into. The fractions sit between the wolf packs' own
## (`wilderness.gd`), so the road is never two fights at once by accident.
##
## `species` is the body the camp fields and `members` how many of it stand there.
## One each: a camp is a duel, and the ladder runs the way a warband walks it -
## the runts on the town end (0.62, 0.76, 0.90), where the first party out of the
## gate meets them, and a full warden in the four camps deeper in.
const CAMPS := [
	{"fraction": 0.06, "side": 1.0, "offset": 78.0, "yaw": 0.4, "seed": 611,
		"species": "hollow_warden", "members": 1},
	{"fraction": 0.20, "side": -1.0, "offset": 96.0, "yaw": 2.1, "seed": 617,
		"species": "hollow_warden", "members": 1},
	{"fraction": 0.34, "side": 1.0, "offset": 86.0, "yaw": 4.6, "seed": 623,
		"species": "hollow_warden", "members": 1},
	{"fraction": 0.48, "side": -1.0, "offset": 92.0, "yaw": 1.2, "seed": 631,
		"species": "hollow_warden", "members": 1},
	{"fraction": 0.62, "side": 1.0, "offset": 80.0, "yaw": 3.3, "seed": 641,
		"species": "hollow_runt", "members": 1},
	{"fraction": 0.76, "side": -1.0, "offset": 88.0, "yaw": 5.2, "seed": 643,
		"species": "hollow_runt", "members": 1},
	{"fraction": 0.90, "side": 1.0, "offset": 94.0, "yaw": 2.7, "seed": 647,
		"species": "hollow_runt", "members": 1},
]
## What a camp fields when its row names no species: the species the camp's gate
## is made of.
const CAMP_SPECIES := "hollow_warden"
## How many bodies a camp fields when its row names no count. One: every camp in
## the table is a single body, and a row that asks for a squad has to say so.
const CAMP_MEMBERS := 1
## The name a camp's bodies are numbered under. A guest builds the same camps, and
## the session finds its bodies by name - so the name is a function of the table
## row (species and camp number), never of spawn order.
const NAME_PREFIX := {
	"hollow_warden": "HollowWarden",
	"hollow_runt": "HollowRunt",
	"ossuary_stalker": "HollowStalker",
	"gallowsroot": "HollowRoot",
}
## Members stand on this ring around the camp's dressing: inside the totem's
## reach and clear of its collider.
const RING_INNER := 3.4
const RING_STEP := 1.3
## The makeshift tier in their hands, by camp and by body, so no two camps are the
## same fight.
const ARMS := ["club_makeshift", "dagger_ironwood", "branch_heavy", "dagger_ironwood"]
## What a runt can lift is the species' own rule (`cage_watcher.RUNT_ARMS`): the
## short pieces only.
## The same 12 cm every body in this world is spawned clear of its ground by.
const SPAWN_LIFT := 0.12
## The warband can seat, down or hand over a body at any moment; half a second is
## fast enough that a warden never hunts a body that has left, and cheap enough
## that the wood's hosts do not notice the tick.
const REFRESH_SECONDS := 0.5
## How long a cut camp stays cut. A party that farms the wood meets the camps
## again instead of emptying them once and walking a dead wood forever.
const RESPAWN_SECONDS := 180.0
## A refill holds while any party body stands this close to the camp's posts: a
## squad must never have bodies appear inside its own sight, and a warden's sight
## is 30 m, so this is the whole of a camp's reach of the road.
const RESPAWN_QUIET := 45.0
## `main.gd`'s pack radius. A camp's bodies stand inside it of one another, so
## `assign_all` hands that camp one territory to roam.
const PACK_RADIUS := 14.0
## How far from its own camp a warden will take a target: past this it is a body in
## a place, not a patrol, and the road belongs to whoever walks it.
const LEASH_METRES := 55.0

## The world this warren is built into.
var host: Node3D = null

## One entry per camp, in `CAMPS` order:
## `{node, centre, mobs, posts, respawn_at}`.
var _camps: Array[Dictionary] = []
## Every warden this node fielded, in spawn order.
var _mobs: Array = []
var _elapsed := 0.0
## Seconds this node has run: the refill clocks are absolute on it, so a clock
## survives a frame budget hitch the way a wall clock does.
var _clock := 0.0


## Build the camps into `world`. The node parents itself under the world if the
## caller has not done it yet: the bodies have to be in the tree for their global
## positions, their pack and their tick.
##
## A co-op guest builds the same camps: the warren's names are derived from the
## camp table, never from spawn order, so the host's name-keyed snapshots find
## exactly these bodies. The session marks each warden a replica before its first
## state arrives, so nothing here runs a brain on the guest's machine - but the
## camps, their dressing and the bodies a soul can see are the wood's, and a guest
## standing in an empty camp the host is fighting in was the visible half of the
## same bug. A guest never refills a camp of its own: the bodies it draws are the
## host's.
func setup(world: Node3D) -> void:
	if not is_instance_valid(world):
		push_error("WatcherWarren.setup() needs the world")
		return
	host = world
	_elapsed = 0.0
	_clock = 0.0
	if not is_inside_tree() and world.is_inside_tree():
		world.add_child(self)
	_clear()
	_build()


func _process(delta: float) -> void:
	Perf.begin("warren.tick")
	_clock += delta
	_tick_refresh(delta)
	Perf.end()


func _tick_refresh(delta: float) -> void:
	if _mobs.is_empty():
		return
	_elapsed += delta
	if _elapsed < REFRESH_SECONDS:
		return
	_elapsed = fmod(_elapsed, REFRESH_SECONDS)
	_refill()
	_refresh()


# --- reading ---------------------------------------------------------------

## The camps, in camp order: `{node, centre, mobs, posts, respawn_at}`.
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
## Summed off the rows, so a camp that grows or shrinks is counted by the same
## number the build walked.
func total() -> int:
	var count := 0
	for spec in CAMPS:
		count += int(spec.get("members", CAMP_MEMBERS))
	return count


## Seconds left on camp `index`'s refill clock, or -1.0 while that camp has
## nothing dead. The camps refill on their own; this is what the regression and
## the map read.
func refill_in(index: int) -> float:
	if index < 0 or index >= _camps.size():
		return -1.0
	var at := float(_camps[index].get("respawn_at", -1.0))
	return -1.0 if at < 0.0 else maxf(at - _clock, 0.0)


## Put camp `index`'s fallen back on their posts now, on the same path the clock
## takes, and return how many wardens came back. The three minutes are the clock's
## business; a scripted encounter may refill a camp by hand.
func refill_camp(index: int) -> int:
	if index < 0 or index >= _camps.size():
		return 0
	return _refill_one(index)


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
		var species := str(spec.get("species", CAMP_SPECIES))
		var size := maxi(1, int(spec.get("members", CAMP_MEMBERS)))
		var members: Array = []
		var posts: Array[Vector3] = []
		for member in size:
			var point := _post(at, index, member, size, int(spec["seed"]))
			posts.append(point)
			members.append(_spawn_watcher(index, member, point, species))
		# One patch of wood per camp: the bodies spawned inside `PACK_RADIUS` of one
		# another, so `assign_all` hands the camp one shared territory instead of
		# one private patch a body.
		MobWander.assign_all(members, PACK_RADIUS)
		_camps.append({
			"node": camp, "centre": at, "mobs": members, "posts": posts,
			"respawn_at": -1.0,
		})
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


## One watcher: the wood's own creature, armed off the makeshift tier, standing on
## `point`, aimed at whichever body is nearest right now, and booked into the
## world's hostile list and its one kill handler.
##
## `species` is the camp row's own: a warden is a full body and a runt is the
## wood's small one, with its pool from the species' own table
## (`cage_watcher.gd::_ready`) and only the pieces it can lift in its hands.
func _spawn_watcher(camp_index: int, member: int, point: Vector3, species: String) -> Node:
	var watcher := WatcherScript.new()
	watcher.name = "%s%d_%d" % [str(NAME_PREFIX.get(species, NAME_PREFIX[CAMP_SPECIES])),
		camp_index + 1, member + 1]
	# Named before the tree sees it: `cage_watcher.gd::_init` sets the warden id,
	# and `_ready` keeps whatever name the scene gave it.
	watcher.mob_id = species
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
	watcher.arm(_arm_for(camp_index, member, species))
	var guards = host.get("guards")
	if guards is Array:
		(guards as Array).append(watcher)
	return watcher


## The piece a body is given: a runt takes the short tier, a full body the whole
## of it, and the ordinal in the camp decides which - so two camps never stand the
## same fight and a refill gives the camp's own body the same arm it had.
func _arm_for(camp_index: int, member: int, species: String) -> String:
	var table: Array = WatcherScript.RUNT_ARMS if species == WatcherScript.RUNT_ID else ARMS
	return str(table[(camp_index + member) % table.size()])


## A body's post: on a loose ring around the camp's dressing, on the ground. `size`
## is the camp's own count, so a lone body and a packed one both land on the ring
## rather than all but the first standing on the same angle.
func _post(centre: Vector3, camp_index: int, member: int, size: int, seed: int) -> Vector3:
	var angle := TAU * float(member) / float(maxi(1, size)) + float(seed % 7) * 0.37 \
		+ float(camp_index) * 0.21
	var radius := RING_INNER + float(member % 3) * RING_STEP
	var at := centre + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	return TerrainScript.grounded(Vector3(at.x, 0.0, at.z)) + Vector3(0.0, SPAWN_LIFT, 0.0)


# --- the refill -------------------------------------------------------------

## One refill clock per camp, never one per warden. A camp with nothing dead has no
## clock; a camp whose first body fell gets one `RESPAWN_SECONDS` out, and the
## clock is read here on the 0.5 s tick with the aim.
func _refill() -> void:
	for index in _camps.size():
		var camp: Dictionary = _camps[index]
		var lost := 0
		for mob in camp["mobs"] as Array:
			if not is_instance_valid(mob) or not bool(mob.get("alive")):
				lost += 1
		if lost == 0:
			camp["respawn_at"] = -1.0
			continue
		var at := float(camp["respawn_at"])
		if at < 0.0:
			camp["respawn_at"] = _clock + RESPAWN_SECONDS
			continue
		if _clock < at:
			continue
		_refill_one(index)


## The camp's fallen back on their own posts - and no one else's. A warden still on
## its feet is left exactly where it is: a refill is never a teleport and never a
## second body. A body that comes back is booked into the world's one hostile list
## and into its camp's own territory.
func _refill_one(index: int) -> int:
	# The guest fielded the same camps, but the bodies it draws are the host's: a
	# second warden spawned here would be a warden the host never spawned.
	if _is_client():
		return 0
	var camp: Dictionary = _camps[index]
	var posts: Array = camp["posts"]
	for post in posts:
		if _body_within(post as Vector3, RESPAWN_QUIET):
			return 0
	var members: Array = camp["mobs"]
	var species := str(CAMPS[index].get("species", CAMP_SPECIES)) if index < CAMPS.size() \
		else CAMP_SPECIES
	var fresh: Array = []
	for member in members.size():
		var old = members[member]
		if is_instance_valid(old) and bool(old.get("alive")):
			continue
		if is_instance_valid(old):
			_retire(old)
		var watcher := _spawn_watcher(index, member, posts[member] as Vector3, species)
		members[member] = watcher
		fresh.append(watcher)
	if fresh.is_empty():
		camp["respawn_at"] = -1.0
		return 0
	_join_territory(members, fresh)
	camp["respawn_at"] = -1.0
	_sync_mobs()
	return fresh.size()


## The patch a body that came back belongs to: its campmates' own territory while
## any of them is still walking it, and a freshly handed one when the camp was cut
## down to its last body.
func _join_territory(members: Array, fresh: Array) -> void:
	var shared: MobWander = null
	var pack_group := ""
	for mob in members:
		if fresh.has(mob) or not is_instance_valid(mob):
			continue
		var wander: MobWander = mob.get("_wander")
		if wander == null or wander.territory == null:
			continue
		shared = wander
		pack_group = wander.group
		break
	if shared == null:
		MobWander.assign_all(fresh, PACK_RADIUS)
		return
	for mob in fresh:
		mob.assign_territory(shared.territory, members.find(mob), pack_group)
		if not pack_group.is_empty():
			(mob as Node).add_to_group(pack_group)


## Make room for a replacement. `queue_free` leaves the corpse in the tree for the
## rest of the frame, and the newcomer takes its predecessor's name - so the corpse
## steps aside first, and off the world's hostile list, which the replacement
## rejoins under that name.
func _retire(corpse: Node) -> void:
	var guards = host.get("guards") if is_instance_valid(host) else null
	if guards is Array:
		(guards as Array).erase(corpse)
	corpse.name = "%sCorpse" % corpse.name
	corpse.queue_free()


## True while any party body - standing or down - is inside `metres` of `point`.
func _body_within(point: Vector3, metres: float) -> bool:
	var bodies = host.get("bodies") if is_instance_valid(host) else null
	if not (bodies is Array):
		return false
	var reach := metres * metres
	for body in bodies as Array:
		if not is_instance_valid(body) or not body is Node3D:
			continue
		if (body as Node3D).global_position.distance_squared_to(point) <= reach:
			return true
	return false


func _is_client() -> bool:
	if not is_instance_valid(host):
		return false
	var client = host.get("_client")
	return client is bool and bool(client)


func _sync_mobs() -> void:
	_mobs.clear()
	for camp in _camps:
		_mobs.append_array(camp["mobs"] as Array)


# --- the aim ---------------------------------------------------------------

## Put the camps' aim back on the bodies that are standing right now - but only
## while they are the camp's own quarry.
##
## A warcamp is a place the warband goes to, not a patrol of the road: handed the
## nearest body unconditionally, every warden of the seven camps leaves its patch
## and walks the kilometre and a third of lane behind a squad that never turned off
## it, which peels the escort off one fight at a time and is not what an order about
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
