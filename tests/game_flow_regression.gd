extends SceneTree
## GHOST OF THE WARBAND: the four doors on the title, through the real `GameFlow`
## and the real world scene.
##
## New Campaign opens the world at the cages with a fresh warband and a fresh
## purse; Resume Campaign opens it where the save's bookmark stands; a campaign
## that was left through the menu is on disk and resumes; and leaving the world
## never strands the flow. The world's own content is proven by its own
## regression - this one proves the loop is wired and that the warband, the
## roster and the purse survive every hand-off.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const RosterScript = preload("res://scripts/warband/warband_roster.gd")

const TEST_SAVE := "user://game_flow_state.json"
const WARBAND_SAVE := "user://game_flow_warband.json"
## The campaign is one world: the cages, the trail and the town are the same scene.
const WORLD := "res://scenes/warband_world.tscn"

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

	# --- NEW CAMPAIGN: the cages, a fresh warband and a fresh purse -----------
	check(int(state.credits) > 0, "the purse starts with the new-game credits")
	warband.hire("Old Hand")
	warband.add_mercenary("Survivor")
	var stale: int = warband.roster.count()
	check(stale == 2, "a warband stands before the new campaign starts (%d)" % stale)

	flow.active = true
	flow.start_campaign()
	var world = await _wait_scene(WORLD, 12.0)
	check(world != null, "NEW CAMPAIGN opens the world")
	if world == null:
		_finish()
		return
	check(flow.world_start == "camp", "at the cages, which is where a run starts")
	check(world.bodies.size() >= 5, "the cages field the squad (%d bodies)" % world.bodies.size())
	check(warband.roster.count() >= 5, "and the warband owns them (%d)" % warband.roster.count())
	check(flow.transitions == 1, "one transition so far")
	check(int(state.credits) > 0, "the purse is the new-game purse, not a previous run's")

	# --- the warband survives the hand-off ----------------------------------
	var live: int = warband.roster.count()
	var reloaded := RosterScript.new()
	reloaded.from_dict(warband.to_dict().get("roster", {}))
	check(reloaded.count() == live, "the saved roster matches the live one")

	# --- a checkpoint is what RESUME reads ----------------------------------
	var body = world.bodies[0]
	warband.save_checkpoint("trail", "trail", body.global_position, "TRAIL")
	check(warband.has_checkpoint(), "the world writes a bookmark")
	warband.save_state()
	check(FileAccess.file_exists(WARBAND_SAVE), "the campaign is on disk")

	# --- RESUME CAMPAIGN: back to the bookmark ------------------------------
	# The warband on disk is what a relaunch reads: reset, load, then resume.
	warband.reset_state()
	check(not warband.has_checkpoint(), "a reset forgets the bookmark")
	warband.load_state()
	flow.enter_warband()
	var resumed = await _wait_scene(WORLD, 12.0)
	check(resumed != null, "RESUME CAMPAIGN opens the world")
	if resumed == null:
		_finish()
		return
	check(flow.world_start == "checkpoint", "at the bookmark, not the cages (%s)" % flow.world_start)
	check(warband.has_checkpoint(), "and the bookmark is still the one the save holds")
	check(flow.transitions == 2, "each door is one transition (%d)" % flow.transitions)

	# --- EXIT TO TITLE leaves the flow usable -------------------------------
	flow.active = false
	check(flow.last_scene == WORLD, "the flow remembers the scene it opened (%s)" % flow.last_scene)

	_finish()

func _finish() -> void:
	flow.active = false
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
			# One more beat so the scene's `_ready` (bodies, HUD) has run.
			await create_timer(0.4).timeout
			scene = current_scene
			if scene != null and scene.scene_file_path == path:
				return scene
	return null
