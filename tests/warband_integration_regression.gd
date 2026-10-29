extends SceneTree
## The world's wiring: the pieces that are not a walk and not a fight, but that a
## campaign still cannot open without.
##
## Phase A's unit tests prove each module on its own. This one proves the place
## they are bolted into: the campaign scene opens on a real trail bookmark, seats
## its bodies, and then
##
##   1. builds the one `WarbandAbilities` scene and binds every seated body to it,
##      so a looted weapon's cue can actually spawn its arrow;
##   2. builds the deep-wood band - eight briar wolves in `guards`, with the
##      `MobCuller` that keeps a walked-past wolf cheap;
##   3. paints the HUD against a living body: a stamina bar with a real maximum
##      and three ability tiles;
##   4. opens and closes the campaign menu from a real Escape key without pausing
##      the tree;
##   5. never hands a human-occupied body to the squad brains - the rule that keeps
##      co-op from driving a body a player is walking.

const WorldScene := "res://scenes/warband_world.tscn"
const TEST_SAVE := "user://warband_integration_player.json"
const WARBAND_SAVE := "user://warband_integration_warband.json"
## The bookmark the world opens on: on the trail, past the cages, so the opening
## lesson and its pause card are behind the warband.
const TRAIL_POINT := Vector3(0.0, 0.0, -90.0)
## How long the world gets to build, seat and settle before the checks read it.
const SETTLE_SECONDS := 1.0
## A hang is a failure, not a test that never ends.
const WATCHDOG_SECONDS := 25.0

var state
var warband
var flow
var game
var checks := 0
var failures := 0
var _done := false


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("INTEGRATION_FAIL  ", message)


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
	flow.active = false

	# One trail bookmark and three living bodies: the world resumes on the road
	# with a real squad, which is the only start where every piece below has
	# something to read.
	for merc_name in ["Ash", "Bram", "Het"]:
		warband.add_mercenary(str(merc_name))
	warband.save_checkpoint("trail_start", "trail", TRAIL_POINT,
		"THE CAMP IS BEHIND YOU")
	flow.world_start = "checkpoint"

	var watchdog := Timer.new()
	watchdog.name = "Watchdog"
	watchdog.wait_time = WATCHDOG_SECONDS
	watchdog.one_shot = true
	watchdog.timeout.connect(_on_watchdog)
	root.add_child(watchdog)
	watchdog.start()

	game = load(WorldScene).instantiate()
	root.add_child(game)
	if not game.has_method("stats"):
		check(false, "the world scene loaded without its script")
		_finish()
		return
	current_scene = game
	# A start that ever raises the opening card must not leave the tree paused
	# behind it: this run reads the world, not the lesson.
	if is_instance_valid(game.card) and game.card.is_open():
		game.card.close()

	await create_timer(SETTLE_SECONDS).timeout
	check_world_pieces()
	await check_menu()
	check_ally_rule()
	_finish()


func _on_watchdog() -> void:
	check(false, "the world did not settle inside %.0f s" % WATCHDOG_SECONDS)
	_finish()


# --- the pieces the world builds ------------------------------------------

func check_world_pieces() -> void:
	# The one ability scene, and one binding per seated body. A body whose cue is
	# not wired starts a skill clock that fires into nothing.
	check(game.abilities != null, "the world builds the ability scene")
	var bound: Array = game.abilities.bound_bodies() if game.abilities != null else []
	check(game.bodies.size() > 0, "the bookmark fielded a warband (%d bodies)" % game.bodies.size())
	check(bound.size() == game.bodies.size(),
		"every seated body is bound to the abilities (%d of %d)"
		% [bound.size(), game.bodies.size()])

	# The band on the way out, and its culler.
	check(game.wilderness != null, "the world builds the wilderness band")
	var wolves: int = game.wilderness.wolves().size() if game.wilderness != null else 0
	check(wolves >= 6, "the way out holds its wolves (%d)" % wolves)
	check(game.find_child("MobCuller", true, false) != null,
		"the band owns its MobCuller")
	# They are the world's mobs: the same `guards` list the squad and retarget read.
	var unlisted := 0
	if game.wilderness != null:
		for wolf in game.wilderness.wolves():
			if not game.guards.has(wolf):
				unlisted += 1
	check(unlisted == 0,
		"every wolf is on the world's hostile list (%d missing)" % unlisted)

	# The HUD is painted against a living body, not idling at zero.
	var bar: ProgressBar = game.hud.stamina_bar()
	check(bar != null, "the HUD carries a stamina bar")
	if bar != null:
		check(bar.max_value > 0.0, "the stamina bar has a real maximum (%.1f)" % bar.max_value)
	check(game.hud.ability_tiles().size() == 3,
		"the HUD carries three ability tiles (%d)" % game.hud.ability_tiles().size())


# --- the menu --------------------------------------------------------------

## Escape as the player sends it: a real key event through the input pipeline, so
## this proves the world's binding and not just the private method behind it.
func _press_escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)


func check_menu() -> void:
	check(game.menu != null, "the world builds the campaign menu")
	if game.menu == null:
		return
	_press_escape()
	await process_frame
	await process_frame
	check(game.menu.is_open(), "Escape opens the menu")
	check(not paused, "an open menu does not pause the world")

	_press_escape()
	await process_frame
	await process_frame
	check(not game.menu.is_open(), "a second Escape closes the menu")
	check(not paused, "closing the menu leaves the world running")


# --- the ally rule ---------------------------------------------------------

func check_ally_rule() -> void:
	var occupied_id: int = game.controller.merc_for_peer(1)
	check(occupied_id > 0, "the soul is seated in a body")
	check(int(warband.souls.occupied_by(occupied_id)) > 0,
		"the seated body is booked to the local soul")
	check(not game._is_free_ally(occupied_id),
		"a body a soul is inside is never a squadmate")

	var free_id := -1
	for merc_id in game.squad_ids:
		if int(warband.souls.occupied_by(int(merc_id))) == 0:
			free_id = int(merc_id)
			break
	check(free_id > 0, "the bookmark fielded a body nobody is inside")
	if free_id > 0:
		check(game._is_free_ally(free_id),
			"a free body may still act as a squadmate")


# --- done ------------------------------------------------------------------

func _finish() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(game):
		game.queue_free()
	await process_frame
	if flow != null:
		flow.active = false
		flow.world_start = "camp"
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("WARBAND_INTEGRATION_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
