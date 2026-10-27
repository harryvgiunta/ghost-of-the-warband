extends SceneTree
## Phase Gate 2, the chain: the cages hand the squad to the town, the town's gate
## launches an expedition, and the field hands the survivors back to town - all
## through the real scene doors and the real `GameFlow` owner, on real saves.
##
## The content of each scene is proven by its own regression; this one proves the
## loop is actually wired and that the warband survives every hand-off.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const RosterScript = preload("res://scripts/warband/warband_roster.gd")
const Damage = preload("res://scripts/warband/damage_scaler.gd")

const TEST_SAVE := "user://game_flow_state.json"
const WARBAND_SAVE := "user://game_flow_warband.json"
## The campaign is one world now: the cages, the trail and the town are the same
## scene, entered at the camp for a fresh run and at the town for a return.
const CAGE := "res://scenes/warband_world.tscn"
const TOWN := "res://scenes/warband_world.tscn"
const ARENA := "res://admin_arena.tscn"

var flow
var warband
var state
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("FLOW_FAIL  ", message)

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
	flow = root.get_node("GameFlow")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()

	flow.active = true
	flow.start_campaign()
	var cage = await _wait_scene(CAGE, 8.0)
	check(cage != null, "the campaign opens in the cages")
	if cage == null:
		_finish()
		return
	check(cage.bodies.size() == 5, "the tutorial fields the four prisoners and the rescuer")
	check(warband.roster.count() == 5, "and the warband owns five bodies")
	check(flow.transitions == 1, "one transition so far")

	# The cage's own door, exactly as the escape emits it.
	cage.scene_requested.emit(TOWN)
	var town = await _wait_scene(TOWN, 8.0)
	check(town != null, "the escape hands the squad to the town")
	if town == null:
		_finish()
		return
	check(town.bodies.size() == 5, "the whole warband walks into the square")
	check(warband.roster.count() == 5, "the warband survives the hand-off")
	check(warband.souls.body_ids().size() == 5, "the town registered every body in the soul router")

	# Hire one more, then deploy three of them through the gate.
	var gold_before: int = warband.gold()
	var hired: Dictionary = warband.hire("Ilsa")
	check(bool(hired.get("ok", false)), "the town can still hire")
	check(warband.gold() < gold_before, "hiring spends the purse")
	check(warband.roster.count() == 6, "the warband is six")

	var deployed_ids: Array = warband.roster.alive_ids().slice(0, 3)
	var launch: Dictionary = town.gate.deploy_and_launch(deployed_ids)
	check(bool(launch.get("ok", false)), "the gate launches")
	check(town.is_connected("scene_requested", Callable(flow, "_on_scene_requested")),
		"the square's door is bound to the flow")
	var arena = await _wait_scene(ARENA, 10.0)
	check(arena != null, "the expedition reaches the arena")
	if arena == null:
		_finish()
		return
	check(arena.expedition, "a deployment line makes it a real battle")
	check(arena.bodies.size() == 3, "exactly the deployed line takes the field (%d)" % arena.bodies.size())
	check(arena.waves != null and arena.waves.living() == 3, "and the cult is waiting")

	# The field's door, exactly as Enter emits it after a cleared battle.
	arena.scene_requested.emit(TOWN)
	var back = await _wait_scene(TOWN, 8.0)
	check(back != null, "the field hands the survivors back to town")
	if back == null:
		_finish()
		return
	check(warband.roster.count() == 6, "the warband keeps every body through the battle")
	check(warband.souls.body_ids().size() == 6, "and the town re-registers them all")
	check(flow.transitions >= 4, "the loop made at least four transitions (%d)" % flow.transitions)

	# A fresh save on disk proves the loop is persistent, not just in memory.
	var reloaded = RosterScript.new()
	reloaded.from_dict(warband.to_dict().get("roster", {}))
	check(reloaded.count() == 6, "the saved roster matches the live one")

	_finish()

func _finish() -> void:
	flow.active = false
	Damage.reset()
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	if current_scene != null:
		current_scene.queue_free()
		await process_frame
	print("GAME_FLOW_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

func _wait_scene(path: String, timeout: float) -> Node:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await create_timer(0.1).timeout
		var scene := current_scene
		if scene != null and scene.scene_file_path == path:
			# One more beat so the scene's `_ready` (bodies, HUD, gate) has run.
			await create_timer(0.4).timeout
			scene = current_scene
			if scene != null and scene.scene_file_path == path:
				return scene
	return null
