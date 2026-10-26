extends RefCounted
## Idle wandering for every wilderness body that is not in a fight.
##
## A lone roamer keeps to the patch it spawned in: it picks a point inside its
## own disc, walks there at its walk speed and rests before choosing another.
## A pack shares one territory, so its members move on the same rhythm and
## settle into ring slots around one goal instead of drifting apart; species
## that do not pack (a sentinel on its post, a rooted gallowsroot) never merge
## with a neighbour, however close they spawned.
##
## A territory advances on the wall clock rather than per member, so any member
## can roll the next goal and no member ever double-advances it. Bodies that
## were never assigned (the delve wave, a fresh respawn) simply never wander.

const MobSenses = preload("res://scripts/mob_senses.gd")

## Rest before the first goal, so a loaded world is not already in motion.
const SETTLE_MIN := 2.0
const SETTLE_MAX := 4.0
## How long a goal stays interesting before another is rolled.
const DWELL_MIN := 2.4
const DWELL_MAX := 6.5
## Standing this close to the goal means it arrived; the body rests there.
const ARRIVE := 0.75
## Pack members surround the shared goal on a ring this wide.
const SLOT_RADIUS := 1.7
## Points are drawn between these fractions of the territory radius.
const REACH_MIN := 0.35
const REACH_MAX := 0.90
## A new goal always lands at least this far from the last one, so a small
## patch cannot keep handing out points under the body's feet.
const MIN_MOVE := 2.0
## Walking this long below this speed means the goal is unreachable (it landed
## inside a building): the patch rolls a fresh one.
const STALL_SECONDS := 2.5
const STALL_SPEED := 0.4
## A goal behind a building is not walkable: when the lane to it is shut the
## body drifts back toward the middle of its patch instead of grinding.
const LANE_PROBE := 2.6
## Height above the body's feet at which the lane is sampled.
const LANE_LIFT := 0.7


## One shared patch: its centre, how far it reaches, and the goal its owners
## are currently walking toward.
class Territory:
	extends RefCounted
	var center := Vector3.ZERO
	var radius := 8.0
	var goal := Vector3.ZERO
	var goal_valid := false
	var next_roll := 0.0
	var slots := 1
	var _rng := RandomNumberGenerator.new()

	func _init(seed_value: int = 1) -> void:
		_rng.seed = maxi(seed_value, 1)

	func roll(now: float) -> void:
		var angle := _rng.randf() * TAU
		var reach := radius * _rng.randf_range(REACH_MIN, REACH_MAX)
		var next := center + Vector3(cos(angle), 0.0, sin(angle)) * reach
		if goal_valid and next.distance_to(goal) < maxf(radius * 0.35, MIN_MOVE):
			# Too close to where they already are: cross to the far side.
			next = center - (next - center)
		goal = next
		goal_valid = true
		next_roll = now + _rng.randf_range(DWELL_MIN, DWELL_MAX)


## The territory this body belongs to, its ring slot and the pack's group name
## (empty for a lone roamer).
var territory: Territory
var slot := 0
var group := ""

var _settle_until := 0.0
var _last := Vector3.ZERO
var _stall := 0.0
var _walking := false
var _query := PhysicsRayQueryParameters3D.new()


func _init() -> void:
	# World geometry only: a packmate standing in the lane is not a wall.
	_query.collision_mask = 1


## Called once the world has placed every body: `territory` may be shared.
func assign(shared: Territory, ring_slot: int, pack_group: String) -> void:
	territory = shared
	slot = ring_slot
	group = pack_group
	_settle_until = _now() + randf_range(SETTLE_MIN, SETTLE_MAX)
	_stall = 0.0
	_walking = false


## A respawned or freshly configured body starts over: no territory is assumed
## until the world assigns one again.
func reset() -> void:
	territory = null
	slot = 0
	group = ""
	_settle_until = 0.0
	_stall = 0.0
	_walking = false


## The next heading for a calm body: ZERO means rest here. The caller owns the
## speed and the steering around obstacles.
func step(owner: Node3D) -> Vector3:
	if not is_instance_valid(owner) or territory == null:
		return Vector3.ZERO
	var now := _now()
	if now < _settle_until:
		return Vector3.ZERO
	_check_progress(owner)
	if outside(owner):
		# Something pushed it out of its patch (a chase, a shove): come home,
		# whatever goal the patch is holding.
		var home := territory.center - owner.global_position
		home.y = 0.0
		if home.length() > ARRIVE:
			_walking = true
			return home.normalized()
	if not territory.goal_valid or territory.next_roll <= now:
		territory.roll(now)
	var target := territory.goal
	if territory.slots > 1:
		var angle := TAU * float(slot) / float(territory.slots)
		target += Vector3(cos(angle), 0.0, sin(angle)) * SLOT_RADIUS
	var offset := target - owner.global_position
	offset.y = 0.0
	_walking = offset.length() > ARRIVE
	if not _walking:
		return Vector3.ZERO
	var heading := offset.normalized()
	if _wall_ahead(owner, heading):
		# The goal sits behind something. Drift back toward open ground inside
		# the patch; the stall clock rolls a fresh goal if that fails too.
		var inward := territory.center - owner.global_position
		inward.y = 0.0
		if inward.length() > ARRIVE and not _wall_ahead(owner, inward.normalized()):
			_walking = true
			return inward.normalized()
	return heading


## True when a straight lane out of the body is shut.
func _wall_ahead(owner: Node3D, direction: Vector3) -> bool:
	if not is_instance_valid(owner) or not owner.is_inside_tree():
		return false
	var space := owner.get_world_3d().direct_space_state
	_query.from = owner.global_position + Vector3(0.0, LANE_LIFT, 0.0)
	_query.to = _query.from + direction * LANE_PROBE
	return not space.intersect_ray(_query).is_empty()


## A goal that cannot be walked to (it landed inside a building) would pin the
## body against the same wall for a whole dwell: give the patch a fresh one.
func _check_progress(owner: Node3D) -> void:
	var moved := owner.global_position.distance_to(_last)
	_last = owner.global_position
	if not _walking:
		_stall = 0.0
		return
	var delta := 1.0 / 60.0
	if owner.is_inside_tree():
		delta = maxf(float(owner.get_physics_process_delta_time()), 0.0001)
	if moved < STALL_SPEED * delta:
		_stall += delta
		if _stall >= STALL_SECONDS:
			_stall = 0.0
			territory.next_roll = 0.0
	else:
		_stall = 0.0


## True when this body is outside the patch it is supposed to keep to.
func outside(owner: Node3D) -> bool:
	if not is_instance_valid(owner) or territory == null:
		return false
	return Vector2(owner.global_position.x - territory.center.x,
		owner.global_position.z - territory.center.z).length() > territory.radius + 1.0


## Distance from the patch centre, for the regressions and the HUD hooks.
func distance_from_center(owner: Node3D) -> float:
	if not is_instance_valid(owner) or territory == null:
		return 0.0
	return Vector2(owner.global_position.x - territory.center.x,
		owner.global_position.z - territory.center.z).length()


## Cluster the bodies that pack into shared territories and give every other
## mobile body a private disc of its own spawn. A band is one species: two
## bodies merge only when both pack and share `pack_family()`, so the court's
## five species keep their own posts even when they spawn side by side while a
## nest of three devil spawns becomes one pack. Returns the number of
## territories handed out.
static func assign_all(mobs: Array, pack_radius: float) -> int:
	var pending: Array = []
	for mob in mobs:
		if not is_instance_valid(mob) or not mob.has_method("wanders_packed"):
			continue
		pending.append(mob)
	var claimed := {}
	var index := 0
	for mob in pending:
		if claimed.has(mob):
			continue
		claimed[mob] = true
		var members: Array = [mob]
		if bool(mob.wanders_packed()):
			var family := str(mob.pack_family())
			for other in pending:
				if other == mob or claimed.has(other) or not bool(other.wanders_packed()):
					continue
				if str(other.pack_family()) != family:
					continue
				if other.global_position.distance_to(mob.global_position) <= pack_radius:
					claimed[other] = true
					members.append(other)
		_hand_out(members, index)
		index += 1
	return index


static func _hand_out(members: Array, index: int) -> void:
	var center := Vector3.ZERO
	var count := 0
	for mob in members:
		center += mob.global_position
		count += 1
	if count == 0:
		return
	center /= float(count)
	var territory := Territory.new(7919 + index * 131)
	territory.center = center
	territory.slots = count
	var reach := 1.0
	for mob in members:
		var roam := float(mob.wander_radius())
		reach = maxf(reach, roam + Vector2(mob.global_position.x - center.x,
			mob.global_position.z - center.z).length())
	# A body posted inside the town's safe ring keeps its patch inside it: the
	# court and the threshold trio stay where the ranger can inspect them and
	# never drift into the square.
	var ring = members[0].get("safe_center")
	if ring is Vector3:
		var inside := Vector2(center.x - ring.x, center.z - ring.z).length()
		if inside < MobSenses.SAFE_RING:
			reach = minf(reach, maxf(1.5, MobSenses.SAFE_RING - inside - 1.0))
	territory.radius = reach
	var group := "" if count < 2 else "mob_pack_%d" % index
	for mob in members:
		mob.assign_territory(territory, members.find(mob), group)
		if not group.is_empty():
			mob.add_to_group(group)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
