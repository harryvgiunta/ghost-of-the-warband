extends SceneTree
## The demons' duel: the Hollow's master and keepers, and the deep wood's Horned
## Thing, fight a ladder instead of grinding.
##
## What this owns: a duelist guards on its temper's share and refuses to swing
## into a target that is not open, and commits the moment one is; a body that is
## not a duelist keeps the walk-into-reach loop and trades blows on its cooldown
## whatever the target is doing; and the arena's three foes are driven by the same
## ladder (`duel_brain.gd`), still on the three tiers' own numbers.

const DuelBrainScript = preload("res://scripts/warband/duel_brain.gd")
const DevilMob = preload("res://scripts/devil_mob.gd")
const ArenaArea = preload("res://scripts/warband/arena_area.gd")

## Far outside the town's safe ring: nothing here is protected from a demon.
const SAFE_OFFSET := Vector3(2000.0, 0.0, 2000.0)
## Physics frames one phase of a fight is watched for.
const WATCH_FRAMES := 300

var world_root: Node3D
var failures := 0
var checks := 0


## What a demon reads off a fighter it is fighting: is it staggered, is it
## mid-swing, and is its guard up. The test answers all three by hand.
class Guard extends RefCounted:
	var stagger_time := 0.0
	var blocking := false
	var progress := 1.0

	func melee_progress_for(_hand: String) -> float:
		return progress


class Target extends CharacterBody3D:
	var combat := Guard.new()
	var alive := true


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("DUEL_FAIL  ", message)


func run() -> void:
	world_root = Node3D.new()
	world_root.name = "DuelTestWorld"
	root.add_child(world_root)
	_build_floor()
	_check_ladder()
	await _check_duelist()
	await _check_grinder()
	_check_arena_uses_the_ladder()
	print("DEMON_DUEL_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


# --- the ladder on its own -------------------------------------------------

## The brain is a decision function, so its rules are asked directly: what a
## temper that fights into openings does with a shut target, and what a fighter
## with a guard of its own offers as a window.
func _check_ladder() -> void:
	seed(20261106)
	var duel := {"guard": 0.0, "beat": 0.0, "step": 0.0, "lead": 0.0,
		"range": 2.0, "pad": 0.0, "window": true}
	var brain = DuelBrainScript.new()
	var answer: Dictionary = brain.tick(0.05, duel, {
		"position": Vector3.ZERO, "target": Vector3(0.0, 0.0, -2.0),
		"ready": true, "target_open": false,
	})
	check(str(answer["swing"]).is_empty(), "a temper that fights into openings never swings into a shut one")
	check(bool(answer["guard"]), "it holds its guard instead")
	answer = brain.tick(0.05, duel, {
		"position": Vector3.ZERO, "target": Vector3(0.0, 0.0, -2.0),
		"ready": true, "target_open": true,
	})
	check(not str(answer["swing"]).is_empty(), "and commits the tick the target is open")

	# A target's windows: staggered, mid-follow-through, or a guard just spent.
	var guard := Guard.new()
	check(not brain.observe(guard), "a standing target in no trouble is not open")
	guard.stagger_time = 0.5
	check(brain.observe(guard), "a staggered target is open")
	guard.stagger_time = 0.0
	guard.progress = 0.8
	check(brain.observe(guard), "a target in its follow-through is open")
	guard.progress = 1.0
	guard.blocking = true
	brain.observe(guard)
	guard.blocking = false
	check(brain.observe(guard), "a guard that has just been spent is open")
	# Lead is what makes a moving target a closing problem at the range it will be
	# at, not the one it is at now.
	var leading = DuelBrainScript.new()
	answer = leading.tick(0.0, {"guard": 0.0, "beat": 0.0, "step": 0.0, "lead": 0.5,
		"range": 2.0, "pad": 0.0}, {
		"position": Vector3.ZERO, "target": Vector3(0.0, 0.0, -3.0),
		"target_velocity": Vector3(0.0, 0.0, -8.0), "ready": false,
	})
	check(bool(answer["run"]), "a body aims at where a moving target is going")


# --- a duelist ------------------------------------------------------------

## With a live target that offers nothing, a duelist circles and guards - and
## never swings, however long its cooldown has been up. The moment the target is
## staggered, it commits, on the profile's own tell.
func _check_duelist() -> void:
	seed(424242)
	var target := _target(Vector3(0.0, 0.0, -6.0))
	var mob = _demon("hell_goat", Vector3(0.0, 0.05, 0.0), target, true)
	check(bool(mob.duelist), "a body told it is a duelist fights the ladder")
	check(mob._duel != null, "and builds one")
	check(bool(mob.guard_between_swings), "so a raised guard is what a blow lands on")
	var start: Vector3 = mob.global_position
	var swings := 0
	var guarded := 0
	var posed := 0
	var ready := 0
	var previous := ""
	for frame in WATCH_FRAMES:
		await physics_frame
		if not is_instance_valid(mob):
			break
		if mob.guard_up():
			guarded += 1
		if mob._present_blocking():
			posed += 1
		if float(mob._attack_cooldown) <= 0.0 and str(mob.state) == "CIRCLE":
			ready += 1
		if str(mob.state) == "WINDUP" and previous != "WINDUP":
			swings += 1
		previous = str(mob.state)
	check(guarded > 0, "a duelist guards while its target is not open (%d frames)" % guarded)
	check(posed > 0, "and the guard is a stance the eye reads (%d frames)" % posed)
	check(ready > 30, "its own cooldown was up for most of that (%d frames)" % ready)
	check(swings == 0, "and it never swung into a shut window (%d swings)" % swings)
	check(mob.global_position.distance_to(start) > 0.5,
		"it closed on the target rather than standing (%.2f m)" % mob.global_position.distance_to(start))

	# The target is staggered: that is a window, and the demon takes it.
	target.combat.stagger_time = 60.0
	var committed := 0
	previous = str(mob.state)
	for frame in WATCH_FRAMES * 2:
		await physics_frame
		if not is_instance_valid(mob):
			break
		if str(mob.state) == "WINDUP" and previous != "WINDUP":
			committed += 1
		previous = str(mob.state)
		if committed > 0:
			break
	check(committed > 0, "the moment the target is open the duelist commits")
	# The brain never touched the blow: the telegraph is the profile's.
	check(is_equal_approx(mob._windup_seconds(), float(mob.profile.windup)),
		"the windup it answers with is the profile's own (%.2f s)" % mob._windup_seconds())
	mob.queue_free()
	target.queue_free()
	await physics_frame


# --- a body that grinds ---------------------------------------------------

## The same target, offering nothing at all, against a body that is not a
## duelist: it walks into reach and swings, which is the fight the frontier and
## every watcher keep.
func _check_grinder() -> void:
	seed(777)
	var target := _target(Vector3(0.0, 0.0, -6.0))
	var mob = _demon("hell_goat", Vector3(0.0, 0.05, 0.0), target, false)
	check(not bool(mob.duelist), "a body that was not told is not a duelist")
	check(mob._duel == null, "and builds no ladder")
	var swings := 0
	var previous := ""
	for frame in WATCH_FRAMES * 2:
		await physics_frame
		if not is_instance_valid(mob):
			break
		if str(mob.state) == "WINDUP" and previous != "WINDUP":
			swings += 1
		previous = str(mob.state)
		if swings > 0:
			break
	check(swings > 0, "a body that grinds still walks in and swings at a shut window")
	check(mob.global_position.distance_to(target.global_position) < 4.0,
		"and it is inside its reach when it does (%.2f m)"
		% mob.global_position.distance_to(target.global_position))
	mob.queue_free()
	target.queue_free()
	await physics_frame


# --- the arena ------------------------------------------------------------

## The ring's three foes are driven by the extracted brain, and the ladder still
## fights on each tier's own temper.
func _check_arena_uses_the_ladder() -> void:
	# `get_script_constant_map` is a `Script` method and answers on the resource,
	# never on the class: the arena's script is held as a plain value and asked at
	# run time, so nothing here reads a member of the arena's own class.
	var arena_script: Variant = ArenaArea
	var consts: Dictionary = arena_script.get_script_constant_map()
	var wired = consts.get("DuelBrainScript")
	check(wired == DuelBrainScript,
		"the ring builds every foe's brain from this ladder, not a copy of it")
	var tiers: Dictionary = consts.get("TEMPER", {})
	check(tiers.size() == 3, "the ring still fights on three tiers (%d)" % tiers.size())
	for tier in ["easy", "medium", "hard"]:
		var temper: Dictionary = tiers.get(tier, {})
		check(float(temper.get("range", 0.0)) > 0.0, "the %s tier carries its own range" % tier)
		var brain = DuelBrainScript.new()
		var swung := 0
		for step in 400:
			var answer: Dictionary = brain.tick(0.05, temper, {
				"position": Vector3.ZERO, "target": Vector3(0.0, 0.0, -1.4),
				"weapon": "sword", "ready": true,
			})
			if not str(answer["swing"]).is_empty():
				swung += 1
				break
		check(swung > 0, "a %s foe still takes the blow once it is in reach" % tier)


# --- the test world -------------------------------------------------------

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(shape)
	world_root.add_child(body)


func _target(at: Vector3) -> Target:
	var body := Target.new()
	body.collision_layer = 4
	body.collision_mask = 0
	body.position = at
	world_root.add_child(body)
	return body


func _demon(mob_id: String, at: Vector3, target: Node3D, duelist: bool):
	var mob = DevilMob.new()
	mob.mob_id = mob_id
	mob.duelist = duelist
	mob.player = target
	mob.safe_center = SAFE_OFFSET
	mob.position = at
	world_root.add_child(mob)
	return mob
