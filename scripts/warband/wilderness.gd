class_name WarbandWilderness
extends Node
## The briar wolves of the way out: six small packs holding the road from the
## camp's mouth to within a couple of hundred metres of the town gate.
##
## The road is the only place in the campaign where a body can learn to fight
## without a tutorial card in the way, and a road that is empty is a walk while a
## road held by two great packs is a wall. The band is therefore a grind: the
## corridor pack of two beside the way out at 62-72 m, then five packs of three, a
## pack every ~190 m of lane, each standing 19-26 m off the centre line - outside
## the trunk rows a body can walk into, outside the walked band, and inside the
## reach of a squad that steps off the road to meet it. Their posts are derived,
## never rolled - the lane's own polyline for the lane packs, the corridor's
## straight cut for the first - so two visits meet the same packs standing in the
## same places, and no wolf is ever inside the camp pocket, the town square, or a
## warden camp's patch.
##
## "Level 1" is not a stat the mobs carry: `enemy.gd` has one authored wolf, kind
## 0 at 38 health, and that base body is what a first road should hold. The band
## is spawned unbuffed, aimed at the warband's own bodies and wired to the world's
## one kill/attack handler, exactly like the camp's watchers.
##
## A pack that is cut down comes back. The clock is one per pack, never one per
## wolf: the pack's first death arms it, and when `RESPAWN_SECONDS` have run every
## wolf of that pack which is not still on its feet is put back on its own post.
## A refill waits while any party body stands within `RESPAWN_QUIET` metres of the
## pack's posts, so a squad walking the road never has bodies appear inside its own
## sight, and the wood refills behind a party that has moved on. A wolf that
## survived the clock is left exactly where it stands - a fight is never teleported
## - and a pack with nothing dead has no clock, so nothing can spawn twice. A body
## that comes back is asleep on its post exactly like a fresh one: it wakes when a
## party comes near.
##
## The wilderness owns only what is different from the rest of the frontier: the
## posts, the 0.5 s refill/aim tick (the warband changes what it is driving, and a
## body seated later must be huntable) and the `MobCuller` that keeps a wolf the
## squad has walked past from costing a tick behind the fog.

const EnemyScript = preload("res://scripts/enemy.gd")
const MobCullerScript = preload("res://scripts/mob_culler.gd")
const MobWander = preload("res://scripts/mob_wander.gd")
const TerrainScript = preload("res://scripts/warband/terrain.gd")
const WoodScript = preload("res://scripts/warband/wood_boss.gd")
const RunForestScript = preload("res://scripts/warband/run_forest.gd")
const Perf = preload("res://scripts/perf_probe.gd")

## Cleared ground: a wolf closer than this to the camp's mouth would be standing
## on the pocket's own edge, and the opening fight belongs to the camp's watchers.
const MOUTH_CLEARANCE := 25.0
## Where the band stands, pack by pack. A `corridor` pack is posted `along` metres
## from the camp's mouth and `side` metres off the corridor's straight line; a lane
## pack is posted by `fraction` of the lane's measured length - 0.0 the first
## waypoint past the corridor, 1.0 the town gate - and metres off the centre line.
## The fractions sit between the warcamps' own (`watcher_warren.gd`), so a squad
## standing on the lane at a camp never has a wolf pack in reach at the same time.
const PACKS := [
	# The first pack is off the corridor beside the trail-start checkpoint, deep
	# enough that a body on the road never sees it (38-45 m out), near enough that
	# a squad that leaves the path finds it - and that a co-op guest at the
	# checkpoint has one in its 70 m replication band.
	{"name": "BriarPackA", "corridor": true, "stations": [[62.0, -38.0], [72.0, -45.0]]},
	{"name": "BriarPackB", "stations": [[0.130, 19.0], [0.134, 26.0], [0.140, 21.0]]},
	{"name": "BriarPackC", "stations": [[0.270, -22.0], [0.274, -27.0], [0.280, -20.0]]},
	{"name": "BriarPackD", "stations": [[0.410, 20.0], [0.414, 26.0], [0.420, 22.0]]},
	{"name": "BriarPackE", "stations": [[0.550, -21.0], [0.554, -26.0], [0.560, -19.0]]},
	{"name": "BriarPackF", "stations": [[0.690, 22.0], [0.694, 26.0], [0.700, 20.0]]},
]
## Every wolf the band fields: the corridor pack's two and five lane packs of
## three, by the table above. The tests that count the whole band read it.
const PACK_COUNT := 17
## The nearest a lane pack stands to the centre line. The two solid rows of trunk
## reach ~11 m into the wood with their jitter, `RunForestScript.CLEAR_HALF`
## (1.55 m) is the walked band, and this is the floor under both: no wolf spawns
## in a body's way or inside a collider.
const LANE_LATERAL_MIN := 15.0
## The same 12 cm the frontier lifts every mob spawn by, so a body dropped on the
## analytic ground starts just clear of it instead of inside the collider.
const SPAWN_LIFT := 0.12
## The warband can seat, down or hand over a body at any moment; half a second is
## fast enough that a wolf never hunts a body that has left, and cheap enough that
## the frontier's hosts do not notice the tick.
const REFRESH_SECONDS := 0.5
## How long a cut pack stays cut. A party that farms the wood meets the same packs
## again instead of emptying the road once and walking it empty forever.
const RESPAWN_SECONDS := 180.0
## A refill holds while any party body stands this close to the pack's posts: a
## squad on the road must never have bodies appear inside its own sight, and a
## wolf's sight is 23 m, so this is the whole of the road plus the verge.
const RESPAWN_QUIET := 45.0
## `main.gd`'s pack radius for every wilderness band. A pack's posts sit inside it
## of one another and the packs are hundreds of metres apart, so `assign_all`
## gives each pack one shared territory to roam and never merges two.
const PACK_RADIUS := 14.0

var _world: Node3D
## Every wolf this node holds, in pack order.
var _wolves: Array = []
## One entry per `PACKS` row: `{posts, names, mobs, respawn_at}`.
var _packs: Array = []
var _culler
var _elapsed := 0.0
## Seconds this node has run: the refill clocks are absolute on it, so a clock
## survives a frame budget hitch the way a wall clock does.
var _clock := 0.0


## Spawn the band against `world`, whose own contract is the frontier's: `bodies`,
## `guards`, `lane_end()`, `trail_offset()`, `nearest_standing_body()` and the two
## handlers the wolves report to. Returns the wolves it placed.
##
## The node parents itself under the world if the caller has not done it yet:
## the wolves have to be in the tree for the `wild_mobs` group and for their
## global positions, and a setup call that silently produced a band of orphans
## would be worse than a little adoption.
func setup(world: Node3D) -> Array:
	if not is_instance_valid(world):
		push_error("WarbandWilderness.setup() needs a world")
		return []
	_world = world
	_elapsed = 0.0
	_clock = 0.0
	if not is_inside_tree() and world.is_inside_tree():
		world.add_child(self)
	_ensure_culler()
	_clear_wolves()
	var numbered := 0
	for spec in PACKS:
		var posts: Array[Vector3] = []
		var names: Array[String] = []
		for station in spec["stations"] as Array:
			# A corridor pack is measured from the camp's mouth; the lane packs
			# follow the lane's own polyline by fraction of its length.
			var point := _corridor_post(float(station[0]), float(station[1])) \
				if bool(spec.get("corridor", false)) \
				else _lane_post(float(station[0]), float(station[1]))
			posts.append(point)
			numbered += 1
			names.append("BriarWolf%d" % numbered)
		var members: Array = []
		for index in posts.size():
			members.append(_spawn_wolf(posts[index], names[index]))
		_packs.append({
			"posts": posts, "names": names,
			"mobs": members, "respawn_at": -1.0,
		})
	# Every wilderness body owns a patch; each pack's members spawned close
	# enough to share one frame of the wood, exactly as the frontier's own packs
	# do. One call, so the packs stay separate territories.
	MobWander.assign_all(_wolves, PACK_RADIUS)
	_refresh()
	return _wolves.duplicate()


func _process(delta: float) -> void:
	Perf.begin("wild.tick")
	_clock += delta
	_tick_refresh(delta)
	Perf.end()


func _tick_refresh(delta: float) -> void:
	if _wolves.is_empty():
		return
	_elapsed += delta
	if _elapsed < REFRESH_SECONDS:
		return
	_elapsed = fmod(_elapsed, REFRESH_SECONDS)
	_refill()
	_refresh()


## The wolves this node holds, in pack order.
func wolves() -> Array:
	return _wolves.duplicate()


## The band's packs, one array of wolves per `PACKS` entry, in spawn order.
func packs() -> Array:
	var out: Array = []
	for pack in _packs:
		out.append((pack["mobs"] as Array).duplicate())
	return out


## Seconds left on pack `index`'s refill clock, or -1.0 while the pack has
## nothing dead. The packs refill on their own; this is what the regression and
## the HUD read.
func pack_refill_in(index: int) -> float:
	if index < 0 or index >= _packs.size():
		return -1.0
	var at := float(_packs[index].get("respawn_at", -1.0))
	return -1.0 if at < 0.0 else maxf(at - _clock, 0.0)


## Put pack `index`'s fallen back on their posts now, on the same path the clock
## takes, and return how many bodies came back. The three minutes are the clock's
## business; a scripted encounter may refill a pack by hand.
func refill_pack(index: int) -> int:
	if index < 0 or index >= _packs.size():
		return 0
	return _refill_one(_packs[index])


## The one sweep that parks a wolf the squad has left far behind.
func culler():
	return _culler


# --- the band ---------------------------------------------------------------

func _spawn_wolf(point: Vector3, wolf_name: String) -> Node:
	var wolf = EnemyScript.new()
	# kind 0 is the authored briar wolf: level 1 in everything but name.
	wolf.kind = 0
	wolf.position = point
	wolf.player = _nearest(point)
	wolf.targets = _standing_bodies()
	wolf.safe_center = _safe_center()
	add_child(wolf)
	# `_ready` read the local transform; a container with its own transform must
	# still leave the wolf standing on the world point, with that point as home.
	wolf.global_position = point
	wolf.home = point
	# `_ready` names every wolf after its species; the band names it after its
	# post instead, so a corpse, a pack or a log line can name the one it means -
	# and a body that comes back takes the name of the one it replaced, which is
	# the name the wire finds a mob by.
	wolf.name = wolf_name
	if _world.has_method("_on_enemy_defeated"):
		wolf.defeated.connect(Callable(_world, "_on_enemy_defeated"))
	elif _wolves.is_empty():
		push_warning("WarbandWilderness: the world has no _on_enemy_defeated; kills go unreported")
	if _world.has_method("_on_enemy_attack"):
		wolf.attacked.connect(Callable(_world, "_on_enemy_attack"))
	elif _wolves.is_empty():
		push_warning("WarbandWilderness: the world has no _on_enemy_attack; blows land nowhere")
	var guards = _world.get("guards")
	if guards is Array:
		guards.append(wolf)
	_wolves.append(wolf)
	return wolf


## Put the band's aim back on the bodies that are standing right now. The free
## bodies are the world's list, and a wolf's `player` is simply the closest of
## them: a downed body is revived, never hunted.
func _refresh() -> void:
	if not is_instance_valid(_world):
		return
	var standing := _standing_bodies()
	for wolf in _wolves:
		if not is_instance_valid(wolf) or not bool(wolf.get("alive")):
			continue
		wolf.player = _nearest(wolf.global_position)
		wolf.targets = standing


func _standing_bodies() -> Array[CharacterBody3D]:
	var standing: Array[CharacterBody3D] = []
	var bodies = _world.get("bodies")
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
	if _world != null and _world.has_method("nearest_standing_body"):
		return _world.nearest_standing_body(point)
	var best = null
	var best_distance := INF
	for body in _standing_bodies():
		var distance := (body as Node3D).global_position.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = body
	return best


## The ring the camp's own mobs use: the town's end of the trail. A body inside it
## is never noticed or chased, which keeps the wolves off the town square without
## a second rule for it.
func _safe_center() -> Vector3:
	if _world != null and _world.has_method("lane_end"):
		return _world.lane_end()
	return Vector3(0.0, 0.0, -100000.0)


# --- the refill -------------------------------------------------------------

## One refill clock per pack, never one per wolf. A pack with nothing dead has no
## clock; a pack whose first body fell gets one `RESPAWN_SECONDS` out, and the
## clock is read here on the 0.5 s tick with the aim.
func _refill() -> void:
	for pack in _packs:
		var lost := 0
		for mob in pack["mobs"] as Array:
			if not is_instance_valid(mob) or not bool(mob.get("alive")):
				lost += 1
		if lost == 0:
			pack["respawn_at"] = -1.0
			continue
		var at := float(pack["respawn_at"])
		if at < 0.0:
			pack["respawn_at"] = _clock + RESPAWN_SECONDS
			continue
		if _clock < at:
			continue
		_refill_one(pack)


## The pack's fallen back on their own posts. A body still on its feet is left
## exactly where it is - a refill is never a teleport and never a second body -
## and a body that comes back is booked into the world's one hostile list and into
## its pack's own territory.
func _refill_one(pack: Dictionary) -> int:
	# A guest fielded the same band, but the bodies it draws are the host's: a
	# second wolf spawned here would be a wolf the host never spawned.
	if _is_client():
		return 0
	var posts: Array = pack["posts"]
	var names: Array = pack["names"]
	var members: Array = pack["mobs"]
	var quiet := true
	for post in posts:
		if _body_within(post as Vector3, RESPAWN_QUIET):
			quiet = false
			break
	if not quiet:
		return 0
	var fresh: Array = []
	for index in members.size():
		var old = members[index]
		if is_instance_valid(old) and bool(old.get("alive")):
			continue
		if is_instance_valid(old):
			_retire(old)
		var wolf := _spawn_wolf(posts[index], str(names[index]))
		members[index] = wolf
		fresh.append(wolf)
	if fresh.is_empty():
		pack["respawn_at"] = -1.0
		return 0
	_join_territory(members, fresh)
	pack["respawn_at"] = -1.0
	_sync_band()
	return fresh.size()


## The patch a body that came back belongs to: its packmates' own territory while
## any of them is still walking it, and a freshly handed one when the pack was cut
## down to the last body.
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
	var guards = _world.get("guards") if is_instance_valid(_world) else null
	if guards is Array:
		(guards as Array).erase(corpse)
	corpse.name = "%sCorpse" % corpse.name
	corpse.queue_free()


## True while any party body - standing or down - is inside `metres` of `point`.
func _body_within(point: Vector3, metres: float) -> bool:
	var bodies = _world.get("bodies") if is_instance_valid(_world) else null
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
	if not is_instance_valid(_world):
		return false
	var client = _world.get("_client")
	return client is bool and bool(client)


func _sync_band() -> void:
	_wolves.clear()
	for pack in _packs:
		_wolves.append_array(pack["mobs"] as Array)


# --- the posts --------------------------------------------------------------

## A corridor post: `along` metres from the camp's mouth down the straight cut the
## way out is made through the trees, `side` metres off that line.
func _corridor_post(along: float, side: float) -> Vector3:
	var mouth: Vector3 = WoodScript.GATE_POINT
	return _ground(mouth + Vector3(side, 0.0, -along))


func _trail_offset() -> Vector3:
	if _world != null and _world.has_method("trail_offset"):
		return _world.trail_offset()
	return Vector3.ZERO


## A lane post at `fraction` of the lane's measured length, `side` metres off the
## centre line. The polyline is the world's own table, so a waypoint the road's
## owner moves takes the pack with it; the lateral offset is held at
## `LANE_LATERAL_MIN`, so no member spawns inside a trunk collider or in the band
## a body walks.
func _lane_post(fraction: float, side: float) -> Vector3:
	var lane: Array = RunForestScript.LANE_POINTS
	var reach := clampf(fraction, 0.0, 1.0) * lane_metres()
	var travelled := 0.0
	var point: Vector3 = lane[0]
	var heading := Vector3(0.0, 0.0, -1.0)
	for index in range(lane.size() - 1):
		var from: Vector3 = lane[index]
		var to: Vector3 = lane[index + 1]
		var span := from.distance_to(to)
		if travelled + span >= reach or index == lane.size() - 2:
			var t := clampf((reach - travelled) / maxf(span, 0.0001), 0.0, 1.0)
			point = from.lerp(to, t)
			heading = to - from
			heading.y = 0.0
			if heading.length_squared() < 0.0001:
				heading = Vector3(0.0, 0.0, -1.0)
			heading = heading.normalized()
			break
		travelled += span
	var across := Vector3(-heading.z, 0.0, heading.x)
	var lateral := side
	if absf(lateral) < LANE_LATERAL_MIN:
		lateral = signf(lateral if absf(lateral) > 0.001 else 1.0) * LANE_LATERAL_MIN
	point = point + _trail_offset() + across * lateral
	# A world whose lane doubles back over the camp is not one this band may stand
	# in: fall back to the corridor's own line, which is always on the road's side
	# of the mouth.
	if not _clear_of_camp(point):
		point = WoodScript.GATE_POINT + Vector3(lateral, 0.0, -reach - WoodScript.CAMP_TO_ROAD_METRES)
	return _ground(point)


## The lane's measured length, from the one table the world lays it out on:
## ~1,376 m of road between the corridor and the town gate.
static func lane_metres() -> float:
	var total := 0.0
	var lane: Array = RunForestScript.LANE_POINTS
	for index in range(lane.size() - 1):
		total += (lane[index] as Vector3).distance_to(lane[index + 1] as Vector3)
	return total


## Never on the mouth, never inside the pocket.
static func _clear_of_camp(point: Vector3) -> bool:
	var mouth: Vector3 = WoodScript.GATE_POINT
	if Vector2(point.x - mouth.x, point.z - mouth.z).length() < MOUTH_CLEARANCE:
		return false
	var in_pocket := absf(point.x - mouth.x) < WoodScript.YARD_HALF_WIDTH \
		and point.z > WoodScript.YARD_FRONT - 2.0 and point.z < WoodScript.YARD_BACK + 2.0
	return not in_pocket


## The world's ground if it exposes one - the frontier bakes `terrain.gd`'s field
## at `_build_ground` - and the flat plane a preview or a stub world stands on
## otherwise. Either way the body starts the same 12 cm clear a frontier spawn does.
func _ground(point: Vector3) -> Vector3:
	var at := point
	if _has_terrain():
		at = TerrainScript.grounded(at)
	return at + Vector3(0.0, SPAWN_LIFT, 0.0)


func _has_terrain() -> bool:
	if _world == null:
		return false
	if _world.has_method("terrain"):
		return true
	var field = _world.get("_terrain")
	return field is Dictionary and not (field as Dictionary).is_empty()


# --- the sweep --------------------------------------------------------------

func _ensure_culler() -> void:
	if is_instance_valid(_culler) and _culler.get_parent() == self:
		return
	_culler = MobCullerScript.new()
	_culler.name = "MobCuller"
	add_child(_culler)
	# The eyes are every body a soul could be inside, so a guest's own ground is
	# swept by the same optimisations as the host's.
	_culler.attach(_world.get("controller"))


## A second setup replaces the band rather than stacking two on the same road.
func _clear_wolves() -> void:
	var guards = _world.get("guards")
	for wolf in _wolves:
		if not is_instance_valid(wolf):
			continue
		if guards is Array:
			guards.erase(wolf)
		wolf.queue_free()
	_wolves.clear()
	_packs.clear()
