extends SceneTree
## The briar wolves of the wood road: a stub world with the frontier's own shape
## stands a flat floor and one ranger, `WarbandWilderness.setup()` must fill the
## way out with small packs of wolves that are real `enemy.gd` mobs, the world owns
## them, they stand clear of the walked lane and the wood's mouth, they aim at the
## ranger, one `MobCuller` sweep parks a wolf that has been left far behind, and a
## pack that is cut down refills on its own clock - one clock for the pack, and
## never over a living body.
##
## The stub's `trail_offset()` is the real one (`GATE_POINT.z - CAMP_TO_ROAD_METRES`
## minus the lane's authored first point), so the lane posts land where the
## campaign puts them and the clearance check means something. The floor stands
## under the whole lane, because the band now runs its length.

const WildernessScript = preload("res://scripts/warband/wilderness.gd")
const WoodScript = preload("res://scripts/warband/wood_boss.gd")
const LaneScript = preload("res://scripts/warband/run_forest.gd")
const WanderScript = preload("res://scripts/mob_wander.gd")

## The lone ranger stands between the corridor posts and the lane's own head, so
## the first packs are in reach and every post is measured against one body.
const TARGET_POST := Vector3(0.0, 0.0, -150.0)
const MOUTH_CLEARANCE := 25.0
## The walked band: no wolf may stand inside it.
const LANE_CLEARANCE := 1.55
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
	const Wood = preload("res://scripts/warband/wood_boss.gd")

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
			Wood.GATE_POINT.z - Wood.CAMP_TO_ROAD_METRES - 6.0)

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


## The warband's bodies, as the culler reads them.
class StubSouls:
	extends RefCounted
	var list: Array = []

	func bodies() -> Array:
		return list


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
		"setup spawns the whole band (%d, got %d)"
		% [expected_wolves, spawned.size()])
	check(wilderness.packs().size() == WildernessScript.PACKS.size(),
		"one array of wolves per pack, %d packs" % wilderness.packs().size())
	for pack in wilderness.packs():
		check((pack as Array).size() >= 2 and (pack as Array).size() <= 3,
			"a pack is two or three bodies (%d)" % (pack as Array).size())
	var mouth: Vector3 = WoodScript.GATE_POINT
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
			"%s stands %.1f m from the wood's mouth" % [wolf.name, planar])
		var lateral: float = _lane_lateral(world, wolf.global_position)
		check(lateral >= LANE_CLEARANCE,
			"%s keeps the walked band clear (%.2f m off the lane)"
				% [wolf.name, lateral])
		check(lateral >= WildernessScript.LANE_LATERAL_MIN - 0.01,
			"%s stands clear of the trunk rows (%.2f m off the lane)"
				% [wolf.name, lateral])
		check(wolf.player == target, "%s aims at the nearest standing body" % wolf.name)
		check(wolf.safe_center.is_equal_approx(world.lane_end()),
			"%s carries the wood mobs' safe centre" % wolf.name)
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
		# The optimisations follow every soul's ground, not the first player's: a
		# body standing beside that wolf - the other player's, two hundred metres
		# from the first - keeps it awake and hunting.
		if culler != null and stray != null:
			var other := Node3D.new()
			other.name = "GuestRanger"
			other.position = (stray as Node3D).global_position + Vector3(6.0, 0.0, 0.0)
			world.add_child(other)
			var souls := StubSouls.new()
			souls.list = [target, other]
			culler.attach(souls)
			culler.sweep()
			check(not bool(stray.dormant),
				"a body standing beside the wolf keeps it awake, whoever is inside it")
			# What a body is *drawn* at is this machine's own camera, not the
			# nearest soul: the host was skinning and shadow-casting the whole of a
			# guest's fight two hundred metres from its own eye. The wolf stays
			# awake - it must still fight - and rests its presentation.
			var eye := Camera3D.new()
			eye.name = "HostEye"
			root.add_child(eye)
			eye.global_position = Vector3(400.0, 3.0, 400.0)
			eye.current = true
			var wolf_at: Vector3 = (stray as Node3D).global_position
			check(is_equal_approx(culler.view_distance(wolf_at), wolf_at.distance_to(eye.global_position)),
				"the culler measures to this machine's eye (%.1f m)"
					% culler.view_distance(wolf_at))
			check(culler.nearest_eye(wolf_at) < 30.0, "while a soul stands beside the wolf")
			culler.sweep()
			check(not bool(stray.dormant),
				"a body beside the wolf still keeps its brain running")
			check(int(stray.get("_present_band")) == 2,
				"and the far eye rests its presentation (%s)"
					% str(stray.get("_present_band")))
			eye.global_position = (stray as Node3D).global_position + Vector3(0.0, 2.0, 4.0)
			culler.sweep()
			check(int(stray.get("_present_band")) == 0,
				"an eye beside the wolf draws it at full detail (%s)"
					% str(stray.get("_present_band")))
			eye.queue_free()
			culler.attach(null)
			other.queue_free()

	# --- the body steps on frames its brain sits out -----------------------
	# A wolf on the deep budget used to move on one frame in twelve: at seventy
	# metres that is a metre a step, five times a second, which is what a mob
	# popping forward reads as. The brain still decides on its budget; the body
	# walks every frame.
	var walking = spawned[1] if spawned.size() > 1 else null
	check(walking != null, "a second wolf is there to walk")
	if walking != null:
		# Far enough from the ranger for the far band, and off its own patch so it
		# is walking back rather than standing on the goal.
		walking.global_position = Vector3(TARGET_POST.x + 70.0, 0.12, TARGET_POST.z)
		await _settle([walking])
		# A calm body rests for `MobWander.SETTLE_MAX` from the frame the world
		# hands it a patch, and a resting body returns no heading at all: the
		# wander's own clock is not the budget this check is about, so it is
		# waited out first and the measurement starts with the wolf on the move.
		await create_timer(WanderScript.SETTLE_MAX + 0.5).timeout
		walking.mob_wake()
		var before: Vector3 = walking.global_position
		var moved := 0
		for _frame in 36:
			await physics_frame
			if not is_instance_valid(walking):
				break
			var step: float = (walking.global_position - before).length()
			before = walking.global_position
			if step > 0.004:
				moved += 1
		check(moved > 12,
			"a wolf on the far budget moves on most frames, not one in twelve (%d/36)" % moved)

	# --- a guest's copy is put down the moment the host stops naming it ----
	# The stream names what a player can reach; a body that leaves it used to stand
	# frozen where it was until the stale clock noticed, and the clock is longer
	# than the host's own refresh, so a living mob blinked out for a quarter of a
	# second at a time. The host says so, and the copy goes at once.
	var named = spawned[2] if spawned.size() > 2 else null
	check(named != null, "a third wolf is there to be streamed")
	if named != null:
		# The band stands its packs the whole length of the road, and the culler
		# parks a body no party body stands near - a copy parked at home is not
		# drawn for anyone, so the peer this block speaks for is a body standing
		# beside it. The eye list is the party's own bodies, whoever is inside
		# them (`MobCuller.attach`), so one is stood on the wolf's post.
		var beside := StubBody.new()
		beside.name = "BesideRanger"
		beside.collision_layer = 4
		beside.collision_mask = 0
		world.add_child(beside)
		beside.global_position = (named as Node3D).global_position + Vector3(6.0, 0.0, 0.0)
		var copy_eyes := StubSouls.new()
		copy_eyes.list = [target, beside]
		if culler != null:
			culler.attach(copy_eyes)
			culler.sweep()
		check(not bool(named.dormant),
			"a body standing beside the copy keeps it off the parking list")
		var pose := func(at: Vector3) -> Dictionary:
			return {"p": at, "y": 0.0, "v": Vector3.ZERO, "g": true, "s": "IDLE",
				"t": 0.0, "h": 38.0, "a": true, "x": Vector4.ZERO}
		named.call("mark_replica")
		check(not named.visible, "a copy the host has never named is not drawn")
		named.call("apply_snapshot", pose.call(Vector3(4.0, 0.2, 4.0)), 40)
		check(named.visible, "the first state the host sends puts it on the screen")
		check((named as Node3D).global_position.distance_to(Vector3(4.0, 0.2, 4.0)) < 0.01,
			"and it stands where the host says, not at its own spawn post")
		named.call("set_streamed", false, 41)
		check(not named.visible, "a body the host stops naming is put down at once")
		named.call("apply_snapshot", pose.call(Vector3(9.0, 0.2, 9.0)), 40)
		check(not named.visible, "a state from before the leave does not bring it back")
		check((named as Node3D).global_position.distance_to(Vector3(9.0, 0.2, 9.0)) > 0.5,
			"and does not move it either")
		named.call("apply_snapshot", pose.call(Vector3(12.0, 0.2, 12.0)), 42)
		check(named.visible, "the next state does")
		check((named as Node3D).global_position.distance_to(Vector3(12.0, 0.2, 12.0)) < 0.01,
			"at the pose it names, a reset rather than a slide from the old one")
		if culler != null:
			culler.attach(null)
		beside.queue_free()

	# --- a standing body asks the world for nothing ------------------------
	# `move_and_slide` is the most expensive thing a mob does in a frame (2.6 us
	# on this project's world, 0.5 ms for two hundred of them at 60 Hz), and for a
	# body with its feet down and no motion it resolves to standing still. The rule
	# is `MobLod.moving`: airborne, or actually moving. This is what keeps a hall of
	# bodies holding position from costing a capsule cast each, every frame.
	var level = spawned[3] if spawned.size() > 3 else null
	if level != null:
		var lod = load("res://scripts/mob_lod.gd")
		await _settle([level])
		(level as Node3D).global_position = Vector3(TARGET_POST.x + 30.0, 0.12, TARGET_POST.z)
		await _settle([level])
		level.velocity = Vector3.ZERO
		await physics_frame
		level.velocity = Vector3.ZERO
		check(level.is_on_floor(), "a settled wolf stands on its feet")
		check(not lod.moving(level),
			"a standing wolf has nowhere to go, so it asks the world nothing")
		# The rule is the contract (a live wolf always has an intent, so it is never
		# "standing" for long): `MobLod.move` is `if moving(body): move_and_slide()`.
		level.velocity = Vector3(2.0, 0.0, 0.0)
		check(lod.moving(level), "a walking wolf does sweep")
		level.velocity = Vector3.ZERO

	# --- a cut pack comes back, one clock for the pack ---------------------
	# The road is a grind, not a one-off: a pack that is cut down refills at its own
	# posts after `RESPAWN_SECONDS`, on one clock for the whole pack. Packs 2, 3 and
	# 4 were never touched by the sweep and the replication checks above, so one is
	# the whole pack that comes back, one is the pack a body holds down, and one is
	# the pack that loses a single body.
	var cut: int = wilderness.packs().size() - 1
	var pack: Array = wilderness.packs()[cut]
	# `home` is the post the body was spawned on; `global_position` is where the
	# patch has walked it since, and the refill puts it back on the former.
	var posts: Array[Vector3] = []
	var names: Array[String] = []
	for wolf in pack:
		posts.append((wolf as Node3D).home)
		names.append(str((wolf as Node).name))
		(wolf as Node).call("take_damage", 4000.0, 0)
	await create_timer(0.7).timeout
	var counting: float = wilderness.pack_refill_in(cut)
	check(counting > 0.0 and counting <= WildernessScript.RESPAWN_SECONDS,
		"the cut pack is counting down its refill (%.1f s of %.0f)"
			% [counting, WildernessScript.RESPAWN_SECONDS])
	check(wilderness.pack_refill_in(0) < 0.0,
		"a pack nothing died in has no clock (%.1f)" % wilderness.pack_refill_in(0))
	# A pack a party body is standing in: its refill holds while he is that close,
	# so a walker never has bodies appear inside his own sight.
	var held: int = 3
	var held_pack: Array = wilderness.packs()[held]
	var held_at: Vector3 = (held_pack[0] as Node3D).home
	(held_pack[0] as Node).call("take_damage", 4000.0, 0)
	await create_timer(0.7).timeout
	target.global_position = held_at + Vector3(0.0, 0.0, WildernessScript.RESPAWN_QUIET * 0.5)
	check(wilderness.refill_pack(held) == 0,
		"a refill holds while a party body stands inside %.0f m"
			% WildernessScript.RESPAWN_QUIET)
	check(not bool((held_pack[0] as Node).get("alive")),
		"and the dead body is still the dead body")
	target.global_position = TARGET_POST
	var back: int = wilderness.refill_pack(cut)
	check(back == pack.size(), "the cut pack refills whole (%d of %d)"
		% [back, pack.size()])
	check(wilderness.wolves().size() == WildernessScript.PACK_COUNT,
		"the band is the same size it was (%d)" % wilderness.wolves().size())
	var revived := 0
	for index in pack.size():
		var wolf = wilderness.packs()[cut][index]
		if not is_instance_valid(wolf):
			continue
		if not bool(wolf.get("alive")):
			continue
		revived += 1
		check(str((wolf as Node).name) == names[index],
			"a body that came back takes the name it had (%s)"
				% str((wolf as Node).name))
		check(world.guards.has(wolf), "%s rejoins the world's hostile list" % wolf.name)
		check((wolf as Node3D).global_position.distance_to(posts[index]) < 0.6,
			"%s stands on its own post (%.2f m off)" % [wolf.name,
				(wolf as Node3D).global_position.distance_to(posts[index])])
		check((wolf as Node3D).home.distance_to(posts[index]) < 0.01,
			"%s has that post as home" % wolf.name)
		check(wolf.player == target, "%s aims at the standing body" % wolf.name)
	check(revived == pack.size(), "every body of the pack came back (%d)" % revived)
	check(wilderness.refill_pack(cut) == 0, "a second refill spawns nobody")

	# Only the dead are replaced: a pack that lost one body keeps the other two
	# exactly where they stand.
	var kept: int = wilderness.packs().size() - 2
	var kept_pack: Array = wilderness.packs()[kept]
	var kept_expected: int = (WildernessScript.PACKS[kept]["stations"] as Array).size()
	var survivor_one = kept_pack[1]
	var survivor_two = kept_pack[2]
	(kept_pack[0] as Node).call("take_damage", 4000.0, 0)
	await create_timer(0.7).timeout
	var kept_back: int = wilderness.refill_pack(kept)
	check(kept_back == 1, "only the fallen body comes back (%d)" % kept_back)
	check(wilderness.packs()[kept].size() == kept_expected,
		"the pack is the table's %d again (%d)"
			% [kept_expected, wilderness.packs()[kept].size()])
	check(wilderness.packs()[kept][1] == survivor_one
			and wilderness.packs()[kept][2] == survivor_two,
		"a body still on its feet is never teleported or respawned")

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
	# Under the whole band, not just its head: the lane packs stand up to 1,400 m
	# down the road, and a floor that ended at 700 m would leave half of them
	# falling for the whole run.
	box.size = Vector3(4000.0, 1.0, 4000.0)
	shape.shape = box
	floor_body.add_child(shape)
	world.add_child(floor_body)


## How far `point` stands from the lane a body walks, measured on the world's own
## offset and the lane's authored table: the rule every spawn has to keep.
func _lane_lateral(world, point: Vector3) -> float:
	var offset: Vector3 = world.trail_offset()
	var lane: Array = LaneScript.LANE_POINTS
	var at := Vector2(point.x, point.z)
	var best := INF
	for index in range(lane.size() - 1):
		var a: Vector3 = (lane[index] as Vector3) + offset
		var b: Vector3 = (lane[index + 1] as Vector3) + offset
		var bx := b.x - a.x
		var bz := b.z - a.z
		var length_squared := bx * bx + bz * bz
		var t := 0.0
		if length_squared > 0.000001:
			t = clampf(((at.x - a.x) * bx + (at.y - a.z) * bz) / length_squared, 0.0, 1.0)
		var cx := a.x + bx * t - at.x
		var cz := a.z + bz * t - at.y
		best = minf(best, sqrt(cx * cx + cz * cz))
	return best
