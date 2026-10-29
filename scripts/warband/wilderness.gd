class_name WarbandWilderness
extends Node
## The briar wolves of the way out: the band the warband meets between the camp's
## mouth and the first stretch of the trail.
##
## The camp road is the only place in the campaign where a body can learn to
## fight without a tutorial card in the way, so the wood is not empty, but the
## road itself is: eight briar wolves hunt the widened forest in two deep packs of
## four - one beside the corridor `cage_escape.gd` cuts through the trees at 38-50
## m, one off the lane far down at 688-712 m. Their posts are derived, never
## rolled - the corridor from `GATE_POINT` for `CAMP_TO_ROAD_METRES`, then the
## lane the world places at `trail_offset()` - so two visits meet the same packs
## standing in the same places, and no wolf is ever inside the camp pocket, the
## town square, or a body's sight of the route it is walking.
##
## "Level 1" is not a stat the mobs carry: `enemy.gd` has one authored wolf, kind
## 0 at 38 health, and that base body is what a first road should hold. The band
## is spawned unbuffed, aimed at the warband's own bodies and wired to the world's
## one kill/attack handler, exactly like the camp's watchers.
##
## The wilderness owns only what is different from the rest of the frontier: the
## posts, the 0.5 s target refresh (the warband changes what it is driving, and a
## body seated later must be huntable) and the `MobCuller` that keeps a wolf the
## squad has walked past from costing a tick behind the fog.

const EnemyScript = preload("res://scripts/enemy.gd")
const MobCullerScript = preload("res://scripts/mob_culler.gd")
const MobWander = preload("res://scripts/mob_wander.gd")
const TerrainScript = preload("res://scripts/warband/terrain.gd")
const CampScript = preload("res://scripts/warband/cage_escape.gd")
const RunForestScript = preload("res://scripts/warband/run_forest.gd")

## Cleared ground: a wolf closer than this to the camp's mouth would be standing
## on the pocket's own edge, and the opening fight belongs to the camp's watchers.
const MOUTH_CLEARANCE := 25.0
## The deep-wood packs, and the whole band. There is no wolf on the lane or the
## corridor: the trail belongs to the cult and the archer ambushes, and a wolf
## pack is a thing a body finds by leaving the road. Two packs of four live well
## out in the widened wood, one either side of the route, their members 6-16 m
## apart inside one `PACK_RADIUS` so `assign_all` hands each pack one territory.
## `along` is metres from the camp's mouth measured on the lane itself, and
## `side` is metres off the centre line. Every post is past `DEEP_WOOD_INNER` and
## beyond the wolf's own 23 m sight of the lane (28-50 m out), so a body on the
## trail is never pulled into a pack, and clear of the two solid tree rows (the
## outermost solid trunk reaches ~10.5 m with its jitter), so no wolf spawns in a
## trunk collider.
const DEEP_WOOD_INNER := 15.0
const PACKS := [
	# The first pack is off the corridor beside the trail-start checkpoint, deep
	# enough (38-50 m) that a body on the road never sees it, near enough that a
	# squad that leaves the path finds it - and that a co-op guest at the
	# checkpoint has one in its 70 m replication band.
	{"name": "BriarPackA", "corridor": true, "stations": [
		[62.0, -38.0], [68.0, -46.0], [74.0, -42.0], [80.0, -50.0],
	]},
	{"name": "BriarPackB", "stations": [
		[688.0, 30.0], [696.0, 36.0], [704.0, 43.0], [712.0, 50.0],
	]},
]
## Both deep packs, for the tests that count the whole band.
const PACK_COUNT := 8
## The same 12 cm the frontier lifts every mob spawn by, so a body dropped on the
## analytic ground starts just clear of it instead of inside the collider.
const SPAWN_LIFT := 0.12
## The warband can seat, down or hand over a body at any moment; half a second is
## fast enough that a wolf never hunts a body that has left, and cheap enough that
## the frontier's hosts do not notice it.
const REFRESH_SECONDS := 0.5
## `main.gd`'s pack radius for every wilderness band. The corridor posts are
## eighteen to twenty-six metres apart, so they keep their own patches; each deep
## pack's posts sit inside this radius of one another, so `assign_all` gives that
## pack one shared territory to roam.
const PACK_RADIUS := 14.0

var _world: Node3D
var _wolves: Array = []
## The deep-wood packs, one array of wolves per entry in `PACKS`, in spawn order.
var _packs: Array = []
var _culler
var _elapsed := 0.0


## Spawn the band against `world`, whose own contract is the frontier's: `bodies`,
## `guards`, `lane_end()`, `trail_offset()`, `nearest_standing_body()` and the two
## handlers the wolves report to. Returns the wolves it placed.
##
## The node parents itself under the world if the caller has not done it yet:
## the wolves have to be in the tree for the `wild_mobs` group and for their
## global positions, and a setup call that silently produced seven orphans would
## be worse than a little adoption.
func setup(world: Node3D) -> Array:
	if not is_instance_valid(world):
		push_error("WarbandWilderness.setup() needs a world")
		return []
	_world = world
	_elapsed = 0.0
	if not is_inside_tree() and world.is_inside_tree():
		world.add_child(self)
	_ensure_culler()
	_clear_wolves()
	# The deep wood has its own bands: each pack's posts are close enough to one
	# another to merge under `PACK_RADIUS`, and far enough from the lane that a
	# body has to leave the trail to meet one.
	_packs.clear()
	for pack in PACKS:
		var members: Array = []
		for station in pack["stations"] as Array:
			# A corridor pack is measured from the camp's mouth like the old band;
			# the lane packs follow the lane's own polyline.
			var point := _post(float(station[0]), float(station[1])) \
				if bool(pack.get("corridor", false)) \
				else _lane_post(float(station[0]), float(station[1]))
			members.append(_spawn_wolf(point))
		_packs.append(members)
	# Every wilderness body owns a patch; each pack's members spawned close
	# enough to share one frame of the wood, exactly as the frontier's own packs
	# do. One call, so the two packs stay two territories.
	MobWander.assign_all(_wolves, PACK_RADIUS)
	_refresh()
	return _wolves.duplicate()


func _process(delta: float) -> void:
	if _wolves.is_empty():
		return
	_elapsed += delta
	if _elapsed < REFRESH_SECONDS:
		return
	_elapsed = fmod(_elapsed, REFRESH_SECONDS)
	_refresh()


## The wolves this node holds, in spawn order.
func wolves() -> Array:
	return _wolves.duplicate()


## The deep-wood packs, one array of wolves per `PACKS` entry. The corridor band
## is not one of them: those posts are solo, exactly as they were.
func packs() -> Array:
	return _packs.duplicate()


## The one sweep that parks a wolf the squad has left far behind.
func culler():
	return _culler


# --- the band ---------------------------------------------------------------

func _spawn_wolf(point: Vector3) -> Node:
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
	# `_ready` gives every wolf the species name; the band numbers them so a
	# corpse, a pack or a log line can name the one it means.
	wolf.name = "BriarWolf%d" % (_wolves.size() + 1)
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


# --- the posts --------------------------------------------------------------

## A post `along` metres from the camp's mouth, `side` metres off the line. The
## corridor is the camp's own straight line; past `CAMP_TO_ROAD_METRES` the lane
## takes over, and the lane's heading is the world's offset applied to the lane's
## authored points - the one table the trail is built from.
func _post(along: float, side: float) -> Vector3:
	var mouth: Vector3 = CampScript.GATE_POINT
	var point: Vector3
	if along <= CampScript.CAMP_TO_ROAD_METRES:
		point = mouth + Vector3(side, 0.0, -along)
	else:
		var lane_start: Vector3 = RunForestScript.LANE_POINTS[0] + _trail_offset()
		var heading: Vector3 = RunForestScript.LANE_POINTS[1] - RunForestScript.LANE_POINTS[0]
		heading.y = 0.0
		if heading.length_squared() < 0.0001:
			heading = Vector3(0.0, 0.0, -1.0)
		heading = heading.normalized()
		var across := Vector3(-heading.z, 0.0, heading.x)
		point = lane_start + heading * (along - CampScript.CAMP_TO_ROAD_METRES) + across * side
	# A world whose trail offset sends the lane back over the camp is not one this
	# band may stand in: fall back to the corridor's own line, which is always
	# `along` metres of ordinary wood past the mouth.
	if not _clear_of_camp(point):
		point = mouth + Vector3(side, 0.0, -along)
	return _ground(point)


func _trail_offset() -> Vector3:
	if _world != null and _world.has_method("trail_offset"):
		return _world.trail_offset()
	return Vector3.ZERO


## A post `along` metres from the camp's mouth, `side` metres left or right of the
## **lane itself**. `_post()` extrapolates the lane's first tangent, which is fine
## for the first 250 m and wrong by tens of metres at 500: the deep packs are laid
## on the real polyline so "15-30 m off the lane" means off the lane a body walks.
## The lateral offset is held at `DEEP_WOOD_INNER`'s edge of the solid tree rows,
## so no member spawns inside a trunk collider.
func _lane_post(along: float, side: float) -> Vector3:
	var mouth: Vector3 = CampScript.GATE_POINT
	if along <= CampScript.CAMP_TO_ROAD_METRES:
		return _post(along, side)
	var reach := along - CampScript.CAMP_TO_ROAD_METRES
	var offset := _trail_offset()
	var lane: Array = RunForestScript.LANE_POINTS
	var travelled := 0.0
	var point := Vector3.ZERO
	var heading := Vector3(0.0, 0.0, -1.0)
	for index in range(lane.size() - 1):
		var from: Vector3 = lane[index] + offset
		var to: Vector3 = lane[index + 1] + offset
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
	if absf(lateral) < DEEP_WOOD_INNER:
		lateral = signf(lateral if absf(lateral) > 0.001 else 1.0) * DEEP_WOOD_INNER
	var at := point + across * lateral
	# A world whose lane doubles back over the camp is not one this band may stand
	# in: fall back to the corridor's own line.
	if not _clear_of_camp(at):
		at = mouth + Vector3(lateral, 0.0, -along)
	return _ground(at)


## Never on the mouth, never inside the pocket.
static func _clear_of_camp(point: Vector3) -> bool:
	var mouth: Vector3 = CampScript.GATE_POINT
	if Vector2(point.x - mouth.x, point.z - mouth.z).length() < MOUTH_CLEARANCE:
		return false
	var in_pocket := absf(point.x - mouth.x) < CampScript.YARD_HALF_WIDTH \
		and point.z > CampScript.YARD_FRONT - 2.0 and point.z < CampScript.YARD_BACK + 2.0
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
