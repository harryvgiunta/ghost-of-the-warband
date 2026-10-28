extends SceneTree
## wt-10 regression: the cultist faction, the expedition waves, and the visible
## soldier loot run - all on real bodies in a real arena field.
##
## Nothing here calls a library in isolation. The guards are spawned by
## `EnemyWaves` into the same world the warband's bodies stand in, the melee
## damage is the arena's own sweep, and the loot merely asks `WarbandLoot` to
## book the pieces the soldiers physically walked to.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Damage = preload("res://scripts/warband/damage_scaler.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const StateScript = preload("res://scripts/player_state.gd")
const WorldScript = preload("res://scripts/arena_world.gd")
const ControllerScript = preload("res://scripts/warband/possession_controller.gd")
const WavesScript = preload("res://scripts/warband/enemy_waves.gd")
const LootScript = preload("res://scripts/warband/loot_vacuum.gd")
const LootRunScript = preload("res://scripts/warband/soldier_loot_run.gd")
const GuardScript = preload("res://scripts/warband/cultist_guard.gd")
const ArrowScript = preload("res://scripts/arrow.gd")

const TEST_SAVE := "user://enemy_waves_state.json"
const WARBAND_SAVE := "user://enemy_waves_warband.json"
const STEP := 1.0 / 60.0
## Open ground: every cover box and arena tree is more than four metres away.
const FIGHT_POINT := Vector3(0.0, 0.0, 0.0)
## Where the rest of the pack waits while one guard is measured against a body:
## twenty-nine metres off, five or more seconds of walking.
const PARK_POINT := Vector3(24.0, 0.0, 16.0)
## Where the warband bodies wait, far from the fight point and clear of the
## arena's trees (the nearest trunk stands at 0, 0, 27).
const BODY_POSTS := [Vector3(4.0, 0.0, 26.0), Vector3(8.0, 0.0, 26.0), Vector3(1.0, 0.0, 26.0)]
## The wave's ring: eighteen metres out, between the cover boxes (nearest is
## five metres) and clear of the arena's trees.
const WAVE_SPAWNS: Array[Vector3] = [
	Vector3(15.6, 0.0, 9.0), Vector3(0.0, 0.0, 18.0), Vector3(-15.6, 0.0, 9.0),
	Vector3(-15.6, 0.0, -9.0), Vector3(0.0, 0.0, -18.0), Vector3(15.6, 0.0, -9.0),
]
## Three line troops: a swordsman, a knifeman and an archer, all in leather.
const LINEUP := [
	["Aldous", "sword_short"], ["Brine", "dagger_iron"], ["Cael", "bow_short"],
]
const LOOT_RUN_POSTS := [Vector3(4.0, 0.0, 10.0), Vector3(-4.0, 0.0, 10.0), Vector3(0.0, 0.0, 13.0)]
const LOOT_DROPS := [["sword_arming", Vector3(5.5, 0.0, 10.0)], ["shield_kite", Vector3(-5.5, 0.0, 10.0)]]

var state
var warband
var checks := 0
var failures := 0

var _field: Node3D
var _camera: Camera3D
var _controller
var _waves
var _loot
var _loot_run
var _bodies: Array = []
## Signal traffic, recorded so a test reads what a scene would listen to.
var _started: Array = []
var _cleared: Array = []
var _finished: Array = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("ENEMY_WAVES_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func run() -> void:
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	Damage.reset()
	_seed_warband()
	_build_scene()
	await create_timer(0.3).timeout

	check_wave_one()
	var second: Array = check_wave_two()
	check_cult_tint(second)
	await check_hostile_melee(second)
	await check_cult_archer()
	await check_soldier_loot_run()

	_field.queue_free()
	await process_frame
	Damage.reset()
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("ENEMY_WAVES_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

# --- scene -----------------------------------------------------------------

func _seed_warband() -> void:
	for entry in LINEUP:
		var merc_id: int = warband.add_mercenary(str(entry[0]))
		warband.roster.equip(merc_id, "main", str(entry[1]))
		for slot in ArmorData.SLOTS:
			warband.roster.equip(merc_id, slot, "armor_leather_%s" % slot)

func _build_scene() -> void:
	_field = Node3D.new()
	_field.name = "Field"
	root.add_child(_field)
	var world = WorldScript.new()
	world.name = "Arena"
	_field.add_child(world)
	_camera = Camera3D.new()
	_camera.name = "FieldCamera"
	_camera.fov = 59
	_camera.far = 180.0
	_field.add_child(_camera)
	_camera.position = Vector3(0.0, 16.0, 26.0)
	_camera.look_at(Vector3(0.0, 1.0, 0.0))
	_camera.current = true
	_controller = ControllerScript.new()
	_controller.name = "Soul"
	_controller.auto_simulate = false
	_field.add_child(_controller)
	_controller.setup(warband, _camera, _field)
	_bodies = _controller.spawn_mercenaries(_posts(), true)
	# The bodies are dummies for this test: their own bot AI is off, so every hit
	# below comes from the cult and every position change from the loot run.
	for body in _bodies:
		_controller.set_bot(_controller.merc_of(body), false)
	_waves = WavesScript.new()
	_waves.name = "Waves"
	_field.add_child(_waves)
	_waves.setup(_controller, _field, WAVE_SPAWNS, Callable(self, "_warband_bodies"))
	_waves.wave_started.connect(func(index: int, count: int) -> void:
		_started.append([index, count]))
	_waves.wave_cleared.connect(func(index: int) -> void: _cleared.append(index))
	_loot = LootScript.new()
	_loot.name = "Loot"
	_field.add_child(_loot)
	_loot.setup(warband, _field)
	_loot_run = LootRunScript.new()
	_loot_run.name = "SoldierLootRun"
	_field.add_child(_loot_run)
	_loot_run.finished.connect(func(collected: int) -> void: _finished.append(collected))

func _posts() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for post in BODY_POSTS:
		out.append(post)
	return out

## The provider a scene hands the waves: the warband bodies the cult is here to
## kill. It is what a step with no explicit body list falls back to.
func _warband_bodies() -> Array:
	return _bodies

# --- wave 1 ----------------------------------------------------------------

func check_wave_one() -> void:
	check(warband.roster.count() == 3, "three mercenaries field for the test")
	check(_bodies.size() == 3, "three real warband bodies exist")
	_started.clear()
	_cleared.clear()
	var guards: Array = _waves.start_wave(0)
	check(guards.size() == 3, "wave 1 fields three guards, got %d" % guards.size())
	check(_waves.wave() == 0, "the wave index is reported")
	check(_waves.living() == 3, "three guards are on their feet, got %d" % _waves.living())
	check(_started.size() == 1 and int(_started[0][0]) == 0 and int(_started[0][1]) == 3,
		"wave_started names the wave and its count, got %s" % str(_started))

	var posts: Array = []
	for index in guards.size():
		var guard = guards[index]
		check(guard is CultistGuard, "the wave fields a real CultistGuard body")
		check(guard.alive and not guard.downed, "the guard is on its feet")
		check(guard.authoritative, "the guard is simulated, not a replica")
		check(guard.is_bot, "the guard thinks for itself")
		check(guard.combat.damage_enabled, "the guard can land a blow")
		check(guard.faction == GuardScript.FACTION, "the guard carries the cult faction tag")
		check(guard.get_parent() == _field, "the guard stands in the scene")
		var main_id := str(guard.kit.get("main", ""))
		check(main_id.begins_with("dagger_"), "the first wave carries cult knives, got %s" % main_id)
		check(StateScript.ITEMS.has(main_id), "the main hand is real catalog gear")
		check(str(guard.kit.get("armor", "")) == "makeshift", "the first wave wears salvage")
		var salvaged: int = ArmorData.SET_IDS.find("makeshift")
		check(int(guard.rig.armor_pieces.get("chest", ArmorData.NONE)) == salvaged,
			"the salvage cuirass reaches the rig")
		check(guard.rig.weapon == "dagger", "the rig holds the knife, got %s" % guard.rig.weapon)
		check(guard.display_name in GuardScript.NAMES, "the guard wears a cult name")
		posts.append(guard.global_position)
		check(guard.global_position.distance_to(WAVE_SPAWNS[index]) < 1.0,
			"guard %d stands on its own spawn point" % index)

	var distinct := true
	for i in posts.size():
		for j in range(i + 1, posts.size()):
			if (posts[i] as Vector3).distance_to(posts[j]) < 1.0:
				distinct = false
	check(distinct, "no two guards share a spawn point")

	var before: int = _waves.total_cleared()
	for guard in guards:
		guard.take_damage(1000.0, 7)
	check(_waves.living() == 0, "killing the wave leaves nobody standing")
	check(_waves.total_cleared() == before + 3, "every kill is tallied, got %d" % _waves.total_cleared())
	check(_cleared.size() == 1 and int(_cleared[0]) == 0,
		"killing the last guard clears wave 0, got %s" % str(_cleared))

	# A blow on a corpse is not a second kill.
	guards[0].take_damage(1000.0, 7)
	check(_waves.total_cleared() == before + 3, "a dead guard is counted once")
	check(_cleared.size() == 1, "a dead wave is not cleared twice")

# --- wave 2 ----------------------------------------------------------------

func check_wave_two() -> Array:
	_started.clear()
	var guards: Array = _waves.start_wave(1)
	check(guards.size() == 4, "wave 2 fields four guards, got %d" % guards.size())
	check(_waves.wave() == 1, "the wave index advanced")
	check(_waves.living() == 4, "four guards are on their feet, got %d" % _waves.living())
	check(_started.size() == 1 and int(_started[0][1]) == 4,
		"wave_started reports the bigger wave, got %s" % str(_started))
	check(_waves.total_cleared() == 3, "the cleared tally survives the new wave")

	# The whole cult is the salvage tier: a mob with a smithed arming sword was a
	# knight in rags, and a knight's blade off a cultist corpse out-valued the
	# battle. A later wave is more bodies and better salvage, never forged steel.
	var salvage := 0
	var makeshifts := 0
	var tier := ["dagger_ironwood", "club_makeshift", "branch_heavy", "bow_twig"]
	for guard in guards:
		var main_id := str(guard.kit.get("main", ""))
		check(StateScript.ITEMS.has(main_id), "wave 2 gear is catalog gear, got %s" % main_id)
		if main_id in tier:
			salvage += 1
		if str(guard.kit.get("armor", "")) == "makeshift":
			makeshifts += 1
		check(int(guard.rig.armor_pieces.get("chest", ArmorData.NONE))
			== ArmorData.SET_IDS.find("makeshift"),
			"wave 2 wears salvage on the rig")
	check(salvage == guards.size(), "wave 2 carries only the salvage tier, got %d" % salvage)
	check(makeshifts == guards.size(), "and wears the salvage it cut for itself")
	check(guards.size() > 3, "the second wave is measurably bigger than the first")

	# Determinism: the same index rolls the same kits, on any run.
	var first_kits := _kits_of(guards)
	var again: Array = _waves.start_wave(1)
	check(_kits_of(again) == first_kits, "the same wave index rolls the same kits")
	check(again.size() == 4, "the re-rolled wave is the same size")
	return again

func _kits_of(guards: Array) -> Array[String]:
	var out: Array[String] = []
	for guard in guards:
		out.append("%s|%s|%s|%s" % [guard.display_name, guard.kit.get("main", ""),
			guard.kit.get("off", ""), guard.kit.get("armor", "")])
	return out

# --- the crimson kit --------------------------------------------------------

func check_cult_tint(guards: Array) -> void:
	var guard = guards[0]
	check(guard.cult_material != null, "the guard built its cult material")
	var meshes: Array = guard.rig.find_children("*", "MeshInstance3D", true, false)
	var painted := 0
	for node in meshes:
		if (node as MeshInstance3D).material_override == guard.cult_material:
			painted += 1
	check(meshes.size() >= 5, "the guard's rig has real meshes, got %d" % meshes.size())
	check(painted == meshes.size(),
		"every mesh on the guard wears the cult paint (%d of %d)" % [painted, meshes.size()])
	check(guard.cult_material.albedo_color.is_equal_approx(CultistGuard.TINT),
		"the paint is the cult crimson")
	check(CultistGuard.TINT.r > CultistGuard.TINT.g * 4.0 and CultistGuard.TINT.r < 0.4,
		"the cult crimson is dark blood, not a player colour")

	var body_meshes: Array = _bodies[0].rig.find_children("*", "MeshInstance3D", true, false)
	check(not body_meshes.is_empty(), "the warband body has a rig to compare against")
	if body_meshes.is_empty():
		return
	var body_mesh := body_meshes[0] as MeshInstance3D
	check(body_mesh.material_override != guard.cult_material,
		"the cult paint never leaks onto a warband body")
	var source := body_mesh.get_active_material(0)
	if source is StandardMaterial3D:
		check(not (source as StandardMaterial3D).albedo_color.is_equal_approx(CultistGuard.TINT),
			"the warband's own albedo is untouched")

# --- hostility --------------------------------------------------------------

func check_hostile_melee(guards: Array) -> void:
	var guard = guards[0]
	var body = _bodies[0]
	body.global_position = FIGHT_POINT + Vector3(0.0, 0.1, 0.0)
	# Only the guard under test is near the body. The rest of the pack waits on
	# the far side of the yard: they are three seconds of walking away, so this
	# window measures one cultist against one body rather than a crowd shoving
	# each other off it.
	for index in range(1, guards.size()):
		guards[index].teleport_to(PARK_POINT + Vector3(2.0 * float(index), 0.1, 0.0), 0.0)
	var parked: Array = []
	for index in range(1, guards.size()):
		parked.append([guards[index], float(guards[index].health)])
	# The pair the arena has to fight with: the guard is given the whole field by
	# `waves.step`, and the cult faction filter leaves only the body as a target.
	guard.teleport_to(FIGHT_POINT + Vector3(1.5, 0.1, 0.0), 0.0)
	var before: float = body.health
	var guard_before: float = guard.health
	var ticks := 0
	# Three seconds of the documented call order: the cult first, the warband
	# after it.
	for tick in 180:
		await physics_frame
		_waves.step(STEP, _bodies)
		_controller.physics_step(STEP)
		ticks += 1
	check(ticks == 180, "the field ran three seconds of ticks")
	check(body.health < before - 5.0,
		"a guard 1.5 m away takes health off a body (%.1f -> %.1f)" % [before, body.health])
	check(guard.health <= guard_before,
		"the guard took no blow from its own pack (%.1f -> %.1f)" % [guard_before, guard.health])
	check(is_instance_valid(guard) and guard.global_position.distance_to(body.global_position) < 6.0,
		"the guard stayed in the fight instead of wandering")
	var untouched := true
	for entry in parked:
		if not is_instance_valid(entry[0]) or not is_equal_approx(float(entry[0].health), float(entry[1])):
			untouched = false
	check(untouched, "the cult never cut its own pack")
	check(_waves.living() > 0, "the wave is still standing after the exchange")

# --- the cult archer --------------------------------------------------------

## The bow tier has to put real shafts in the air: a cultist archer draws, the
## waves spawn the arena's arrow, and the body across the yard loses health.
func check_cult_archer() -> void:
	var guards: Array = _waves.start_wave(2)
	check(guards.size() == 5, "wave 3 fields five guards, got %d" % guards.size())
	var archer = null
	for guard in guards:
		if str(guard.kit.get("main", "")).begins_with("bow"):
			archer = guard
			break
	check(archer != null, "the bow tier really fields an archer")
	if archer == null:
		return
	var body = _bodies[0]
	body.revive()
	body.global_position = FIGHT_POINT + Vector3(0.0, 0.1, 0.0)
	for index in guards.size():
		if guards[index] != archer:
			guards[index].teleport_to(PARK_POINT + Vector3(2.0 * float(index), 0.1, 0.0), 0.0)
	archer.teleport_to(FIGHT_POINT + Vector3(12.0, 0.1, 0.0), 0.0)
	var before: float = body.health
	var arrows := 0
	for tick in 240:
		await physics_frame
		_waves.step(STEP, _bodies)
		_controller.physics_step(STEP)
		var live := 0
		for child in _field.get_children():
			if child is ArrowScript:
				live += 1
		arrows = maxi(arrows, live)
	check(arrows > 0, "the archer's release became a real arrow")
	check(body.health < before - 5.0,
		"a cult arrow takes health off a body (%.1f -> %.1f)" % [before, body.health])

# --- the soldier loot run ---------------------------------------------------

func check_soldier_loot_run() -> void:
	# A fresh battle for the loot phase: the melee above is not this run's fight.
	for body in _bodies:
		body.revive()
	for index in _bodies.size():
		_bodies[index].global_position = LOOT_RUN_POSTS[index] + Vector3(0.0, 0.1, 0.0)
	_bodies[2].enter_downed(-1)
	var downed = _bodies[2]
	var downed_at: Vector3 = downed.global_position
	var soldier_starts: Array = []
	for index in 2:
		soldier_starts.append(_bodies[index].global_position)

	var drops: Array = []
	for entry in LOOT_DROPS:
		var pickup = _loot.spawn(str(entry[0]), entry[1])
		check(pickup != null, "%s lies on the battlefield" % str(entry[0]))
		drops.append(pickup)
	var stash_before: int = warband.stash.pooled_total()

	_finished.clear()
	_loot_run.setup(warband, _loot, _bodies)
	_loot_run.run(_loot.pickups())
	check(_loot_run.running(), "the survivors start walking")
	check(not _loot_run.done(), "a fresh run is not finished")
	var ticks := 0
	while not _loot_run.done() and ticks < 240:
		await physics_frame
		_controller.physics_step(STEP)
		ticks += 1

	check(_loot_run.done(), "the run finishes on its own")
	check(not _loot_run.running(), "a finished run is not still running")
	check(_finished.size() == 1 and int(_finished[0]) == 2,
		"the run reports two pieces, got %s" % str(_finished))
	check(warband.stash.pooled_total() == stash_before + 2,
		"the shared stash grew by two (%d -> %d)" % [stash_before, warband.stash.pooled_total()])
	await process_frame
	for index in drops.size():
		check(not is_instance_valid(drops[index]), "drop %d left the world" % index)

	check(downed.global_position.distance_to(downed_at) < 0.01,
		"the downed soldier never moved (%.3f m)" % downed.global_position.distance_to(downed_at))
	# The survivors physically jogged: they covered ground and stopped on top of
	# the piece they went for.
	for index in 2:
		var travelled: float = (_bodies[index].global_position as Vector3).distance_to(
			soldier_starts[index] as Vector3)
		check(travelled > 0.5, "soldier %d walked to its drop (%.2f m)" % [index, travelled])
		var target: Vector3 = LOOT_DROPS[index][1]
		var gap: float = _bodies[index].global_position.distance_to(target)
		check(gap <= LootRunScript.ARRIVE_REACH,
			"soldier %d stopped on the drop (%.2f m away)" % [index, gap])

	_waves.clear()
	check(_waves.living() == 0, "clear() empties the yard")
	check(_waves.wave() == -1, "clear() forgets the wave on the field")
	check(_waves.total_cleared() == 3, "clear() keeps the expedition's tally")
	await process_frame
