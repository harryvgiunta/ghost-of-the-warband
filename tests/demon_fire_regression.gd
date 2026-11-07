extends SceneTree
## The goatman's fire: the three casts the Hollow's demons throw, on their own
## cooldowns, through the victim's own `take_damage`.
##
## What this owns: the numbers in `demon_fire.gd`'s table; which spells the
## master and a keeper carry; a fireball that really flies (so it can be walked
## out of) and blasts for its damage on arrival; a breath that only burns what
## stands inside its cone; a patch that ticks, stops when the party steps out of
## it and frees itself; a stagger that takes the windup and the spell with it; a
## body already on the ground that fire will not finish; a replica that spawns
## nothing of its own; and the melee the boss already had - the same damage, reach
## and shut-window rule, unchanged beside the fire.

const DemonFireScript = preload("res://scripts/warband/demon_fire.gd")
const DemonScript = preload("res://scripts/warband/delve_demon.gd")
const DevilMob = preload("res://scripts/devil_mob.gd")

## Far outside the town's safe ring: nothing here is protected from a demon.
const SAFE_OFFSET := Vector3(2000.0, 0.0, 2000.0)
## The spells parked so a test sees only the one it armed.
const PARKED := 999.0
## How long a test waits for one thing to happen (frames at 60 Hz).
const WATCH_FRAMES := 240

var world_root: Node3D
var failures := 0
var checks := 0


## What a demon reads off a fighter: is it staggered, is it mid-swing, is its
## guard up. The test answers all three by hand.
class Guard extends RefCounted:
	var stagger_time := 0.0
	var blocking := false
	var progress := 1.0

	func melee_progress_for(_hand: String) -> float:
		return progress


## A body to burn. It answers `take_damage` exactly as a warband body does - but
## here every blow is recorded, so damage that arrived by the wrong road is
## visible.
class Target extends CharacterBody3D:
	var combat := Guard.new()
	var alive := true
	var downed := false
	var health := 100.0
	var hits: Array[float] = []
	var sources: Array[int] = []
	var attacker: Node3D

	func take_damage(amount: float, source_id: int, _headshot: bool = false) -> void:
		hits.append(amount)
		sources.append(source_id)
		health = maxf(0.0, health - amount)

	func note_attacker(who: Node3D) -> void:
		attacker = who

	func total() -> float:
		var sum := 0.0
		for hit in hits:
			sum += hit
		return sum


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("FIRE_FAIL  ", message)


func run() -> void:
	world_root = Node3D.new()
	world_root.name = "DemonFireTestWorld"
	root.add_child(world_root)
	_build_floor()
	_check_table()
	await _check_kits()
	await _check_range()
	await _check_fireball()
	await _check_downed()
	await _check_breath()
	await _check_embers()
	await _check_stagger()
	await _check_replica()
	await _check_melee_unchanged()
	print("DEMON_FIRE_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


# --- the table ------------------------------------------------------------

## Every number the kit fights on, stated once: a cast is only fair if its tell,
## its reach and its cooldown are the numbers the fight was tuned on.
func _check_table() -> void:
	var ball := DemonFireScript.spell("fireball")
	check(is_equal_approx(float(ball.get("damage", 0.0)), 18.0)
		and is_equal_approx(float(ball.get("speed", 0.0)), 12.0)
		and is_equal_approx(float(ball.get("radius", 0.0)), 1.6)
		and is_equal_approx(float(ball.get("cooldown", 0.0)), 9.0)
		and is_equal_approx(float(ball.get("windup", 0.0)), 0.7),
		"the fireball is 18 damage at 12 m/s in a 1.6 m blast, 0.7 s tell, 9 s clock")
	var breath := DemonFireScript.spell("hellfire_breath")
	check(is_equal_approx(float(breath.get("damage", 0.0)), 14.0)
		and is_equal_approx(float(breath.get("radius", 0.0)), 7.0)
		and is_equal_approx(float(breath.get("arc_degrees", 0.0)), 50.0)
		and is_equal_approx(float(breath.get("windup", 0.0)), 1.25)
		and is_equal_approx(float(breath.get("cooldown", 0.0)), 11.0),
		"hellfire is 14 damage through a 7 m 50 degree cone, 1.25 s tell, 11 s clock")
	var embers := DemonFireScript.spell("ember_rain")
	check(is_equal_approx(float(embers.get("damage", 0.0)), 6.0)
		and is_equal_approx(float(embers.get("tick", 0.0)), 0.6)
		and is_equal_approx(float(embers.get("duration", 0.0)), 3.0)
		and is_equal_approx(float(embers.get("radius", 0.0)), 2.6)
		and is_equal_approx(float(embers.get("windup", 0.0)), 1.2)
		and is_equal_approx(float(embers.get("cooldown", 0.0)), 14.0),
		"ember rain is 6 a tick every 0.6 s for 3 s in a 2.6 m patch, 1.2 s bloom, 14 s clock")
	check(int(DemonFireScript.DAMAGE_SOURCE) == 93,
		"fire is booked to the demon family, beside the watchers, the cultists and the wood")
	# The three shapes are the three the state machine knows how to resolve, and
	# each answers for its own reach.
	for spell_id in DemonFireScript.SPELLS.keys():
		var row: Dictionary = DemonFireScript.SPELLS[spell_id]
		check(str(row.get("shape", "")) in ["projectile", "cone", "hazard"],
			"%s is one of the three shapes a cast resolves" % spell_id)
		var reach := float(row.get("range", 0.0))
		check(DemonFireScript.in_range(row, reach - 0.5)
			and not DemonFireScript.in_range(row, reach + 0.5),
			"%s begins inside its %.0f m and never outside it" % [spell_id, reach])


# --- who throws what ------------------------------------------------------

## The master has the whole kit and a keeper the two that answer a party at range;
## a frontier demon has none at all, which is what makes this an addition.
func _check_kits() -> void:
	var keeper = _demon(false, Vector3(40.0, 0.05, 0.0))
	var kit: Array = keeper.fire_spells()
	check(kit.size() == 2 and kit.has("fireball") and kit.has("ember_rain"),
		"a keeper carries the fireball and the embers (%s)" % str(kit))
	keeper.queue_free()
	var plain = DevilMob.new()
	check(plain._fire_kit().is_empty(), "a frontier demon carries no fire")
	plain.free()
	await physics_frame


# --- the fireball ---------------------------------------------------------

## Out of range is no cast: the fireball's 16 m is the demon's own reach for it,
## however long it can see.
func _check_range() -> void:
	var target := _target(Vector3(0.0, 0.0, -24.0))
	var mob = _demon(true, Vector3(0.0, 0.05, 0.0), target)
	_arm(mob, "fireball")
	for frame in 90:
		await physics_frame
	check(not mob.casting(),
		"a target 24 m off is outside the fireball's 16 m and no cast begins")
	check(target.hits.is_empty(), "and nothing is thrown at it")
	mob.queue_free()
	target.queue_free()
	await physics_frame


## It winds up, it really flies, and it blasts the point it was loosed at.
func _check_fireball() -> void:
	var target := _target(Vector3(0.0, 0.0, -8.0))
	var mob = _demon(true, Vector3(0.0, 0.05, 0.0), target)
	var kit: Array = mob.fire_spells()
	check(kit.size() == 3 and kit.has("hellfire_breath"),
		"the master carries the whole kit (%s)" % str(kit))
	_arm(mob, "fireball")
	check(await _wait_until(func() -> bool: return mob.casting(), WATCH_FRAMES),
		"a fireball winds up at a target inside its range")
	check(mob.fire_cooldown("fireball") > 8.0,
		"and the spell is spent as the tell begins (%.2f s)" % mob.fire_cooldown("fireball"))
	check(target.hits.is_empty(), "the tell itself lands nothing")
	check(await _wait_until(func() -> bool: return is_instance_valid(mob._cast_missile),
			WATCH_FRAMES), "the windup ends in a fireball in the air")
	var shot = mob._cast_missile
	check(is_equal_approx(shot.velocity.length(), 12.0),
		"it flies at 12 m/s (%.2f)" % shot.velocity.length())
	check(target.hits.is_empty(), "and nothing has been hurt while it is still in the air")
	check(await _wait_until(func() -> bool: return not target.hits.is_empty(),
			WATCH_FRAMES), "the blast arrives at the target")
	check(is_equal_approx(target.total(), 18.0),
		"and takes the fireball's 18 damage (%.2f)" % target.total())
	check(not target.sources.is_empty()
		and int(target.sources[0]) == DemonFireScript.DAMAGE_SOURCE,
		"the blow is booked to the demon family, through `take_damage`")
	check(target.attacker == mob, "the body knows what burned it")
	for frame in 3:
		await physics_frame
	check(not is_instance_valid(shot), "the projectile frees itself once it has landed")
	mob.queue_free()
	target.queue_free()
	await physics_frame


# --- a body already down --------------------------------------------------

## Fire is routed like the melee blow the scene books: a body on the ground is out
## of the fight, so the blaze burns nothing of it and cannot finish it.
func _check_downed() -> void:
	var target := _target(Vector3(0.0, 0.0, -6.0))
	target.downed = true
	var mob = _demon(true, Vector3(0.0, 0.05, 0.0), target)
	_arm(mob, "fireball")
	check(await _wait_until(func() -> bool: return mob.casting(), WATCH_FRAMES),
		"a fireball still winds up at a body on the ground")
	for frame in 120:
		await physics_frame
	check(target.hits.is_empty(), "and fire never finishes a body that is already down")
	check(not is_instance_valid(mob._cast_missile), "the shot lands and clears itself")
	mob.queue_free()
	target.queue_free()
	await physics_frame


# --- the breath -----------------------------------------------------------

## The cone burns what stands in it and nothing else - not the body at its side,
## not the one behind.
func _check_breath() -> void:
	var front := _target(Vector3(0.0, 0.0, -4.0))
	var side := _target(Vector3(5.0, 0.0, -1.0))
	var behind := _target(Vector3(0.0, 0.0, 3.0))
	var mob = _demon(true, Vector3(0.0, 0.05, 0.0), front)
	mob.targets.append(side)
	mob.targets.append(behind)
	_arm(mob, "hellfire_breath")
	check(await _wait_until(func() -> bool: return mob.casting(), WATCH_FRAMES),
		"the breath winds up at a body on the cone's line")
	check(front.hits.is_empty(), "the rear-back lands nothing by itself")
	check(await _wait_until(func() -> bool: return not front.hits.is_empty(),
			WATCH_FRAMES), "the cone burns the body in front of it")
	check(is_equal_approx(front.total(), 14.0),
		"for the breath's 14 damage (%.2f)" % front.total())
	for frame in 4:
		await physics_frame
	check(side.hits.is_empty(), "a body off to the side of the cone is untouched")
	check(behind.hits.is_empty(), "and a body behind the demon is untouched")
	check(not mob.casting(), "the cast resolves at the end of its windup")
	mob.queue_free()
	front.queue_free()
	side.queue_free()
	behind.queue_free()
	await physics_frame


# --- the embers -----------------------------------------------------------

## The ground blooms where the target stood, ticks, stops the moment the party
## steps out of it, and frees itself when its clock runs out.
func _check_embers() -> void:
	var target := _target(Vector3(0.0, 0.0, -6.0))
	var mob = _demon(true, Vector3(0.0, 0.05, 0.0), target)
	_arm(mob, "ember_rain")
	check(await _wait_until(func() -> bool: return mob.casting(), WATCH_FRAMES),
		"ember rain winds up with a hand raised")
	check(target.hits.is_empty(), "the bloom delay lands nothing by itself")
	check(await _wait_until(func() -> bool: return is_instance_valid(mob._hazard),
			WATCH_FRAMES), "the patch blooms when the delay runs out")
	var patch = mob._hazard
	check(Vector2(patch.global_position.x - target.global_position.x,
		patch.global_position.z - target.global_position.z).length() < 0.01,
		"it blooms on the ground the target stood on")
	check(await _wait_until(func() -> bool: return target.hits.size() >= 3,
			WATCH_FRAMES), "the patch ticks its damage while the body stands in it")
	for hit in target.hits:
		check(is_equal_approx(hit, 6.0), "every tick is the patch's 6 damage (%.2f)" % hit)
	# Walk out of it: this is the one the party can leave.
	target.position = Vector3(0.0, 0.0, 4.0)
	# Two frames for any tick already in this frame's queue to land at the old
	# ground, then nothing more may burn anybody.
	for frame in 2:
		await physics_frame
	var mark := target.hits.size()
	for frame in 40:
		await physics_frame
	check(target.hits.size() == mark,
		"a body that walks out of the patch stops burning (%d -> %d)"
		% [mark, target.hits.size()])
	check(await _wait_until(func() -> bool: return not is_instance_valid(patch), 400),
		"the patch frees itself when its clock runs out")
	check(not is_instance_valid(mob._hazard), "and the demon keeps no orphan of it")
	mob.queue_free()
	target.queue_free()
	await physics_frame


# --- the interrupt --------------------------------------------------------

## A stagger takes the windup, the spell and the fire with it, for each of the
## three casts.
func _check_stagger() -> void:
	var target := _target(Vector3(0.0, 0.0, -6.0))
	var mob = _demon(true, Vector3(0.0, 0.05, 0.0), target)
	for spell_id in ["fireball", "hellfire_breath", "ember_rain"]:
		_arm(mob, spell_id)
		check(await _wait_until(func() -> bool: return mob.casting(), WATCH_FRAMES),
			"%s winds up before it is staggered" % spell_id)
		mob.stagger(2.0)
		check(not mob.casting(), "a stagger drops the %s windup" % spell_id)
		check(mob.fire_cooldown(spell_id) > 1.0,
			"and the %s stays spent (%.2f s)" % [spell_id, mob.fire_cooldown(spell_id)])
		for frame in 30:
			await physics_frame
		check(not mob.casting(), "and no new %s begins while the body is staggered" % spell_id)
		check(target.hits.is_empty(), "an interrupted %s never lands" % spell_id)
		check(mob._cast_missile == null and mob._hazard == null,
			"nothing is spawned by an interrupted %s" % spell_id)
		check(await _wait_until(func() -> bool: return str(mob.state) == "CIRCLE",
				WATCH_FRAMES), "the body comes back out of the stagger")
	mob.queue_free()
	target.queue_free()
	await physics_frame


# --- the replica ----------------------------------------------------------

## A guest's copy is a drawing of the host's demon: it never winds a cast up and
## never spawns a fireball or a patch of its own.
func _check_replica() -> void:
	var target := _target(Vector3(0.0, 0.0, -6.0))
	var mob = _demon(true, Vector3(0.0, 0.05, 0.0), target)
	mob.mark_replica()
	_arm(mob, "fireball")
	for frame in 120:
		await physics_frame
	check(not mob.casting(), "a replica never winds a cast up")
	check(mob._cast_missile == null and mob._hazard == null,
		"and spawns neither a fireball nor a burning patch")
	check(target.hits.is_empty(), "so nothing burns on the guest's machine")
	check(mob.fire_cooldown("fireball") <= 0.0, "its spells are the host's to spend")
	mob.queue_free()
	target.queue_free()
	await physics_frame


# --- the melee it already had --------------------------------------------

## The fire is an addition: the master's blow, its pool and its ladder are the
## numbers they were, and a target that offers no window still buys no swing.
func _check_melee_unchanged() -> void:
	var target := _target(Vector3(0.0, 0.0, -2.2))
	var mob = _demon(true, Vector3(0.0, 0.05, 0.0), target)
	var blows: Array = []
	mob.attacked.connect(func(_attacker, amount, _victim) -> void: blows.append(amount))
	# Every spell parked: what is left is the fight the demon already had.
	_arm(mob, "")
	check(is_equal_approx(float(mob.profile.damage), 21.0),
		"the master's blow is still 21 (%.2f)" % float(mob.profile.damage))
	check(is_equal_approx(float(mob.profile.reach), 2.35),
		"its reach is still 2.35 m (%.2f)" % float(mob.profile.reach))
	check(is_equal_approx(mob.max_health, 400.0),
		"its pool is still 400 (%.2f)" % mob.max_health)
	check(int(mob.profile.gold) == 60, "and its prize is still 60 gold")
	check(bool(mob.duelist) and mob._duel != null, "it still fights the duel ladder")
	check(is_equal_approx(mob._windup_seconds(), float(mob.profile.windup)),
		"on the profile's own telegraph (%.2f s)" % mob._windup_seconds())
	var swings := 0
	var previous := ""
	for frame in 180:
		await physics_frame
		if str(mob.state) == "WINDUP" and previous != "WINDUP":
			swings += 1
		previous = str(mob.state)
	check(swings == 0, "a shut window still buys it no swing (%d)" % swings)
	check(not mob.casting() and mob._hazard == null,
		"and a spent kit throws nothing")
	# The window opens: the blow is the profile's own damage, unchanged.
	target.combat.stagger_time = 60.0
	check(await _wait_until(func() -> bool: return not blows.is_empty(), 400),
		"an open window takes the master's blow")
	check(is_equal_approx(float(blows[0]), 21.0),
		"for its 21 damage (%.2f)" % float(blows[0]))
	mob.queue_free()
	target.queue_free()
	await physics_frame


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


## One of the Hollow's demons (`delve_demon.gd`), built by hand: the master when
## `boss`, a keeper otherwise. A target passed here is the local ranger.
func _demon(boss: bool, at: Vector3, target: Node3D = null):
	var mob = DemonScript.new()
	mob.boss = boss
	mob.player = target
	mob.safe_center = SAFE_OFFSET
	mob.position = at
	world_root.add_child(mob)
	return mob


## Only the named spell is off cooldown. `""` parks the whole kit.
func _arm(mob, spell_id: String) -> void:
	for id in mob.fire_spells():
		mob._fire_cooldowns[id] = 0.0 if id == spell_id else PARKED


## Frame-waits until `test` answers true, at most `frames` of them.
func _wait_until(test: Callable, frames: int) -> bool:
	for frame in frames:
		if bool(test.call()):
			return true
		await physics_frame
	return false
