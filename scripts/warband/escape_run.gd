extends Node3D
## GHOST OF THE WARBAND: the run from the camp to town.
##
## The arch in the cage yard is not a teleport any more. It opens onto the road
## out - a quarter-kilometre of night voodoo wood, torch-lit, hung with rags and
## bones - and the warband has to run it. Two cultists start behind the squad and
## a pair waits in each of the three clearings ahead, so the escape is a running
## fight the whole way rather than one last stand at the gate.
##
## This scene owns the bodies, the fight and the doors. The lane and every prop
## on it belong to `run_forest.gd`, which builds them out of the world's own art
## kits; the squad's behaviour is `squad_drive.gd`, the same one the cage uses, so
## a freed prisoner follows the soul down the lane and fights what the lane puts
## in front of them without a second copy of that AI existing.
##
## Two ways out, and both of them are the same door:
##   * the far arch: walk inside `ARCH_RADIUS`, press G, the warband reaches town;
##   * a wipe: every body down means the run is over, and after `WIPE_BEAT` the
##     warband is handed to town exactly as it fell - downed bodies stay downed,
##     no revival, no sweep, no free loot.

signal scene_requested(path: String)

const RunForestScript = preload("res://scripts/warband/run_forest.gd")
const ControllerScript = preload("res://scripts/warband/possession_controller.gd")
const HudScript = preload("res://scripts/warband/warband_hud.gd")
const ScreenScript = preload("res://scripts/warband/warband_screen.gd")
const PaperdollScript = preload("res://scripts/warband/warband_paperdoll.gd")
const LootScript = preload("res://scripts/warband/loot_vacuum.gd")
const CrawlScript = preload("res://scripts/warband/crawl_to_safety.gd")
const ReviveScript = preload("res://scripts/warband/revive_channel.gd")
const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const SquadDriveScript = preload("res://scripts/warband/squad_drive.gd")
const BrandedScript = preload("res://scripts/warband/branded_runner.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")

## The one place the run ends up. The town is the next scene's business; this
## scene only asks for it.
const TOWN_SCENE := "res://scenes/town_hub.tscn"
## How close to the far arch a body must stand to take the town road.
const ARCH_RADIUS := 4.0
## What a warband sword may bite: the watchers' physics layer. `ArenaActor`
## defaults to 4 (other fighters), and a run body that kept that mask would swing
## through every mob in the wood and damage nothing.
const WATCHER_LAYER := 2
## The watchers' damage source id, so a blow is booked against the road and never
## against a squadmate's slot.
const WATCHER_SOURCE := 91
## The lane is 286 m; bodies are clamped to a square around the origin.
const BOUNDS := 320.0
const LOOT_REACH := 2.6
## How far an escorting ally will pick its own fight before it comes back to the
## soul. The wood is 286 m long: an ally that chases every watcher it can see
## would be a spectator for the run.
const ENGAGE_RADIUS := 26.0
## What each cultist carries, in spawn order. Every one of them drops it.
const CULTIST_ARMS := [
	"sword_arming", "dagger_iron", "sword_short", "sword_short",
	"dagger_iron", "sword_arming", "sword_short", "dagger_iron",
]
## How long the squad lies in the mud before the run hands the warband to town.
const WIPE_BEAT := 2.5
const OBJECTIVE := "REACH THE TOWN ROAD"
const HINT := "The squad follows you   ·   TAB - warband   ·   P - gear"

var warband
var controller
var camera: Camera3D
var hud
var screen
var paperdoll
var loot
var revive
var branded
var brand_hud
## The lane: `{root, lane, length, width, torches, spawn_posts, arch, ...}` from
## `run_forest.gd`. Every number the HUD and the test read comes from here.
var forest: Dictionary = {}
var bodies: Array = []
var guards: Array = []
var crawls: Array = []
var squad
var squad_ids: Array[int] = []
## What the squad has taken off the ground so far. Silent: the run does not
## advertise loot, and the total is only for the readout in a test or a log.
var steel_taken := 0

var _pickups: Array = []
var _reviving := false
var _door_taken := false
var _wipe_beat := -1.0
var _cultist_kills := 0
var _roster_elapsed := 0.0
var _prompt_text := ""
var _hint_text := ""


func _ready() -> void:
	warband = get_node_or_null("/root/Warband")
	if warband == null:
		push_error("EscapeRun needs the Warband autoload")
		return
	forest = RunForestScript.build(self)
	camera = Camera3D.new()
	camera.name = "RoadCamera"
	camera.current = true
	camera.fov = 62.0
	camera.near = 0.08
	camera.far = 240.0
	camera.position = Vector3(0.0, 12.0, 24.0)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, 0.0))

	controller = ControllerScript.new()
	controller.name = "Soul"
	controller.auto_simulate = false
	add_child(controller)
	controller.setup(warband, camera, self)
	bodies = controller.spawn_mercenaries(_spawn_points(), true)
	_place_bodies()
	_wire_crawl()
	revive = ReviveScript.new()
	revive.name = "Revive"
	add_child(revive)
	revive.set_bodies(bodies)
	_build_loot()
	controller.possession_changed.connect(_on_possession_changed)
	controller.transfer_refused.connect(_on_transfer_refused)
	controller.possession_released.connect(_on_possession_released)
	# The soul is in a body before the cult spawns: the two behind the squad start
	# on the soul's own body, and the squad's escort begins from a soul already
	# seated rather than a spectator's camera.
	_enter_first_body()
	_build_cultists()
	_build_squad()
	_build_ui()
	branded = BrandedScript.new()
	branded.name = "Branded"
	add_child(branded)
	brand_hud = BrandedHud.attach(self)
	_on_possession_changed(1, controller.merc_for_peer(1))
	# The blood field is the shared one: the first wound would create it anyway,
	# but a scene that owns its own pool of stains owns its own budget too.
	BloodFx.field_for(self)
	# Capture the mouse the way every warband scene does: the player is in a body.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_hint()
	if hud != null:
		hud.set_status("The arch opens on the wood. Run the lane to town.", 6.0)
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.bind(self)
	print("ESCAPE_RUN_READY bodies=%d length=%.1f width=%.1f torches=%d cultists=%d"
		% [bodies.size(), float(forest.get("length", 0.0)), float(forest.get("width", 0.0)),
			(forest.get("torches", []) as Array).size(), guards.size()])


func _process(delta: float) -> void:
	if controller == null:
		return
	var panel_open := _panel_open()
	var wanted := Input.MOUSE_MODE_VISIBLE if panel_open else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != wanted:
		Input.mouse_mode = wanted
	_tick_revive(delta)


func _physics_process(delta: float) -> void:
	if controller == null:
		return
	# The squad's brains write a body's intent for this frame, so they run before
	# the controller integrates it; the cultists are wilderness mobs and tick
	# themselves.
	if _door_taken:
		_hold_squad()
	else:
		squad.drive(delta)
	controller.physics_step(delta)
	SquadDriveScript.retarget(guards, bodies)
	_sync_roster(delta)
	_update_prompt()
	_check_wipe(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_TAB:
			if screen.is_open():
				screen.close()
			else:
				_hide_panels()
				screen.open()
			get_viewport().set_input_as_handled()
		KEY_P:
			if paperdoll.is_open():
				paperdoll.close()
			else:
				_hide_panels()
				paperdoll.open(controller.merc_for_peer(1))
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if _panel_open():
				_hide_panels()
				get_viewport().set_input_as_handled()
		KEY_K:
			_try_loot()
			get_viewport().set_input_as_handled()
		KEY_R:
			_activate_brand()
			get_viewport().set_input_as_handled()
		KEY_G:
			_try_take_town_road()
			get_viewport().set_input_as_handled()


## `E` is the revive channel, so it is consumed before the actor layer can read it
## as a step, and only when there is a downed body in reach.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.echo or event.keycode != KEY_E:
		return
	if event.pressed:
		if _reviving or _revive_target() != null:
			_begin_revive()
			get_viewport().set_input_as_handled()
	elif _reviving:
		_cancel_revive()
		get_viewport().set_input_as_handled()


# --- the fielded warband ---------------------------------------------------

func _spawn_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for post in forest.get("spawn_posts", []) as Array:
		points.append(post as Vector3)
	return points


## Give every body its post and point its weapon at the wood. Nothing in this
## scene is an arena bot: an unpossessed body either escorts the soul or lies
## where it fell.
func _place_bodies() -> void:
	for actor in bodies:
		if not is_instance_valid(actor):
			continue
		var merc_id: int = controller.merc_of(actor)
		actor.global_position = actor.spawn_point
		actor.bounds = BOUNDS
		actor.combat.target_mask = WATCHER_LAYER
		controller.set_bot(merc_id, false)
		# `seat_loadout()` is the spawn snapshot; the roster is the truth. Re-assert
		# it once the body is standing, so a piece the camp's last quiet moment put
		# in the roster is the piece the body walks the lane with.
		controller.refresh_gear(merc_id)


func _enter_first_body() -> void:
	var ids: Array[int] = controller.living_merc_ids()
	if ids.is_empty():
		return
	controller.direct(1, ids[0])


func _wire_crawl() -> void:
	for actor in bodies:
		var crawl = CrawlScript.new()
		crawl.name = "Crawl"
		add_child(crawl)
		crawl.attach(actor)
		crawl.set_friends(bodies)
		crawls.append(crawl)


func _build_loot() -> void:
	loot = LootScript.new()
	loot.name = "Loot"
	add_child(loot)
	loot.setup(warband, self)
	loot.equip_target = Callable(self, "_loot_owner")


## Which mercenary a picked-up piece should be worn by, or -1.
func _loot_owner(peer_id: int) -> int:
	var actor = controller.body_for_peer(peer_id)
	if actor == null or not is_instance_valid(actor):
		return -1
	if not bool(actor.get("alive")) or bool(actor.get("downed")):
		return -1
	return controller.merc_for_peer(peer_id)


func _on_pickup_taken(_pickup) -> void:
	steel_taken += 1
	if screen != null:
		screen.refresh()


## The squad, driven by the module the cage also uses: they escort the soul,
## arm themselves off the ground and fight what blocks the road.
func _build_squad() -> void:
	squad = SquadDriveScript.new()
	squad.setup(warband, controller, loot)
	squad_ids.clear()
	for actor in bodies:
		var merc_id: int = controller.merc_of(actor)
		if merc_id > 0 and not squad_ids.has(merc_id):
			squad_ids.append(merc_id)
	squad.squad_ids = squad_ids
	squad.watchers = guards
	squad.pickups = _pickups
	squad.following = true
	squad.engage_radius = ENGAGE_RADIUS


func _hold_squad() -> void:
	for merc_id in squad_ids:
		var actor = controller.body_of(int(merc_id))
		if actor == null or not is_instance_valid(actor):
			continue
		if bool(actor.get("alive")) and not bool(actor.get("downed")):
			actor.accept_network_input(Vector2.ZERO, false)


# --- the cult on the road --------------------------------------------------

## Two behind the squad at the mouth of the lane and a pair in each clearing:
## eight cultists, all armed, all hunting, all dropping what they carried.
func _build_cultists() -> void:
	# The pair at the camp mouth is aimed at the soul itself: the run starts with
	# the player already being chased, not with a wood that has to notice them.
	var soul = controller.active_body(1)
	for post in forest.get("pursuer_posts", []) as Array:
		_spawn_cultist(post as Vector3, soul)
	for post in forest.get("clearing_posts", []) as Array:
		_spawn_cultist(post as Vector3, null)


func _spawn_cultist(at: Vector3, prey) -> void:
	var watcher := WatcherScript.new()
	watcher.name = "RoadWatcher%d" % (guards.size() + 1)
	watcher.mob_id = "hollow_warden"
	add_child(watcher)
	watcher.global_position = at
	# The town end of the lane is the safe ring: the last few metres before the
	# arch are town ground, not wood ground.
	watcher.safe_center = forest.get("arch", Vector3.ZERO)
	watcher.defeated.connect(_on_cultist_defeated)
	watcher.attacked.connect(_on_cultist_attack)
	watcher.arm(str(CULTIST_ARMS[guards.size() % CULTIST_ARMS.size()]))
	var target = prey if is_instance_valid(prey) else _nearest_standing_body(at)
	if target != null:
		watcher.hunt(target)
	guards.append(watcher)


## Each one drops the weapon it held, exactly as the camp's watchers do.
func _on_cultist_defeated(enemy, _reward: int) -> void:
	_cultist_kills += 1
	if is_instance_valid(enemy) and enemy.has_method("take_weapon_item"):
		var item_id := str(enemy.take_weapon_item())
		if not item_id.is_empty():
			var pickup = loot.spawn(item_id, enemy.global_position + Vector3(0.3, 0.0, 0.2))
			if pickup != null:
				pickup.taken.connect(_on_pickup_taken)
				_pickups.append(pickup)
	if hud != null and guards.size() > 0:
		hud.set_status("A cultist falls on the road (%d of %d)." % [_cultist_kills, guards.size()],
			2.0)


## A watcher's swing lands on the warband body it was hunting. The mob emits the
## blow; the scene applies it through the body's own guard, like every scene.
func _on_cultist_attack(attacker, amount: float, victim) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(victim):
		return
	if victim.has_method("receive_melee"):
		victim.receive_melee(amount, WATCHER_SOURCE, attacker.global_position)
	elif victim.has_method("take_damage"):
		victim.take_damage(amount, WATCHER_SOURCE)


## The nearest standing squad body to a point; the cultists are pointed here.
func _nearest_standing_body(point: Vector3):
	var best = null
	var best_distance := INF
	for body in bodies:
		if not is_instance_valid(body) or not bool(body.get("alive")) or bool(body.get("downed")):
			continue
		var distance: float = body.global_position.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = body
	return best


# --- the two ways out ------------------------------------------------------

## The far arch is a door, not a trigger: walk inside `ARCH_RADIUS` and press G.
func _try_take_town_road() -> void:
	if _door_taken:
		return
	var actor = controller.active_body(1)
	if actor == null or not is_instance_valid(actor):
		if hud != null:
			hud.set_status("The soul is loose. There is nobody to walk the road.", 3.0)
		return
	if not _arch_in_reach(actor):
		if hud != null:
			hud.set_status("The town gate is at the far end of the lane (%d m)."
				% int(round(_flat_distance(actor.global_position, forest.get("arch", Vector3.ZERO)))), 3.0)
		return
	_finish_run()


func _arch_in_reach(actor) -> bool:
	var arch: Vector3 = forest.get("arch", Vector3.ZERO)
	return _flat_distance(actor.global_position, arch) <= ARCH_RADIUS


## A wipe: every body the run fielded is down or dead. The wood has the warband;
## the roster keeps exactly that state, and the run ends the same way a victory
## does - through the road's own door.
func _check_wipe(delta: float) -> void:
	if _door_taken or not _all_bodies_out():
		return
	if _wipe_beat < 0.0:
		_wipe_beat = WIPE_BEAT
	squad.following = false
	if hud != null:
		hud.set_status("The warband is down. The wood takes what is left.", WIPE_BEAT)
	_wipe_beat -= delta
	if _wipe_beat <= 0.0:
		_finish_run()


func _all_bodies_out() -> bool:
	if bodies.is_empty():
		return false
	for actor in bodies:
		if not is_instance_valid(actor):
			continue
		if bool(actor.get("alive")) and not bool(actor.get("downed")):
			return false
	return true


## Hand the warband to town through the road's own door. The roster is mirrored
## first, so the next scene loads the squad as it actually stands - including a
## wipe, where every body is left downed and nothing is gathered.
func _finish_run() -> void:
	if _door_taken:
		return
	_door_taken = true
	_hold_squad()
	_sync_roster(1.0)
	if hud != null:
		hud.set_status("The road ends in town.", 3.0)
	if revive != null:
		revive.set_bodies([])
	scene_requested.emit(TOWN_SCENE)


## The roster is the truth the next scene loads: mirror health and downed state
## while the run lasts, so a body that fell on the lane arrives in town exactly
## as it fell.
func _sync_roster(delta: float) -> void:
	_roster_elapsed += delta
	if _roster_elapsed < 0.4:
		return
	_roster_elapsed = 0.0
	if warband == null or controller == null:
		return
	for actor in bodies:
		if not is_instance_valid(actor):
			continue
		var merc_id: int = controller.merc_of(actor)
		if merc_id <= 0:
			continue
		var state := Contracts.HealthState.ALIVE
		if bool(actor.get("downed")):
			state = Contracts.HealthState.DOWNED
		elif not bool(actor.get("alive")):
			state = Contracts.HealthState.DEAD
		warband.roster.set_health(merc_id, float(actor.get("health")))
		warband.roster.set_state(merc_id, state)


# --- possession ------------------------------------------------------------

func _on_possession_changed(peer_id: int, merc_id: int) -> void:
	if peer_id == 1 and hud != null:
		hud.set_body(controller.active_body(1), warband.roster.name_of(merc_id), merc_id)
	_attach_brand()
	_update_hint()


func _on_transfer_refused(_peer_id: int, merc_id: int, reason: String) -> void:
	if hud != null:
		hud.set_status("%s: %s" % [warband.roster.name_of(merc_id), reason], 2.5)


func _on_possession_released(_peer_id: int, reason: String) -> void:
	if hud != null:
		hud.set_body(null, "", -1)
		hud.set_status("The soul is loose (%s)." % reason, 4.0)


func _on_possess_requested(merc_id: int) -> void:
	screen.close()
	controller.direct(1, merc_id)


func _hide_panels() -> void:
	if screen != null and screen.is_open():
		screen.close()
	if paperdoll != null and paperdoll.is_open():
		paperdoll.close()


func _panel_open() -> bool:
	return (screen != null and screen.is_open()) \
		or (paperdoll != null and paperdoll.is_open())


# --- the branded sigil -----------------------------------------------------

## The sigil belongs to the weapon, not the body: every time the soul changes
## hands, the runner is re-bound to whatever blade that mercenary holds.
func _attach_brand() -> void:
	if branded == null:
		return
	var actor = controller.active_body(1)
	var merc_id: int = controller.merc_for_peer(1)
	if actor == null or merc_id <= 0:
		branded.attach(null, {})
	else:
		var main_id := str(warband.roster.equipped_of(merc_id).get("main", ""))
		branded.attach(actor, warband.cruor.brand_of(main_id))
	if brand_hud != null:
		brand_hud.set_runner(branded)


func _activate_brand() -> void:
	if branded == null or hud == null:
		return
	var status: Dictionary = branded.can_activate()
	if not bool(status.get("ok", false)):
		hud.set_status(str(status.get("reason", "No brand.")), 2.0)
		return
	if branded.activate():
		hud.set_status(str(branded.brand().get("ability", "")), 1.5)


# --- revive ----------------------------------------------------------------

func _revive_target():
	var actor = controller.active_body(1)
	if actor == null or not is_instance_valid(actor):
		return null
	var best = null
	var best_distance: float = Contracts.REVIVE_REACH
	for body in bodies:
		if not is_instance_valid(body) or body == actor:
			continue
		if not bool(body.get("downed")) or not bool(body.get("alive")):
			continue
		var distance: float = actor.global_position.distance_to(body.global_position)
		if distance <= best_distance:
			best_distance = distance
			best = body
	return best


func _begin_revive() -> void:
	var target = _revive_target()
	if target == null or revive == null:
		return
	if revive.begin(1, target):
		_reviving = true
		hud.set_status("Reviving %s..." % warband.roster.name_of(int(controller.merc_of(target))),
			Contracts.REVIVE_CHANNEL_SECONDS)
	else:
		hud.set_status("That one cannot be brought back.", 2.0)


func _cancel_revive() -> void:
	_reviving = false
	if revive != null:
		revive.cancel(1)


func _tick_revive(delta: float) -> void:
	if revive == null:
		return
	revive.tick(delta)
	if not _reviving:
		return
	var progress: float = float(revive.progress(1))
	if hud != null and progress > 0.0:
		hud.set_prompt("REVIVING  %d%%" % int(round(progress * 100.0)))
	if not revive.channeling(1):
		_reviving = false


# --- looting and the readout -----------------------------------------------

## `K` still works for a human, exactly as it does in the camp; the run never
## advertises it, and the squad loots itself.
func _nearest_pickup():
	var actor = controller.active_body(1)
	if actor == null or not is_instance_valid(actor):
		return null
	var best = null
	var best_distance := LOOT_REACH
	for pickup in _pickups:
		if not is_instance_valid(pickup) or bool(pickup.collected):
			continue
		var distance: float = actor.global_position.distance_to(pickup.global_position)
		if distance <= best_distance and not pickup.blocked_for(1):
			best_distance = distance
			best = pickup
	return best


func _try_loot() -> void:
	var pickup = _nearest_pickup()
	if pickup == null:
		hud.set_status("Nothing within reach.", 1.5)
		return
	var result: Dictionary = loot.quick_loot(pickup, 1)
	if bool(result.get("ok", false)):
		controller.refresh_gear(controller.merc_for_peer(1))
	hud.set_status(str(result.get("message", "")), 2.5)


## The objective line names the escape and carries the metres left to the arch.
## Nothing else: the run does not advertise loot and does not count kills at the
## player.
func _update_prompt() -> void:
	if hud == null or controller == null:
		return
	var text := ""
	var actor = controller.active_body(1)
	if _door_taken:
		text = "The road ends in town."
	elif actor == null or not is_instance_valid(actor):
		text = "The warband is down."
	else:
		var gap := _flat_distance(actor.global_position, forest.get("arch", Vector3.ZERO))
		text = "%s   ·   %d m" % [OBJECTIVE, int(round(gap))]
	if text != _prompt_text:
		_prompt_text = text
		hud.set_prompt(text)


func _update_hint() -> void:
	if hud == null:
		return
	var text := HINT
	var actor = controller.active_body(1)
	if actor != null and is_instance_valid(actor) and _arch_in_reach(actor):
		text = "G - take the town road"
	if text != _hint_text:
		_hint_text = text
		hud.set_hint(text)


## What the HUD says the run is, for a test that must not read a private label.
func objective_text() -> String:
	return OBJECTIVE


## The live prompt line, distance readout included.
func prompt_text() -> String:
	return _prompt_text


func cultist_count() -> int:
	return guards.size()


func cultists_alive() -> int:
	var alive := 0
	for watcher in guards:
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			alive += 1
	return alive


func cultist_kills() -> int:
	return _cultist_kills


func pickups_left() -> int:
	var left := 0
	for pickup in _pickups:
		if is_instance_valid(pickup) and not bool(pickup.collected):
			left += 1
	return left


func door_taken() -> bool:
	return _door_taken


func _flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()


# --- ui --------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)
	hud = HudScript.new()
	hud.name = "WarbandHud"
	layer.add_child(hud)
	hud.configure(warband)
	hud.set_prompt("%s   ·   %d m" % [OBJECTIVE,
		int(round(_flat_distance(forest.get("start", Vector3.ZERO), forest.get("arch", Vector3.ZERO))))])
	screen = ScreenScript.new()
	screen.name = "WarbandScreen"
	add_child(screen)
	screen.configure(warband, warband.souls)
	screen.possess_requested.connect(_on_possess_requested)
	paperdoll = PaperdollScript.new()
	paperdoll.name = "Paperdoll"
	add_child(paperdoll)
	paperdoll.configure(warband)
	paperdoll.changed.connect(func() -> void:
		if paperdoll.selected_merc > 0:
			controller.refresh_gear(paperdoll.selected_merc))
