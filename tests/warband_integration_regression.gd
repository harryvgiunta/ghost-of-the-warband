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
const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
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
	# A start that ever raises the opening's tips must not leave a panel over the
	# world: this run reads the world, not the lesson.
	if game.tips != null and is_instance_valid(game.tips):
		game.tips.hide()

	await create_timer(SETTLE_SECONDS).timeout
	check_world_pieces()
	await check_menu()
	await check_orders()
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
	_press_key(KEY_ESCAPE)


## One real key event through the input pipeline, so a binding is proved and not
## just the private method behind it.
func _press_key(keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
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


# --- the orders, the map and the click -------------------------------------

## The three things the campaign's quests are played against, as the world builds
## them: the cages, the warcamps, and the map sheet the player reads to find both.
## Then the one gesture that turns a kill into loot, through the world's own press
## path - a click on lootable ground must never also be a swing.
func check_orders() -> void:
	check(game.soldier_cages != null, "the world builds the cage line")
	check(game.watcher_warren != null, "the world builds the watcher warcamps")
	check(game.world_map != null, "the world builds the map sheet")
	if game.soldier_cages != null:
		check(game.soldier_cages.remaining() == 4, "four soldiers wait in the wood")
	if game.watcher_warren != null:
		check(game.watcher_warren.living() == game.watcher_warren.total(),
			"every warden in the warcamps is standing")
	var marks: Array = game.map_markers()
	check(marks.size() >= 4, "the map is told where the orders are (%d marks)" % marks.size())

	_press_key(KEY_M)
	await process_frame
	await process_frame
	check(game.world_map.is_open(), "M opens the map sheet")
	check(not paused, "the map does not pause the world")
	_press_key(KEY_M)
	await process_frame
	await process_frame
	check(not game.world_map.is_open(), "a second M closes it")

	# The click that loots. A drop is put exactly under the crosshair, so the ray
	# the world reads is the ray the test aimed down.
	var actor = game.controller.active_body(1)
	check(actor != null, "a body stands for the click")
	if actor == null or game.loot_hand == null:
		return
	# A piece under the crosshair but out of the body's reach is a swing. The
	# channel is the body's own work: a click on a drop across the clearing used
	# to loot it and steal the attack aimed at a fighter standing over it.
	var far_drop = game.spawn_pickup("wolf_pelt",
		actor.global_position + actor.global_basis.x * 30.0)
	check(far_drop != null, "a pelt lies thirty metres off")
	check(not game.loot_hand.try_click(actor, far_drop.global_position),
		"a drop out of the body's reach is left to the sword")
	check(not game.loot_hand.active(), "and no channel opened")
	far_drop.queue_free()
	# The same gesture on a piece at the body's feet is the loot.
	var drop = game.spawn_pickup("wolf_pelt",
		actor.global_position - actor.global_basis.z * 1.0)
	check(drop != null, "a pelt lies at the body's feet")
	check(game.loot_hand.try_click(actor, drop.global_position),
		"the left button begins the loot")
	check(game.loot_hand.active(), "the body is working the ground")
	check(game.loot_hand.target_kind() == "drop", "and it is the drop it found")
	# The world owns the channel's clock, so the test drives one full beat instead
	# of racing a squadmate to the piece the body is already working.
	game.loot_hand.tick(1.0)
	check(not game.loot_hand.active(), "the channel closes on its own")
	check(warband.stash.pooled_count("wolf_pelt") >= 1, "the pelt is in the shared stash")
	check(game.loot_hand.last_summary().contains("Wolf Pelt"),
		"and one line says what came back (%s)" % game.loot_hand.last_summary())

	# A fighter under the reticle is what the press was for, whatever lies at its
	# feet. The aim point of a mob across the fight sits on its own chest, so a drop
	# inside the same arm's reach is "under the crosshair" by distance alone: the
	# body ducked to work the ground in the middle of the fight and the click never
	# swung. That is the report "clicking to attack is unresponsive", and it starts
	# once the ground has steel on it.
	game.loot_hand.tick(0.3)
	var stand: Vector3 = actor.global_position
	var ray: Dictionary = game.controller.camera_rig.aim_ray()
	var ray_origin: Vector3 = ray.get("origin", stand)
	var ray_dir: Vector3 = ray.get("direction", -actor.global_basis.z)
	# The scenery the reticle lands on now is the wall the fighter must stand in
	# front of, or the ray would stop short and never meet him.
	var obstacle: Vector3 = game.controller.aim_sample().get("point", stand)
	var clear_from := ray_origin.distance_to(obstacle) if obstacle != Vector3.ZERO else 0.0
	var spot := Vector3.ZERO
	var reachable := false
	var along := 0.6
	while along < 14.0:
		var probe: Vector3 = ray_origin + ray_dir * along
		var flat := Vector2(probe.x - stand.x, probe.z - stand.z).length()
		var near_ground := absf((probe.y - 1.0) - stand.y) <= 0.8
		var clear := clear_from < 0.1 or along < clear_from - 0.4
		if flat >= 1.7 and flat <= 2.1 and near_ground and clear:
			spot = probe
			reachable = true
			break
		along += 0.05
	check(reachable, "the crosshair ray has a point inside a mob's arm's reach")
	if reachable:
		var fighter = WatcherScript.new()
		fighter.name = "LootFighter"
		fighter.mob_id = "hollow_warden"
		fighter.health_pool = 8.0
		game.add_child(fighter)
		# Feet under the ray point, so the capsule a ~2 m tall body carries has the
		# reticle on its chest rather than over its head.
		fighter.global_position = Vector3(spot.x, spot.y - 1.0, spot.z)
		# Held still so the ray keeps meeting the same capsule for the whole check.
		fighter.set_physics_process(false)
		var toward := Vector3(spot.x - stand.x, 0.0, spot.z - stand.z)
		if toward.length_squared() < 0.0001:
			toward = -actor.global_basis.z
		await physics_frame
		await physics_frame
		var aimed: Dictionary = game.controller.aim_sample()
		check(aimed.get("target") == fighter, "the reticle is on the living watcher")
		# The piece that steals the press: inside the body's reach and inside the
		# aim point's, so distance alone calls it "under the crosshair".
		game.loot_hand.tick(0.3)
		var under = game.spawn_pickup("wolf_pelt",
			stand + toward.normalized() * 0.9 + Vector3.UP * 0.2)
		check(under != null, "a pelt lies between the two bodies")
		# Read once: the squad's own hands take loose steel between frames, and the
		# piece has to be the same one for every press below.
		var under_at: Vector3 = under.global_position
		var strike := InputEventMouseButton.new()
		strike.button_index = MOUSE_BUTTON_LEFT
		strike.pressed = true
		check(not game._loot_click(strike),
			"a press aimed at a living fighter is a cut, not a loot")
		check(not game.loot_hand.active(), "and the body does not duck to work the ground")
		check(not game.loot_hand.try_click(actor, under_at, fighter),
			"a living fighter under the reticle is never a loot")
		check(not game.loot_hand.active(), "and no channel opened")
		# The same piece, the same arm: only the body on the reticle changes, and a
		# body that has stopped fighting is ground to work.
		fighter.take_damage(1000.0, 0)
		check(not bool(fighter.get("alive")), "the watcher is down")
		check(game.loot_hand.try_click(actor, under_at, fighter),
			"a press on that body once it is down is the loot")
		check(game.loot_hand.active(), "and the body works the ground")
		game.loot_hand.cancel()
		if is_instance_valid(under):
			under.queue_free()
		fighter.queue_free()
		await physics_frame

	# Empty hands are the one click that used to do nothing at all. It is not a
	# loot and it cannot swing, so the HUD has to name the missing piece.
	var merc: int = game.controller.merc_for_peer(1)
	var hands: Dictionary = warband.roster.equipped_of(merc)
	warband.roster.unequip(merc, "main")
	warband.roster.unequip(merc, "off")
	game.controller.refresh_gear(merc)
	await physics_frame
	check(str(actor.rig.weapon) in ["", "none"], "the body is bare-handed (%s)"
		% str(actor.rig.weapon))
	var bare := InputEventMouseButton.new()
	bare.button_index = MOUSE_BUTTON_LEFT
	bare.pressed = true
	check(not game._loot_click(bare), "a bare-handed press is not a loot")
	var status: Label = game.hud.get("_status_label")
	check(status != null and status.text.contains("hands are empty"),
		"and the HUD says why nothing swings (%s)"
			% ("" if status == null else status.text))
	for slot in ["main", "off"]:
		var item_id := str(hands.get(slot, ""))
		if not item_id.is_empty():
			warband.roster.equip(merc, slot, item_id)
	game.controller.refresh_gear(merc)

	# Nothing under the crosshair: the world must not eat the press, or the sword
	# could never be raised over open ground.
	await create_timer(0.4).timeout
	var empty := InputEventMouseButton.new()
	empty.button_index = MOUSE_BUTTON_LEFT
	empty.pressed = true
	check(not game._loot_click(empty), "a press on bare ground is left to the sword")


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
