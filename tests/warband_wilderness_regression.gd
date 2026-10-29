extends SceneTree
## The briar wolves of the camp road: a stub world with the frontier's own shape
## stands a flat floor and one ranger, `WarbandWilderness.setup()` must fill the
## way out with a band of wolves that are real `enemy.gd` mobs, the world owns
## them, they stand clear of the camp, they aim at the ranger, and one
## `MobCuller` sweep parks a wolf that has been left far behind.
##
## The stub's `trail_offset()` is the real one (`GATE_POINT.z - CAMP_TO_ROAD_METRES`
## minus the lane's authored first point), so the first-stretch posts land where
## the campaign puts them and the clearance check means something.

const WildernessScript = preload("res://scripts/warband/wilderness.gd")
const CampScript = preload("res://scripts/warband/cage_escape.gd")

## The lone ranger stands between the corridor posts and the trail posts, so no
## wolf is more than 150 m from a body and every one of them is awake.
const TARGET_POST := Vector3(0.0, 0.0, -150.0)
const MOUTH_CLEARANCE := 25.0
const FLEE_METRES := 300.0
## Falling onto the floor is budgeted like everything else in `enemy.gd`; this
## cap is four seconds, and the band lands long before it.
const SETTLE_FRAMES := 240

var checks := 0
var failures := 0


class StubBody:
	extends CharacterBody3D
	var alive := true
	var downed := false


## The frontier's contract, as far as this module can see it: the body list, the
## guard list, the ring at the town end, the lane offset, the nearest-ranger
## lookup and the two handlers the mobs report to.
class StubWorld:
	extends Node3D
	const Camp = preload("res://scripts/warband/cage_escape.gd")

	var bodies: Array = []
	var guards: Array = []
	var lane := Vector3(3.0, 0.0, -1100.0)
	var pickups: Array = []
	var killed := 0
	var struck := 0

	func lane_end() -> Vector3:
		return lane

	## `trail_offset()` is `trail_start - LANE_POINTS[0]`, and the lane's authored
	## head is (0, 0, 6): the real offset puts the trail head on the corridor's
	## end, which is what makes the first-stretch posts land on the lane.
	func trail_offset() -> Vector3:
		return Vector3(0.0, 0.0,
			Camp.GATE_POINT.z - Camp.CAMP_TO_ROAD_METRES - 6.0)

	func nearest_standing_body(point: Vector3):
		var best = null
		var best_distance := INF
		for body in bodies:
			if not is_instance_valid(body):
				continue
			if not bool(body.get("alive")) or bool(body.get("downed")):
				continue
			var distance: float = (body as Node3D).global_position.distance_to(point)
			if distance < best_distance:
				best_distance = distance
				best = body
		return best

	func spawn_pickup(item_id: String, at: Vector3):
		pickups.append({"item": item_id, "at": at})
		return null

	func _on_enemy_defeated(_enemy, _reward: int) -> void:
		killed += 1

	func _on_enemy_attack(_attacker, _amount: float, _victim) -> void:
		struck += 1


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WARBAND_WILDERNESS_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func _settle(wolves: Array) -> void:
	for _frame in SETTLE_FRAMES:
		var settled := true
		for wolf in wolves:
			if not is_instance_valid(wolf):
				continue
			if not bool(wolf.is_on_floor()):
				settled = false
				break
		if settled:
			return
		await physics_frame


func run() -> void:
	var world := StubWorld.new()
	world.name = "StubWildernessWorld"
	root.add_child(world)
	_build_floor(world)

	var target := StubBody.new()
	target.name = "Ranger"
	target.collision_layer = 4
	target.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	target.add_child(shape)
	target.position = TARGET_POST
	world.add_child(target)
	world.bodies = [target]

	var wilderness := WildernessScript.new()
	wilderness.name = "Wilderness"
	world.add_child(wilderness)
	var spawned: Array = wilderness.setup(world)

	# --- the band -----------------------------------------------------------
	var expected_wolves := WildernessScript.PACK_COUNT
	check(spawned.size() == expected_wolves,
		"setup spawns only the two deep packs (%d, got %d)"
		% [expected_wolves, spawned.size()])
	var mouth: Vector3 = CampScript.GATE_POINT
	for wolf in spawned:
		check(is_instance_valid(wolf), "every spawned wolf is a live node")
		if not is_instance_valid(wolf):
			continue
		check(int(wolf.kind) == 0, "wolf kind 0 is the level-1 briar wolf")
		check(world.guards.has(wolf), "%s is in world.guards" % wolf.name)
		check(wolf.is_in_group("wild_mobs"), "%s joined wild_mobs itself" % wolf.name)
		var planar := Vector2(wolf.global_position.x - mouth.x,
			wolf.global_position.z - mouth.z).length()
		check(planar >= MOUTH_CLEARANCE,
			"%s stands %.1f m from the camp mouth" % [wolf.name, planar])
		check(wolf.player == target, "%s aims at the nearest standing body" % wolf.name)
		check(wolf.safe_center.is_equal_approx(world.lane_end()),
			"%s carries the camp mobs' safe centre" % wolf.name)
		check(wolf.targets.has(target), "%s hunts the standing body" % wolf.name)

	check(wilderness.wolves().size() == spawned.size(),
		"wolves() exposes the whole band")

	# --- the sweep ----------------------------------------------------------
	var culler = wilderness.get_node_or_null("MobCuller")
	check(culler != null, "a MobCuller child exists")
	check(wilderness.culler() == culler, "culler() returns that node")
	check(culler != null and culler.name == "MobCuller", "the culler is named MobCuller")

	await _settle(spawned)
	# Every wolf now starts deep in the wood, well beyond sight. Wake one, walk it
	# 300 m behind the ranger and prove the culler parks it: a hunting body must
	# not sleep, and the sweep must never depend on one having kept its nose down.
	var stray = spawned[0] if not spawned.is_empty() else null
	check(stray != null, "a wolf was placed to strand")
	if stray != null:
		check((stray as Node3D).global_position.distance_to(target.global_position) > 30.0,
			"the pack starts off the trail, beyond sight")
		stray.mob_wake()
		check(not bool(stray.dormant), "the wolf is awake before the move")
		# Land it first, inside the tick band, then slide it out to 300 m. A body
		# teleported straight past `DORMANT_DISTANCE` while airborne gets no tick
		# (the budget gives it zero) and could never report its feet down.
		stray.global_position = Vector3(TARGET_POST.x, 0.12, TARGET_POST.z - 100.0)
		await _settle([stray])
		check(stray.is_on_floor(), "the wolf lands before it is stranded")
		stray.global_position = Vector3(stray.global_position.x, stray.global_position.y,
			TARGET_POST.z - FLEE_METRES)
		check(stray.global_position.distance_to(target.global_position) >= FLEE_METRES,
			"the stranded wolf really stands 300 m behind")
		if culler != null:
			culler.sweep()
		check(bool(stray.dormant), "one sweep parks the wolf left 300 m behind")

	world.queue_free()
	await process_frame
	print("WARBAND_WILDERNESS_REGRESSION checks=", checks, " failures=", failures)
	quit(1 if failures > 0 else 0)


func _build_floor(world: Node3D) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1400.0, 1.0, 1400.0)
	shape.shape = box
	floor_body.add_child(shape)
	world.add_child(floor_body)
