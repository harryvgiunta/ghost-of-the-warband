extends SceneTree
## Auto save / checkpoints: the campaign remembers how far it got.
##
## The warband save is now also a bookmark. The camp's six watchers down and the
## squad on the road writes `trail_start`; the town square writes `town`. The
## bookmark rides in the same file as the roster, stash and essence, so a load is
## one truthful picture, and it must survive a save/load round trip, reject a
## hand-edited record rather than half-read it, and never appear in a file written
## before checkpoints existed.
##
## This drives the real world twice: once opening on a trail bookmark (the cages
## hang open, nobody is clamped, no watcher is fielded, the squad walks with the
## soul and the bookmark is not rewritten), then walks the soul into the square so
## the town bookmark replaces it, then opens a second world on that town bookmark.
## The restore door is exercised separately: a downed body wakes, the dead stay
## dead, and a checkpoint with no living body refuses to be loaded at all.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const SequencerScript = preload("res://scripts/warband/tutorial_sequencer.gd")
const WorldScene := "res://scenes/warband_world.tscn"
const TEST_SAVE := "user://checkpoint_player.json"
const WARBAND_SAVE := "user://checkpoint_warband.json"
const OLD_SAVE := "user://checkpoint_v3.json"
const BAD_SAVE := "user://checkpoint_bad.json"

var state
var warband
var flow
var game
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("CHECKPOINT_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func run() -> void:
	for path in [TEST_SAVE, WARBAND_SAVE, OLD_SAVE, BAD_SAVE]:
		_remove(path)
	state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	flow = root.get_node("GameFlow")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	flow.active = false
	flow.world_start = "camp"

	check_persistence()
	check_sanitising()
	check_restore()
	await check_world_resume()
	check_wipe_door()
	await check_retry_reload()
	await check_title_door()
	await check_opening_into_town()
	_finish()

func _finish() -> void:
	Engine.time_scale = 1.0
	if is_instance_valid(game):
		game.queue_free()
	await process_frame
	flow.active = false
	flow.world_start = "camp"
	for path in [TEST_SAVE, WARBAND_SAVE, OLD_SAVE, BAD_SAVE]:
		_remove(path)
	print("CHECKPOINT_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

# --- the record itself -----------------------------------------------------

func _seed_warband() -> void:
	warband.reset_state()
	var first: int = warband.add_mercenary("Ash")
	warband.roster.equip(first, "main", "sword_short")
	warband.add_mercenary("Bram")
	warband.add_mercenary("Wren")
	warband.stash.add("dagger_ironwood", 1)
	warband.save_state()

func check_persistence() -> void:
	_seed_warband()
	check(not warband.has_checkpoint(), "a fresh warband has no checkpoint")
	warband.save_checkpoint("trail_start", "trail", Vector3(4.5, 0.25, -90.0), "THE CAMP IS BEHIND YOU")
	var file := FileAccess.open(WARBAND_SAVE, FileAccess.READ)
	check(file != null, "the checkpoint writes a save file")
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	check(parsed is Dictionary, "the checkpoint save is JSON")
	if not (parsed is Dictionary):
		return
	var data: Dictionary = parsed
	check(data.get("checkpoint", {}) is Dictionary, "the file carries a checkpoint block")
	var stored: Dictionary = warband.sanitise_checkpoint(data.get("checkpoint", {}))
	check(stored.get("id", "") == "trail_start", "the bookmark names the tutorial's end")
	check(stored.get("area", "") == "trail", "the bookmark is on the trail")
	check(warband.checkpoint_position().distance_to(Vector3(4.5, 0.25, -90.0)) < 0.01,
		"the position survives the round trip")
	check(warband.checkpoint_label() == "THE CAMP IS BEHIND YOU", "the label survives too")

	# Mutating the warband after the bookmark must not change the bookmark, and a
	# reload must bring back the state the file holds.
	warband.add_mercenary("Het")
	warband.clear_checkpoint()
	check(not warband.has_checkpoint(), "a bookmark can be cleared")
	check(warband.load_state(), "the save loads")
	check(warband.roster.count() == 3, "the reload is the file's roster, not the live one (%d)" % warband.roster.count())
	check(warband.checkpoint_id() == "trail_start", "and the file's bookmark is back")

	# A file written before checkpoints existed still loads, at the town.
	var old: Dictionary = warband.to_dict()
	old["version"] = 3
	old.erase("checkpoint")
	var old_file := FileAccess.open(OLD_SAVE, FileAccess.WRITE)
	old_file.store_string(JSON.stringify(old))
	old_file.close()
	warband.save_path = OLD_SAVE
	check(warband.load_state(), "a v3 save loads")
	check(not warband.has_checkpoint(), "a v3 save carries no bookmark")
	check(warband.roster.count() == 3, "and its roster is intact")
	warband.save_path = WARBAND_SAVE
	warband.load_state()
	check(warband.checkpoint_id() == "trail_start", "the v4 bookmark is restored for the next checks")

func check_sanitising() -> void:
	check(warband.sanitise_checkpoint({}).is_empty(), "no record means no bookmark")
	check(warband.sanitise_checkpoint({"id": "", "area": "trail", "position": [0, 0, 0]}).is_empty(),
		"a nameless bookmark is refused")
	check(warband.sanitise_checkpoint({"id": "x", "area": "camp", "position": [0, 0, 0]}).is_empty(),
		"the camp is never a bookmark")
	check(warband.sanitise_checkpoint({"id": "x", "area": "trail", "position": [0, 0]}).is_empty(),
		"a two-value position is refused")
	check(warband.sanitise_checkpoint({"id": "x", "area": "trail", "position": ["a", 0, 0]}).is_empty(),
		"a non-numeric position is refused")
	check(warband.sanitise_checkpoint({"id": "x", "area": "trail", "position": [INF, 0, 0]}).is_empty(),
		"an infinite position is refused")
	var good: Dictionary = warband.sanitise_checkpoint(
		{"id": " town ", "area": "town", "position": [1, 2, 3], "at": 7})
	check(good.get("id", "") == "town" and good.get("area", "") == "town", "a clean record is accepted")
	check(warband.checkpoint_vector(good) == Vector3(1, 2, 3), "and reads back as a point")

	# A hand-edited file is normalised on load rather than poisoning the session.
	var bad: Dictionary = warband.to_dict()
	bad["checkpoint"] = {"id": "x", "area": "everywhere", "position": "here"}
	var bad_file := FileAccess.open(BAD_SAVE, FileAccess.WRITE)
	bad_file.store_string(JSON.stringify(bad))
	bad_file.close()
	var previous_path: String = warband.save_path
	warband.save_path = BAD_SAVE
	check(warband.load_state(), "a file with a garbage bookmark still loads")
	check(not warband.has_checkpoint(), "and drops the garbage")
	warband.save_path = previous_path
	warband.load_state()

# --- the restore door ------------------------------------------------------

func check_restore() -> void:
	# A body that was down at the bookmark gets up; a body that was dead stays so.
	var ids: Array = warband.roster.ids()
	warband.roster.set_state(int(ids[0]), Contracts.HealthState.DOWNED)
	warband.roster.set_health(int(ids[0]), 3.0)
	warband.roster.set_state(int(ids[1]), Contracts.HealthState.DEAD)
	warband.save_state()
	var credits: int = int(state.credits)
	flow.world_start = "camp"
	check(flow.restore_checkpoint(), "the restore door opens on a real bookmark")
	check(flow.world_start == "checkpoint", "and names the checkpoint as the world's start")
	check(warband.roster.state_of(int(ids[0])) == Contracts.HealthState.ALIVE,
		"a downed body is woken by the reload")
	check(warband.roster.health_of(int(ids[0])) >= warband.roster.max_health_of(int(ids[0])) * 0.5,
		"at half the body's own pool or better (%f)" % warband.roster.health_of(int(ids[0])))
	check(warband.roster.state_of(int(ids[1])) == Contracts.HealthState.DEAD,
		"a dead body stays dead")
	check(int(state.credits) == credits, "the purse is never rolled back by a reload")

	# No bookmark, and a bookmark with nobody standing, both refuse.
	warband.clear_checkpoint()
	warband.save_state()
	check(not flow.restore_checkpoint(), "a save without a bookmark cannot be resumed")
	for merc_id in warband.roster.ids():
		warband.roster.set_state(int(merc_id), Contracts.HealthState.DEAD)
	warband.save_checkpoint("town", "town", Vector3.ZERO, "EMPTY")
	flow.world_start = "camp"
	check(not flow.restore_checkpoint(), "a bookmark whose whole squad is dead refuses to load")
	check(flow.world_start == "camp", "and leaves the start where it was")

# --- the world opening on a bookmark ---------------------------------------

func _build_world() -> void:
	game = load(WorldScene).instantiate()
	root.add_child(game)
	await create_timer(0.8).timeout

func check_world_resume() -> void:
	_seed_warband()
	# Two bodies on their feet, one dead: a resume fields the two.
	var ids: Array = warband.roster.ids()
	warband.roster.set_state(int(ids[2]), Contracts.HealthState.DEAD)
	warband.save_checkpoint("trail_start", "trail", Vector3(6.0, 0.0, -90.0), "THE CAMP IS BEHIND YOU")
	flow.world_start = "checkpoint"
	await _build_world()
	if game == null or not game.has_method("stats"):
		check(false, "the world loaded for the trail resume")
		return
	check(game.start_area == "checkpoint", "the world opens on the bookmark (%s)" % game.start_area)
	check(game.bodies.size() == 2, "the bookmark's standing bodies take the field (%d)" % game.bodies.size())
	check(game.camp.sequencer == null, "no tutorial runs on a resumed trail")
	check(not game.camp.lesson_running(), "and the camp lesson is not running")
	check(game.camp.guards.is_empty(), "no watcher is fielded past the cages (%d)" % game.camp.guards.size())
	check(game.camp.cages_open(), "the cages hang open")
	check(game.squad.following, "the squad walks with the soul")
	var anchor: Vector3 = warband.checkpoint_position()
	for body in game.bodies:
		check(is_instance_valid(body) and body.global_position.distance_to(anchor) < 8.0,
			"a resumed body stands on the bookmark (%.1f m)" % (
				body.global_position.distance_to(anchor) if is_instance_valid(body) else -1.0))
	check(warband.checkpoint_id() == "trail_start", "the resumed trail does not rewrite its own bookmark")

	# Walking into the square advances the bookmark to the town.
	var soul = game.controller.active_body(1)
	check(soul != null, "the soul is in a body")
	if soul != null:
		soul.global_position = game.town.global_position + Vector3(0, 1.0, 0)
		await create_timer(0.3).timeout
		check(game.town.in_square(soul), "the teleported soul is inside the square (%.1f, %.1f vs %.1f, %.1f)" % [
			soul.global_position.x, soul.global_position.z,
			game.town.global_position.x, game.town.global_position.z])
	check(warband.checkpoint_id() == "town", "the town square writes the town bookmark (%s)" % warband.checkpoint_id())
	check(warband.checkpoint_area() == "town", "and says so")
	check(FileAccess.file_exists(WARBAND_SAVE), "the town bookmark is on disk at once")
	await check_town_silence(soul)
	game.queue_free()
	await process_frame
	game = null

	# The town bookmark opens a world in the square, with no lesson and no cages
	# to cut.
	flow.world_start = "checkpoint"
	await _build_world()
	if game == null or not game.has_method("stats"):
		check(false, "the world loaded for the town resume")
		return
	check(game.start_area == "checkpoint", "the town bookmark is a checkpoint start (%s)" % game.start_area)
	check(game.bodies.size() == 2, "the town resume fields the standing bodies (%d)" % game.bodies.size())
	check(game.camp.sequencer == null, "and never restarts the lesson")
	for body in game.bodies:
		check(is_instance_valid(body) and game.town.in_square(body),
			"a resumed body stands in the square")
	check(game.controller.active_body(1) != null, "the soul is seated in the square")
	check(warband.checkpoint_id() == "town", "the town resume keeps its own bookmark")

# --- the town is where the score stops -------------------------------------

## The soundtrack is the wood's: it rides the cages and the whole kilometre of
## trail. Reaching the town is the end of the run, so the square is silent - and
## the wood takes its score back the moment the squad walks back out through the
## gate, with a band between the two answers so a body on the line cannot flicker
## it.
func check_town_silence(soul) -> void:
	var audio = root.get_node_or_null("Audio")
	check(audio != null, "the mixer is up")
	if audio == null or soul == null:
		return
	# The world scene's scene-change sync has no `current_scene` in this harness,
	# so the track is set here: the rule under test is the town's own, not the
	# manager's.
	audio.play_music("warband")
	await create_timer(0.2).timeout
	check(str(audio.music_track).is_empty(),
		"the square stops the soundtrack (%s)" % str(audio.music_track))
	# Asked again with the score back up, because holding the rule has to be
	# idempotent - the manager answers a scene change with its own track.
	audio.play_music("warband")
	await create_timer(0.2).timeout
	check(str(audio.music_track).is_empty(),
		"and goes on stopping it while the soul stands there (%s)" % str(audio.music_track))
	# Just outside the square but inside the hysteresis band: hold, not restart.
	var half: float = game.town.WALL_RADIUS + 2.0
	soul.global_position = game.town.global_position + Vector3(0.0, 1.0, half + 2.0)
	await create_timer(0.2).timeout
	check(not game.town.in_square(soul), "the body is out of the square itself")
	check(str(audio.music_track).is_empty(), "a body in the band keeps the silence (%s)"
		% str(audio.music_track))
	# Well clear of the square: back to the wood, and the chase with it.
	soul.global_position = game.town.global_position + Vector3(0.0, 1.0, half + 30.0)
	await create_timer(0.2).timeout
	check(str(audio.music_track) == "warband",
		"the wood takes its score back (%s)" % str(audio.music_track))
	# And walking in again silences it again.
	soul.global_position = game.town.global_position + Vector3(0.0, 1.0, 0.0)
	await create_timer(0.2).timeout
	check(str(audio.music_track).is_empty(),
		"and the square stops it a second time (%s)" % str(audio.music_track))


# --- the wipe door ---------------------------------------------------------

func check_wipe_door() -> void:
	check(not bool(game._reload_checkpoint()),
		"a regression harness (GameFlow inactive) never reloads the world")
	# The door a wipe pulls is `restore_checkpoint()`; the scene hand-off after it
	# is the same world load the two resumes above already exercised.
	check(flow.restore_checkpoint(), "the checkpoint a wipe would load is restorable")
	check(flow.world_start == "checkpoint", "and names the checkpoint start")
	warband.clear_checkpoint()
	warband.save_state()
	flow.active = true
	check(not bool(game._reload_checkpoint()), "a warband with no bookmark has no way back")
	flow.active = false


## The wipe door end to end: the flow restores the bookmark and opens the world on
## it, with the bodies it held. This is the exact call `_reload_checkpoint()` makes
## once a live campaign has fallen.
func check_retry_reload() -> void:
	game.queue_free()
	await process_frame
	game = null
	_seed_warband()
	warband.save_checkpoint("trail_start", "trail", Vector3(6.0, 0.0, -90.0), "THE CAMP IS BEHIND YOU")
	flow.active = true
	check(flow.retry_checkpoint(), "the retry door restores the bookmark")
	var resumed = await _wait_world(8.0)
	check(resumed != null, "the retry door opens the world")
	if resumed != null:
		check(resumed.start_area == "checkpoint", "on the checkpoint start")
		check(resumed.bodies.size() == 3, "with the bookmark's bodies (%d)" % resumed.bodies.size())
		check(resumed.camp.sequencer == null, "and no lesson")
		check(resumed.controller.active_body(1) != null, "the soul is seated")
	flow.active = false
	if current_scene != null:
		current_scene.queue_free()
		await process_frame


func _wait_world(timeout: float) -> Node:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(timeout * 1000.0):
		await process_frame
		if current_scene != null and current_scene.has_method("stats"):
			# Give the world one physics tick to seat its bodies.
			await process_frame
			return current_scene
	return null


## The title's resume door: present, and only live when there is a warband save
## for it to open.
func check_title_door() -> void:
	var title = load("res://title.tscn").instantiate()
	root.add_child(title)
	await process_frame
	check(title.resume_button != null, "the title carries a resume door")
	check(not title.resume_button.disabled,
		"the resume door is live while a warband save exists")
	check(title.new_campaign_button != null, "and the new-campaign door is still there")
	warband.save_path = "user://checkpoint_absent.json"
	title._refresh_resume()
	check(title.resume_button.disabled, "the resume door is dead without a save")
	warband.save_path = WARBAND_SAVE
	title.queue_free()
	await process_frame


# --- the opening walked into the town --------------------------------------

## A session that played the opening keeps its camp cleared for good. That used to
## be enough to write `trail_start` again on the frame after the square wrote
## `town`, and `town` again on the frame after that: the status line flipped between
## the two bookmarks and the save hit the disk every frame. The bookmark only moves
## forward - and the trail's objective is a countdown to the square, gone inside it.
func check_opening_into_town() -> void:
	warband.reset_state()
	warband.clear_checkpoint()
	flow.world_start = "camp"
	await _build_world()
	if game == null or not game.has_method("stats") or game.camp.sequencer == null:
		check(false, "the world opened on the cages with the lesson running")
		return
	# The opening's end, as the sequencer books it: the leaving happened and the
	# six watchers it called out are down.
	var sequencer = game.camp.sequencer
	sequencer._state = SequencerScript.State.ESCAPING
	sequencer._guards_down = SequencerScript.GUARD_COUNT
	check(game.camp.tutorial_cleared(), "the opening reads as cleared")
	game._check_checkpoints()
	check(warband.checkpoint_id() == "trail_start",
		"the cleared opening writes the trail bookmark (%s)" % warband.checkpoint_id())
	var soul = game.controller.focus_body()
	check(soul != null, "the party has a body to walk")
	if soul == null:
		return
	# Several frames standing in the square, the camp still cleared behind it.
	for frame in 4:
		soul.global_position = game.town.global_position + Vector3(0.0, 1.0, 0.0)
		game._check_checkpoints()
		check(warband.checkpoint_id() == "town",
			"frame %d in the square keeps the town bookmark (%s)" % [frame, warband.checkpoint_id()])
	check(game.hud.status_line().contains("HEARTHSTEAD"),
		"the status line stays on the town (%s)" % game.hud.status_line())
	check(game._trail_objective_line(soul).is_empty(),
		"a body in the square is never told to reach the town (%s)" % game._trail_objective_line(soul))
	# Walking back out does not pull the bookmark back to the trail either.
	soul.global_position = game.trail.town_gate() + Vector3(0.0, 1.0, 0.0)
	game._check_checkpoints()
	check(warband.checkpoint_id() == "town",
		"walking back out keeps the town bookmark (%s)" % warband.checkpoint_id())
	# The walk in, from outside the gate to the fire: the objective's figure only
	# ever falls, and the line is gone once the square is reached.
	var centre: Vector3 = game.town.global_position
	var gate: Vector3 = game.trail.town_gate()
	var outside: Vector3 = gate + (gate - centre).normalized() * 24.0
	var previous := INF
	var falling := true
	var gone := false
	for step in 13:
		var at: Vector3 = outside.lerp(centre, float(step) / 12.0)
		soul.global_position = Vector3(at.x, soul.global_position.y, at.z)
		var line: String = game._trail_objective_line(soul)
		if line.is_empty():
			gone = game.town.in_square(soul)
			continue
		var metres := float(line.get_slice("\u00b7", 1).to_int())
		falling = falling and metres <= previous and not gone
		previous = metres
	check(falling, "the walk to the town counts its metres down, never back up")
	check(gone, "and the line is gone in the square")
