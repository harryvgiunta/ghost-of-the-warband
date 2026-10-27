extends Node3D
## GHOST OF THE WARBAND: the campaign, as one continuous world.
##
## There used to be three scenes with two doors between them: a cage yard that
## handed the squad to a road, and a road that handed them to a town. Walking was
## not the way anything happened - pressing G on an arch was. This scene is the
## answer: the camp clearing (with the four cages in it), the trail through the
## wood, and the town with its counters, its altar and its expedition gate all
## stand in **one coordinate space**, and the only way between them is to walk.
##
## It owns the things a warband scene must own exactly once - the
## `PossessionController` and its bodies, the camera, the `WarbandHud`, the
## warband screen, the paperdoll, the tutorial card, the loot vacuum, the revive
## channel, the downed-crawl and the branded runner - and it builds three areas
## that bring only their own geometry and their own business:
##
##   * `Camp` - `cage_escape.gd`: the clearing, the cages, the lesson. Its arena
##     is 60 x 68 m of open ground inside the fence line, in the trees.
##   * `Trail` - `escape_run.gd`: the 286 m lane through the wood, with the eight
##     cultists on it. Its first waypoint is the clearing's mouth; there is no
##     wall between the two.
##   * `Town` - `town_hub.gd`: the square at the far end, walled on three sides,
##     open where the trail comes in.
##
## The one door left in the campaign is the expedition gate: it asks for
## `admin_arena.tscn`, and the arena's return lands back here at the town end (see
## `GameFlow`). Nothing else changes scene, and nothing about travel does.
##
## Keys: TAB warband, P paperdoll, G interact, E revive, K manual loot (never
## advertised), R the branded sigil. The camp's lesson adds F1-F5 and `[` `]`.

signal scene_requested(path: String)

const ControllerScript = preload("res://scripts/warband/possession_controller.gd")
const HudScript = preload("res://scripts/warband/warband_hud.gd")
const ScreenScript = preload("res://scripts/warband/warband_screen.gd")
const PaperdollScript = preload("res://scripts/warband/warband_paperdoll.gd")
const CardScript = preload("res://scripts/warband/tutorial_card.gd")
const LootScript = preload("res://scripts/warband/loot_vacuum.gd")
const CrawlScript = preload("res://scripts/warband/crawl_to_safety.gd")
const ReviveScript = preload("res://scripts/warband/revive_channel.gd")
const BrandedScript = preload("res://scripts/warband/branded_runner.gd")
const SquadDriveScript = preload("res://scripts/warband/squad_drive.gd")
const CampScript = preload("res://scripts/warband/cage_escape.gd")
const TrailScript = preload("res://scripts/warband/escape_run.gd")
const TownScript = preload("res://scripts/warband/town_hub.gd")
const RunForestScript = preload("res://scripts/warband/run_forest.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")
const TextureLibrary = preload("res://scripts/world/texture_library.gd")

## How far past the lane's far end the town square stands. The lane ends at the
## town's north gate; the square's centre is this far beyond it.
const TOWN_BEHIND := 30.0
## The floor under everything: wider than the clearing, the lane and the square
## put together, so no body ever walks off the edge of the world (rule 12).
const FLOOR_HALF_WIDTH := 96.0
const FLOOR_FRONT := -402.0
const FLOOR_BACK := 60.0
## How close a body has to stand to something to loot it by hand.
const LOOT_REACH := 2.6
## `ArenaActor` clamps a body to a square around the world origin, and the town
## stands 342 m south of the camp: this is the whole map, with room to spare. A
## bound that fitted one area would wall the world in halfway down the trail.
const BODY_BOUNDS := 380.0
## A watcher only takes an interest in a body it can plausibly reach: without
## this the camp's guards would run the whole trail after a squad that left.
const AGGRO_RADIUS := 55.0
## How long the warband lies in the mud before the world stops pretending.
const WIPE_BEAT := 2.5
const TRAIL_OBJECTIVE := "REACH THE TOWN"
const TRAIL_HINT := "The squad follows you   ·   TAB - warband   ·   P - gear"

var warband
var flow
var controller
var camera: Camera3D
var hud
var screen
var paperdoll
var card
var loot
var revive
var branded
var brand_hud
var squad
## The three areas. Each is the same script its standalone preview uses.
var camp
var trail
var town
var bodies: Array = []
## Every hostile in the world, in one list: the camp's watchers, the six that come
## out of the trees, and the road's cultists. Found by `SquadDrive.retarget` and
## by the squad's fight, appended to by the areas that spawn them.
var guards: Array = []
## Every weapon on the ground, in one list, for the one loot vacuum.
var pickups: Array = []
var squad_ids: Array[int] = []
## "camp" (the campaign's opening) or "town" (a resumed save, or the arena's
## return). Read from `GameFlow.world_start`.
var start_area := "camp"

var _reviving := false
var _prompt_text := ""
var _hint_text := ""
var _roster_elapsed := 0.0
var _wipe_beat := -1.0
var _wiped := false


func _ready() -> void:
	warband = get_node_or_null("/root/Warband")
	if warband == null:
		push_error("WarbandWorld needs the Warband autoload")
		return
	flow = get_node_or_null("/root/GameFlow")
	start_area = _wanted_start()
	_build_floor()
	_build_camera()
	_build_soul()
	_build_ui()
	_build_loot()
	_build_revive()
	_build_squad()
	_build_areas()
	# The soul is wired before it is seated: the very first possession is the
	# camp's first seen body, and a signal connected afterwards would miss it.
	_wire_possession()
	_seat_warband()
	_attach_trail()
	_build_brand()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_write_prompt("", "")
	_announce()
	if flow != null:
		flow.bind(self)


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
	# the controller integrates it; the watchers tick themselves.
	if squad != null:
		squad.drive(delta)
	controller.physics_step(delta)
	SquadDriveScript.retarget(guards, bodies, AGGRO_RADIUS)
	_sync_roster(delta)
	_update_prompt()
	_update_hint()
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
			_try_interact()
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


# --- the world's floor and its night ---------------------------------------

## One floor under the camp, the trail and the town, and one net under that. The
## lane asks for no floor of its own and the town asks for no slab: this is the
## only ground in the world, which is the only way three places can share it.
func _build_floor() -> void:
	var style: WorldStyle = RunForestScript.night_style()
	var ground: Material = TextureLibrary.ground_material(style)
	var centre := Vector3(0.0, -0.3, (FLOOR_FRONT + FLOOR_BACK) * 0.5)
	var size := Vector3(FLOOR_HALF_WIDTH * 2.0, 0.6, FLOOR_BACK - FLOOR_FRONT)
	var floor_body := StaticBody3D.new()
	floor_body.name = "WorldFloor"
	floor_body.position = centre
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	add_child(floor_body)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = ground
	mesh.name = "WorldGround"
	floor_body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	floor_body.add_child(shape)
	# The net: nothing is ever lost, whatever is pushed through a collider.
	var net := StaticBody3D.new()
	net.name = "CatchFloor"
	net.position = Vector3(0.0, -1.6, (FLOOR_FRONT + FLOOR_BACK) * 0.5)
	net.collision_layer = 1
	net.collision_mask = 0
	add_child(net)
	var net_shape := CollisionShape3D.new()
	var net_box := BoxShape3D.new()
	net_box.size = Vector3(FLOOR_HALF_WIDTH * 2.0 + 120.0, 0.4, FLOOR_BACK - FLOOR_FRONT + 120.0)
	net_shape.shape = net_box
	net.add_child(net_shape)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "WorldCamera"
	camera.current = true
	camera.fov = 62.0
	camera.near = 0.08
	camera.far = 260.0
	camera.position = Vector3(0.0, 14.0, 30.0)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, 0.0))


func _build_soul() -> void:
	controller = ControllerScript.new()
	controller.name = "Soul"
	controller.auto_simulate = false
	add_child(controller)
	controller.setup(warband, camera, self)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)
	hud = HudScript.new()
	hud.name = "WarbandHud"
	layer.add_child(hud)
	hud.configure(warband)
	screen = ScreenScript.new()
	screen.name = "WarbandScreen"
	add_child(screen)
	screen.configure(warband, warband.souls)
	screen.possess_requested.connect(_on_possess_requested)
	paperdoll = PaperdollScript.new()
	paperdoll.name = "Paperdoll"
	add_child(paperdoll)
	paperdoll.configure(warband)
	paperdoll.changed.connect(_on_paperdoll_changed)
	card = CardScript.new()
	card.name = "TutorialCard"
	add_child(card)


func _build_loot() -> void:
	loot = LootScript.new()
	loot.name = "Loot"
	add_child(loot)
	loot.setup(warband, self)
	loot.equip_target = Callable(self, "_loot_owner")


func _build_revive() -> void:
	revive = ReviveScript.new()
	revive.name = "Revive"
	add_child(revive)


func _build_brand() -> void:
	branded = BrandedScript.new()
	branded.name = "Branded"
	add_child(branded)
	brand_hud = BrandedHud.attach(self)
	_attach_brand()
	# The blood field is the shared one: a scene that owns its own pool of stains
	# owns its own budget too.
	BloodFx.field_for(self)


# --- the three areas -------------------------------------------------------

## Build the camp and the town into one coordinate space. The camp is at the
## origin; the town stands past the trail's far end, which is measured off the
## lane's own constants so a moved mouth moves the trail with it.
func _build_areas() -> void:
	camp = CampScript.new()
	camp.name = "Camp"
	camp.host = self
	add_child(camp)
	camp.embed(self)

	town = TownScript.new()
	town.name = "Town"
	town.host = self
	town.position = lane_end() + Vector3(0.0, 0.0, -TOWN_BEHIND)
	add_child(town)
	town.embed(self)
	# The expedition gate is the only door the campaign has left.
	town.scene_requested.connect(_on_scene_requested)


## The lane, and the cult standing on it. Built after the warband is seated: two
## of the eight start on the soul's own body, so there has to be one.
func _attach_trail() -> void:
	trail = TrailScript.new()
	trail.name = "Trail"
	add_child(trail)
	trail.attach(self, {
		"offset": trail_offset(),
		"ground": false,
		"closed_start": false,
		"closed_end": false,
		"arch": false,
	})


## Where the lane's first waypoint has to land: the clearing's mouth.
func trail_offset() -> Vector3:
	return CampScript.GATE_POINT - (RunForestScript.LANE_POINTS[0] as Vector3)


## Where the lane's last waypoint lands: the town's own gate.
func lane_end() -> Vector3:
	var points: Array = RunForestScript.LANE_POINTS
	return (points[points.size() - 1] as Vector3) + trail_offset()


# --- the warband -----------------------------------------------------------

## Seed the warband the way the area it starts in expects, spawn one body per
## mercenary at that area's posts, and seat the soul.
func _seat_warband() -> void:
	if start_area == "town":
		town.seed_warband()
		warband.roster.clear_deployment()
		bodies = controller.spawn_mercenaries(town.spawn_posts(), true)
		town.place_warband(bodies)
	else:
		camp.seed_warband()
		bodies = controller.spawn_mercenaries(camp.spawn_posts(), true)
		camp.place_warband(bodies)
	squad_ids.clear()
	for actor in bodies:
		var merc_id: int = controller.merc_of(actor)
		if merc_id > 0 and not squad_ids.has(merc_id):
			squad_ids.append(merc_id)
		# The warband's enemies in this world are the wood's own mobs (layer 2).
		# `ArenaActor` is born hostile to other arena bodies (layer 4), which in a
		# world with nowhere to duel would swing through every watcher for nothing.
		actor.combat.target_mask = 2
		actor.bounds = BODY_BOUNDS
		_wire_crawl(actor)
	if squad != null:
		squad.squad_ids = squad_ids
	if revive != null:
		revive.set_bodies(bodies)
	# The soul goes into a body before anything hunts it: a spectator's camera
	# while two cultists run at nothing is not a first fight.
	var first: int = controller.merc_for_peer(1)
	if first <= 0 and not squad_ids.is_empty():
		first = int(squad_ids[0])
		controller.direct(1, first)
	if start_area == "camp":
		camp.begin_lesson()
	_on_possession_changed(1, controller.merc_for_peer(1))


func _wire_crawl(actor) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var crawl = CrawlScript.new()
	crawl.name = "Crawl"
	add_child(crawl)
	crawl.attach(actor)
	crawl.set_friends(bodies)


## The squad is `squad_drive.gd` - the same one module the cage and the road always
## shared. In the camp it holds the clearing; once the lesson is over the camp
## tells it to escort the soul down the trail.
func _build_squad() -> void:
	squad = SquadDriveScript.new()
	squad.setup(warband, controller, loot)
	squad.squad_ids = squad_ids
	squad.watchers = guards
	squad.pickups = pickups
	squad.following = start_area == "town"
	squad.engage_radius = 34.0
	squad.eligible = Callable(self, "_is_free_ally")


## Who may act as a squadmate this frame: the camp answers with its latches (a
## prisoner still in a cage is not free, and the rescuer is the player's beat
## until the squad is out).
func _is_free_ally(merc_id: int) -> bool:
	if camp == null:
		return merc_id > 0
	return camp.is_free(merc_id)


func _wire_possession() -> void:
	controller.possession_changed.connect(_on_possession_changed)
	controller.transfer_refused.connect(_on_transfer_refused)
	controller.possession_released.connect(_on_possession_released)


func _on_possession_changed(peer_id: int, merc_id: int) -> void:
	if peer_id == 1 and hud != null:
		hud.set_body(controller.active_body(1), warband.roster.name_of(merc_id), merc_id)
	if camp != null:
		camp.note_possession(merc_id)
	_attach_brand()
	_write_prompt("", "")


func _on_transfer_refused(_peer_id: int, merc_id: int, reason: String) -> void:
	if hud != null:
		hud.set_status("%s: %s" % [warband.roster.name_of(merc_id), reason], 2.5)


func _on_possession_released(_peer_id: int, reason: String) -> void:
	if hud != null:
		hud.set_body(null, "", -1)
		hud.set_status("The soul is loose (%s)." % reason, 4.0)
	_attach_brand()


func _on_possess_requested(merc_id: int) -> void:
	screen.close()
	controller.direct(1, merc_id)


func _on_paperdoll_changed() -> void:
	if paperdoll == null or paperdoll.selected_merc <= 0:
		return
	controller.refresh_gear(paperdoll.selected_merc)


# --- the fight the world keeps ---------------------------------------------

## The nearest standing body to a point: what a watcher is aimed at and where a
## reinforcement wave is pointed.
func nearest_standing_body(point: Vector3):
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


## One weapon on the ground, in the one vacuum. The camp's watchers and the
## trail's cultists both drop through here.
func spawn_pickup(item_id: String, at: Vector3) -> void:
	if loot == null or item_id.is_empty():
		return
	var pickup = loot.spawn(item_id, at)
	if pickup == null:
		return
	pickup.taken.connect(_on_pickup_taken)
	pickups.append(pickup)


func _on_pickup_taken(_pickup) -> void:
	if camp != null:
		camp.note_pickup()
	if screen != null:
		screen.refresh()


## Which mercenary a picked-up piece should be worn by, or -1.
func _loot_owner(peer_id: int) -> int:
	var actor = controller.body_for_peer(peer_id)
	if actor == null or not is_instance_valid(actor):
		return -1
	if not bool(actor.get("alive")) or bool(actor.get("downed")):
		return -1
	return controller.merc_for_peer(peer_id)


## The roster is the truth a reload loads: mirror health and downed state while
## the world lasts, so a body that fell on the trail is found exactly as it fell.
func _sync_roster(delta: float) -> void:
	_roster_elapsed += delta
	if _roster_elapsed < 0.4:
		return
	_roster_elapsed = 0.0
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


## A wipe is every body the world fielded down or dead. There is no door to hand
## the warband through any more and nowhere to be carried to: the wood simply
## takes what is left, the roster keeps exactly that, and the squad stops.
func _check_wipe(delta: float) -> void:
	if _wiped:
		return
	if not _all_bodies_out():
		_wipe_beat = -1.0
		return
	# The beat starts once, on the frame the last body goes down, and is only
	# counted down from there: restarting it every frame is a wipe that never
	# finishes.
	if _wipe_beat < 0.0:
		_wipe_beat = WIPE_BEAT
		if hud != null:
			hud.set_status("The warband is down. The wood takes what is left.", WIPE_BEAT)
		if squad != null:
			squad.following = false
	_wipe_beat -= delta
	if _wipe_beat > 0.0:
		return
	_wiped = true
	_sync_roster(1.0)
	if revive != null:
		revive.set_bodies([])


func _all_bodies_out() -> bool:
	if bodies.is_empty():
		return false
	for actor in bodies:
		if not is_instance_valid(actor):
			continue
		if bool(actor.get("alive")) and not bool(actor.get("downed")):
			return false
	return true


# --- interaction -----------------------------------------------------------

## The one `G`: a cage latch in the camp, a counter in the town, a piece of steel
## at your feet - in that order, because that is the order a body meets them.
func _try_interact() -> void:
	if camp != null and camp.try_interact():
		return
	var actor = controller.active_body(1)
	if actor == null or not is_instance_valid(actor):
		if hud != null:
			hud.set_status("The soul is loose. There is nobody to act with.", 2.5)
		return
	if town != null and not town.interact_at(1, actor.global_position).is_empty():
		return
	var pickup = _nearest_pickup()
	if pickup != null:
		_try_loot()
		return
	_interaction_status(actor)


## What `G` says when it found nothing to use.
func _interaction_status(actor) -> void:
	if hud == null:
		return
	var line := ""
	if camp != null:
		line = camp.prompt_line(actor)
	if line.is_empty() and trail != null:
		line = "%s   ·   %d m" % [TRAIL_OBJECTIVE,
			int(round(trail.metres_to_town(actor.global_position)))]
	hud.set_status(line if not line.is_empty() else "Nothing within reach.", 3.0)


func _nearest_pickup():
	var actor = controller.active_body(1)
	if actor == null or not is_instance_valid(actor):
		return null
	var best = null
	var best_distance := LOOT_REACH
	for pickup in pickups:
		if not is_instance_valid(pickup) or bool(pickup.collected):
			continue
		var distance: float = actor.global_position.distance_to(pickup.global_position)
		if distance <= best_distance and not pickup.blocked_for(1):
			best_distance = distance
			best = pickup
	return best


## `K` still works for a human; the squad loots itself and nothing announces it.
func _try_loot() -> void:
	var pickup = _nearest_pickup()
	if pickup == null:
		if hud != null:
			hud.set_status("Nothing within reach.", 1.5)
		return
	var result: Dictionary = loot.quick_loot(pickup, 1)
	if bool(result.get("ok", false)):
		controller.refresh_gear(controller.merc_for_peer(1))
	if hud != null:
		hud.set_status(str(result.get("message", "")), 2.5)


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
		if hud != null:
			hud.set_status("Reviving %s..." % warband.roster.name_of(int(controller.merc_of(target))),
				Contracts.REVIVE_CHANNEL_SECONDS)
	elif hud != null:
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


# --- the one HUD line ------------------------------------------------------

## The prompt: the counter under the body's nose, then the camp's lesson, then the
## metres left to the town.
func _update_prompt() -> void:
	if hud == null or controller == null:
		return
	if _panel_open() or _reviving:
		return
	var actor = controller.active_body(1)
	var text := ""
	# The counter under the body's nose wins over the camp's lesson, and the
	# lesson wins over the road: a body can only be standing in one of them.
	if town != null and town.in_square(actor):
		text = town.prompt_line(actor)
	if text.is_empty() and camp != null:
		text = camp.prompt_line(actor)
	if text.is_empty() and trail != null and actor != null and is_instance_valid(actor):
		text = "%s   ·   %d m" % [TRAIL_OBJECTIVE,
			int(round(trail.metres_to_town(actor.global_position)))]
	_write_prompt(text, _hint_text)


## The key line: the lesson's, or the counter's, or the road's.
func _update_hint() -> void:
	if hud == null or controller == null:
		return
	var actor = controller.active_body(1)
	var text := ""
	if town != null and town.in_square(actor):
		text = town.hint_line(actor)
	if text.is_empty() and camp != null:
		text = camp.hint_line(actor)
	if text.is_empty():
		text = TRAIL_HINT
	_write_prompt(_prompt_text, text)


func _write_prompt(prompt: String, hint: String) -> void:
	if hud == null:
		return
	if prompt != _prompt_text:
		_prompt_text = prompt
		hud.set_prompt(prompt)
	if hint != _hint_text:
		_hint_text = hint
		hud.set_hint(hint)


## What the HUD says the trail is, for a test that must not read a private label.
func objective_text() -> String:
	return TRAIL_OBJECTIVE


func prompt_text() -> String:
	return _prompt_text


func _hide_panels() -> void:
	if screen != null and screen.is_open():
		screen.close()
	if paperdoll != null and paperdoll.is_open():
		paperdoll.close()
	if town != null:
		town.close_panels()


func _panel_open() -> bool:
	if (screen != null and screen.is_open()) or (paperdoll != null and paperdoll.is_open()):
		return true
	return town != null and town.panels_open()


# --- the town's readout ----------------------------------------------------
#
# The world *is* the scene the town's services stand in, so the services are
# answered from here: the altar, the counters, the stash and the gate are the
# town area's own objects, forwarded rather than duplicated.

var altar:
	get:
		return town.altar if town != null else null
var gate:
	get:
		return town.gate if town != null else null
var quartermaster:
	get:
		return town.quartermaster if town != null else null
var stash_chest:
	get:
		return town.stash_chest if town != null else null
var recruiter_desk:
	get:
		return town.recruiter_desk if town != null else null
var quartermaster_desk:
	get:
		return town.quartermaster_desk if town != null else null
var signpost:
	get:
		return town.signpost if town != null else null
var flame:
	get:
		return town.flame if town != null else null
var fire_light:
	get:
		return town.fire_light if town != null else null


func service_at(point: Vector3) -> String:
	return town.service_at(point) if town != null else ""


func service_point(service: String) -> Vector3:
	return town.service_point(service) if town != null else Vector3.ZERO


func interact_at(peer_id: int, point: Vector3) -> String:
	return town.interact_at(peer_id, point) if town != null else ""


# --- the readout -----------------------------------------------------------

## What this world is, measured: the three areas' numbers, the budget it holds
## itself to, and the ground a body can stand on.
func stats() -> Dictionary:
	return {
		"nodes": _count_nodes(self),
		"draws": _count_type(self, "MultiMeshInstance3D"),
		"meshes": _count_type(self, "MeshInstance3D"),
		"lights": _count_type(self, "OmniLight3D"),
		"shapes": _count_type(self, "CollisionShape3D"),
		"bodies": bodies.size(),
		"guards": guards.size(),
		"pickups": pickups.size(),
		"start": start_area,
		"clearing": camp.clearing.get("clear", Vector2.ZERO) if camp != null else Vector2.ZERO,
		"clearing_trees": int(camp.clearing.get("trees", 0)) if camp != null else 0,
		"clearing_bushes": int(camp.clearing.get("bushes", 0)) if camp != null else 0,
		"lane_length": float(trail.forest.get("length", 0.0)) if trail != null else 0.0,
		"lane_width": float(trail.forest.get("width", 0.0)) if trail != null else 0.0,
		"torches": (trail.forest.get("torches", []) as Array).size() if trail != null else 0,
		"town_wood": int(town.wood.get("trees", 0)) if town != null else 0,
		"town_at": town.global_position if town != null else Vector3.ZERO,
	}


## The point the trail's far end stands at - the town's north gate.
func town_gate() -> Vector3:
	return trail.town_gate() if trail != null else Vector3.ZERO


## The camp's clearing: 60 x 68 m of open ground inside the fence line.
func clearing_size() -> Vector2:
	return camp.clearing.get("clear", Vector2.ZERO) if camp != null else Vector2.ZERO


func _count_nodes(node: Node) -> int:
	var total := 0
	for child in node.get_children():
		total += 1 + _count_nodes(child)
	return total


func _count_type(node: Node, type_name: String) -> int:
	var total := 0
	for child in node.get_children():
		if child.is_class(type_name):
			total += 1
		total += _count_type(child, type_name)
	return total


# --- doors -----------------------------------------------------------------

## The expedition gate asked for the field; the world owns the only door.
func _on_scene_requested(path: String) -> void:
	scene_requested.emit(path)


# --- startup ---------------------------------------------------------------

## Where the campaign puts this body down: the camp for a fresh run, the town for
## a resumed save or for the arena's return.
func _wanted_start() -> String:
	if flow == null:
		return "camp"
	var wanted := str(flow.world_start)
	return "town" if wanted == "town" else "camp"


func _announce() -> void:
	var readout: Dictionary = stats()
	print("WARBAND_WORLD_READY start=%s bodies=%d guards=%d lane=%.1f torches=%d trees=%d nodes=%d draws=%d shapes=%d"
		% [start_area, bodies.size(), guards.size(), float(readout["lane_length"]),
			int(readout["torches"]), int(readout["clearing_trees"]) + int(readout["town_wood"]),
			int(readout["nodes"]), int(readout["draws"]), int(readout["shapes"])])
