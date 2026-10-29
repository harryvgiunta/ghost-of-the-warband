extends Node3D
## GHOST OF THE WARBAND: the campaign, as one continuous world.
##
## There used to be three scenes with two doors between them: a cage yard that
## handed the squad to a road, and a road that handed them to a town. Walking was
## not the way anything happened - pressing G on an arch was. This scene is the
## answer: the camp in the deep wood (with the four cages in it), the trail
## through the wood, and the town with its counters, its altar and its expedition
## gate all stand in **one coordinate space**, and the only way between them is to
## walk. They also stand on **one ground**: `terrain.gd`'s heightfield, with the
## camp pocket and the town square padded flat into a rolling forest floor.
##
## It owns the things a warband scene must own exactly once - the
## `PossessionController` and its bodies, the camera, the `WarbandHud`, the
## warband screen, the paperdoll, the tutorial card, the ability scene, the
## campaign menu, the loot vacuum, the revive channel, the downed-crawl, the
## branded runner, and the wilderness band on the way out - and it builds three
## areas that bring only their own geometry and their own business:
##
##   * `Camp` - `cage_escape.gd`: the ragged pocket in the wood, the cages, the
##     lesson. No fence and no road: a camp with trees standing in it, and a gap
##     in those trees at its front line.
##   * `Trail` - `escape_run.gd`: the 915 m way through the wood, with the twenty
##     cultists on it. There is no lane: a faint worn line between trunks that
##     stand in it, marked by a pair of torches every twelve metres. Its first
##     waypoint is `Camp.CAMP_TO_ROAD_METRES` of ordinary wood past the camp's
##     mouth, so the way on is a long walk and not the other side of a hedge.
##   * `Town` - `town_hub.gd`: the square at the far end, walled on three sides,
##     open where the trail comes in.
##
## The one door left in the campaign is the expedition gate: it asks for
## `admin_arena.tscn`, and the arena's return lands back here at the town end (see
## `GameFlow`). Nothing else changes scene, and nothing about travel does.
##
## Keys: O warband, ESC the campaign menu (resume, save, load, settings, leave,
## quit), TAB quick weapon swap, P paperdoll, G interact and the revive hold,
## K manual loot (never advertised), R the branded sigil, X shoulder swap.
## Q and E are held to strafe, WASD to walk, so neither is a press key. The camp's
## lesson adds F1-F5 and `[` `]`.

signal scene_requested(path: String)

const ControllerScript = preload("res://scripts/warband/possession_controller.gd")
const HudScript = preload("res://scripts/warband/warband_hud.gd")
const ScreenScript = preload("res://scripts/warband/warband_screen.gd")
## The `P` panel is the corpse screen, which extends the paperdoll: a living body's
## gear and a dead body's pockets are the same panel, so every equip path, the
## change signal and `is_open()` are unchanged.
const PaperdollScript = preload("res://scripts/warband/corpse_loot_panel.gd")
const GearDropScript = preload("res://scripts/warband/gear_drop.gd")
const CardScript = preload("res://scripts/warband/tutorial_card.gd")
const LootScript = preload("res://scripts/warband/loot_vacuum.gd")
const CrawlScript = preload("res://scripts/warband/crawl_to_safety.gd")
const ReviveScript = preload("res://scripts/warband/revive_channel.gd")
const BrandedScript = preload("res://scripts/warband/branded_runner.gd")
const SquadDriveScript = preload("res://scripts/warband/squad_drive.gd")
## The scene half of the item skills: one node for the whole campaign, exactly
## as `main.gd` keeps one for the frontier. Without it a warband body could start
## a skill's clock and never fire the arrow or the spell the clock was counting.
const AbilitiesScript = preload("res://scripts/warband/warband_abilities.gd")
## The campaign's Escape window. The frontier's quick menu belongs to a level of
## that game; the world opens this one, which writes the same warband save and
## leaves for the same title.
const MenuScript = preload("res://scripts/warband/warband_menu.gd")
## The deep-wood band: two packs of four briar wolves, both hundreds of metres
## off the route. They spawn after the warband is seated, so a wolf's first target
## is a real body.
const WildernessScript = preload("res://scripts/warband/wilderness.gd")
const TorchScript = preload("res://scripts/warband/torch_light.gd")
const CampScript = preload("res://scripts/warband/cage_escape.gd")
const TrailScript = preload("res://scripts/warband/escape_run.gd")
const TownScript = preload("res://scripts/warband/town_hub.gd")
const RunForestScript = preload("res://scripts/warband/run_forest.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
## Bows and thrown steel. The warband mode had no projectile spawner at all: a
## body could draw a bow, release it, and the arrow simply never existed. These are
## the same classes the frontier and the arena spawn, with the campaign's target
## layers.
const ArrowScript = preload("res://scripts/arrow.gd")
const ThrownScript = preload("res://scripts/thrown_weapon.gd")
const CombatScript = preload("res://scripts/combat.gd")
const ArcherScript = preload("res://scripts/archer.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")
const TerrainScript = preload("res://scripts/warband/terrain.gd")

## How far past the lane's far end the town square stands. The lane ends at the
## town's north gate; the square's centre is this far beyond it.
const TOWN_BEHIND := 30.0
## Half the town's flat pad: the square's walls plus a stride, so a body standing
## on any part of the square is standing on level ground.
const TOWN_PAD := 23.0
## How close a body has to stand to something to loot it by hand.
const LOOT_REACH := 2.6
## `ArenaActor` clamps a body to a square around the world origin, and the town
## stands well over a kilometre south of the camp: this is the whole map, with room
## to spare. A bound that fitted one area would wall the world in halfway down the
## trail.
const BODY_BOUNDS := 1400.0
## A watcher only takes an interest in a body it can plausibly reach: without
## this the camp's guards would run the whole trail after a squad that left.
const AGGRO_RADIUS := 55.0
## The source a wilderness blow is booked under, beside the camp's watchers (90)
## and the trail's cultists (91): damage scaling, the threat a body remembers and
## the death record all name an attacker family by number, and the band on the way
## out is its own family.
const WILDERNESS_SOURCE := 92
## What a warband missile may strike: the world (1) and the wood's own bodies (2).
## A squadmate is deliberately not in the set - the warband's swords do not cut
## its own, and neither do its arrows.
const PROJECTILE_HIT_MASK := 1 | 2
## A ceiling on live missiles, oldest freed first, so a long trail fight cannot
## grow the tree without bound.
const PROJECTILE_CAP := 64
## How long the warband lies in the mud before the world stops pretending.
const WIPE_BEAT := 2.5
const TRAIL_OBJECTIVE := "REACH THE TOWN"
const TRAIL_HINT := "The squad follows you   ·   O - warband   ·   P - gear"
## The key line under a prompt that names the revive hold.
const G_REVIVE_HINT := "hold G   ·   five seconds, and a fifth of a breath to walk on"
## The band a fallen squadmate is taught in: close enough that the player is in
## the fight that put them down, wide enough that the card does not wait for a
## body to fall at their feet.
const REVIVE_LESSON_RADIUS := 12.0
const REVIVE_LESSON_STEP := "lesson_revive"
## How often the world asks what part it plays in a co-op campaign. The flow is
## still offline when `_ready` runs - the session is seated at the end of it - so
## a client only learns its role from a poll, never from a read at startup.
const ROLE_POLL_SECONDS := 1.0
## The door the menu's "exit to title" row opens.
const TITLE_SCENE := "res://title.tscn"
## The one card that is not a beat of a chapter: a squadmate going down can
## happen anywhere, in the camp or a mile down the trail, so it carries no numeral.
const REVIVE_LESSON := {
	"kicker": "THE FALLEN  /  THE WARBAND",
	"title": "A squadmate is down - bring them back",
	"body": "A body on its chest is not dead yet. It bleeds for thirty seconds, and for every one of them it can be brought back: stand over your squadmate and HOLD G - not a tap. Five full seconds, and a blow that lands on you breaks the channel.",
	"keys": "HOLD G  -  five seconds on a fallen body",
	"footnote": "Let go and the work is lost. A body that bleeds out keeps its date with the dirt: the roster will not stand it back up.",
}

## The wrong-way sign. The trail is about 1070 m long at the camp's mouth, so a
## body is only taught the road once it has stood within 950 m of town - the
## escape's first steps never raise it. Running back up the trail from there shows
## the banner at 1000 m, and turning round drops it under 980: the gap between the
## two is the sign's hysteresis, so a body on the line does not flicker.
const WRONG_WAY_ARM_METRES := 950.0
const WRONG_WAY_TRIGGER_METRES := 1000.0
const WRONG_WAY_CLEAR_METRES := 980.0
const WRONG_WAY_TEXT := "You're running the wrong way!"
## How high over the gap in the trees the roadside word stands. High enough to be
## read from the trail's first torch, low enough not to sit in the canopy.
const WRONG_WAY_SIGN_HEIGHT := 4.2

## The damage lesson: a bandage is three seconds of wrapping and 35 health, and it
## is taught the first time a body is badly hurt with nobody close enough to
## punish the channel. The radius is a fight's breath, not the whole wood.
const BANDAGE_LESSON_STEP := "lesson_bandage"
const BANDAGE_LESSON_HEALTH := 0.6
const BANDAGE_LESSON_RADIUS := 22.0
const BANDAGE_LESSON := {
	"kicker": "THE WOUND  /  THE WARBAND",
	"title": "You've been damaged",
	"body": "A blade has opened you and nothing is close enough to finish it. Press 6 to bind a bandage: three seconds of wrapping and 35 health back - and any blow that lands breaks the channel, so bind in the quiet, not in the fight.",
	"keys": "6  -  bandage        ·        three seconds, +35 health",
	"footnote": "A bandage only works while you are left alone. Break the fight off, then dress the wound.",
}

## The soul's own body on the floor. It is the one card that is about the player
## rather than the squad: nobody is coming for a body the player did not ask to
## save, so both ways out - an ally's `G`, or jumping - are named.
const DOWNED_LESSON_STEP := "lesson_downed"
const DOWNED_LESSON := {
	"kicker": "THE DOWNED  /  THE WARBAND",
	"title": "You've been downed!",
	"body": "Your body is on its chest and bleeding. An ally can bring it back: stand over it and HOLD G for five seconds. Or leave it - step into another body with [ ] or F1..F8, and come back for the one you left behind.",
	"keys": "HOLD G  -  an ally revives you        ·        [  ]  or  F1 .. F8  -  take another body",
	"footnote": "The body you step out of keeps bleeding. Do not forget it - it is still yours to save.",
}

var warband
var flow
var controller
var camera: Camera3D
var hud
## The one ability scene for the campaign: bodies are bound as they are adopted.
var abilities
## Escape's window: the warband's own quick menu, on a layer above the HUD.
var menu
var screen
var paperdoll
var card
var loot
var revive
var branded
var brand_hud
var squad
## The band between the camp's mouth and the lane. Built after the warband is
## seated, because a wolf's first target is a real body.
var wilderness
## The three areas. Each is the same script its standalone preview uses.
var camp
var trail
var town
var bodies: Array = []
## Every hostile in the world, in one list: the camp's watchers, the six that come
## out of the trees, and the trail's cultists. Found by `SquadDrive.retarget` and
## by the squad's fight, appended to by the areas that spawn them.
var guards: Array = []
## Every weapon on the ground, in one list, for the one loot vacuum.
var pickups: Array = []
var squad_ids: Array[int] = []
## "camp" (the campaign's opening) or "town" (a resumed save, or the arena's
## return). Read from `GameFlow.world_start`.
var start_area := "camp"

var _crawls: Array = []
## Every arrow and thrown blade in flight. Nothing else in this mode owns them.
var projectiles: Array = []
var _reviving := false
var _prompt_text := ""
var _hint_text := ""
## The wrong-way sign's own memory: whether the road has been learned yet (armed),
## whether the banner is up, and the word standing at the gap in the trees. Both
## the banner and the sign are driven from the one poll, so they cannot disagree.
var _wrong_way_armed := false
var _wrong_way := false
var _wrong_way_sign: Label3D
## The player's own body went down while a card was up: the card is raised on the
## first frame the tree is free again rather than written over somebody's read.
var _downed_card_pending := false
var _roster_elapsed := 0.0
var _wipe_beat := -1.0
var _wiped := false
## True once the flow says this machine is a guest. A client fields the same
## bodies but does not own the world: it writes no checkpoint, runs no squad AI
## and never swings a mob the session has marked as a replica.
var _client := false
## Seconds since the last role poll; `flow.warband_role()` costs a string compare
## and a socket read, so it is asked once a second rather than every physics tick.
var _role_elapsed := 0.0
## What the heightfield was baked to: `{triangles, cell, min, max}`.
var _terrain: Dictionary = {}
## Where the town square stands, worked out before the ground so its pad can be
## cut into the field.
var _town_at := Vector3.ZERO


func _ready() -> void:
	warband = get_node_or_null("/root/Warband")
	if warband == null:
		push_error("WarbandWorld needs the Warband autoload")
		return
	flow = get_node_or_null("/root/GameFlow")
	start_area = _wanted_start()
	_build_ground()
	_build_camera()
	_build_soul()
	# The ability scene exists before the bodies do: `_adopt_bodies()` binds each
	# one as it is seated, and a body bound after its first cue would swallow it.
	_build_abilities()
	_build_ui()
	_build_menu()
	_build_loot()
	_build_revive()
	_build_squad()
	_build_areas()
	_build_wrong_way_sign()
	# The soul is wired before it is seated: the very first possession is the
	# camp's first seen body, and a signal connected afterwards would miss it.
	_wire_possession()
	_seat_warband()
	# The band comes after the seating: a wolf's first target is a real body.
	_build_wilderness()
	_attach_trail()
	_build_brand()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_write_prompt("", "")
	_announce()
	if flow != null:
		flow.bind(self)
		# `bind()` is where the flow seats the session, so the role is knowable
		# here - and it is the last moment a guest can act before the poll: a
		# camp opening raises its pause card inside `_seat_warband`, and a paused
		# tree runs no physics tick to poll from.
		if str(flow.warband_role()) == "client":
			_become_client()


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
	# The role is polled, never read once: the flow seats the session at the end
	# of `_ready`, so at startup the answer is honestly "offline" and a guest only
	# discovers itself a moment later.
	_poll_role(delta)
	# The squad's brains write a body's intent for this frame, so they run before
	# the controller integrates it; the watchers tick themselves. A guest does not
	# run them: its bodies are the host's to drive, and a second brain on the same
	# body is a fight with itself.
	_sync_crawl_control()
	if squad != null and not _client:
		squad.drive(delta)
	controller.physics_step(delta)
	# A replica is a mob the session is showing, not one this machine owns: it is
	# handed no target, so no local sense ever wakes it behind the host's back.
	SquadDriveScript.retarget(_local_guards(), bodies, AGGRO_RADIUS)
	_sync_roster(delta)
	_update_prompt()
	_update_hint()
	_push_downed_card()
	_update_bandage_card()
	_update_wrong_way()
	_check_checkpoints()
	_check_wipe(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_O:
			if screen.is_open():
				screen.close()
			else:
				_hide_panels()
				screen.open()
			get_viewport().set_input_as_handled()
		KEY_TAB:
			_swap_weapon_set()
			get_viewport().set_input_as_handled()
		KEY_P:
			if paperdoll.is_open():
				paperdoll.close()
			else:
				_hide_panels()
				paperdoll.open(controller.merc_for_peer(1))
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			# The warband's window is the menu: close it, close whatever panel is
			# under it, or open it. The menu is the settings page's door now, so
			# Escape no longer opens a second, narrower settings window.
			if menu != null and menu.is_open():
				menu.close()
				get_viewport().set_input_as_handled()
			elif _panel_open():
				_hide_panels()
				get_viewport().set_input_as_handled()
			else:
				_open_menu()
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


## `G` held is the revive channel: hold it for `REVIVE_CHANNEL_SECONDS` (five) on a
## downed squadmate and the body stands up on `REVIVE_HEALTH_FRACTION` of its pool.
## The key is consumed on press only when a downed body is actually in reach, so a
## tap of `G` still cuts a latch, opens a counter or searches a corpse when nobody
## is on the floor beside you; releasing early drops the work and spends nothing.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.echo or event.keycode != KEY_G:
		return
	if event.pressed:
		if _reviving or _revive_target() != null:
			_begin_revive()
			get_viewport().set_input_as_handled()
	elif _reviving:
		_cancel_revive()
		get_viewport().set_input_as_handled()


# --- the world's ground and its night --------------------------------------

## The ground the camp, the trail and the town all stand on: one heightfield
## (`terrain.gd`), baked once, with one trimesh collider and one `height_at` the
## whole world samples. The camp pocket and the town square are padded flat inside
## it; the walk between them rolls over the wood's own rises and hollows.
##
## Under it, the net: a catch floor below the lowest point of the field, so a body
## pushed through a collider lands somewhere rather than falling out of the map.
func _build_ground() -> void:
	var style: WorldStyle = RunForestScript.night_style()
	_town_at = lane_end() + Vector3(0.0, 0.0, -TOWN_BEHIND)
	var pads := [
		{"rect": Rect2(-CampScript.YARD_HALF_WIDTH, CampScript.YARD_FRONT,
			CampScript.YARD_HALF_WIDTH * 2.0,
			CampScript.YARD_BACK - CampScript.YARD_FRONT),
			"y": TerrainScript.PAD_Y, "blend": 14.0},
		{"rect": Rect2(_town_at.x - TOWN_PAD, _town_at.z - TOWN_PAD,
			TOWN_PAD * 2.0, TOWN_PAD * 2.0), "y": TerrainScript.PAD_Y, "blend": 16.0},
	]
	# What feet have worn: the gap in the camp's wood and the line of torches. The
	# far side of the town's square is paved, so nothing there needs a path.
	var worn := [
		{"points": _corridor_line(), "half_width": 2.6},
		{"points": _lane_line(), "half_width": 3.2},
	]
	_terrain = TerrainScript.build(self, style, pads, worn)
	# The net: a slab under the strip's lowest point, as wide and as long as the
	# field it protects. Nothing that slips through the mesh is ever lost.
	var net := StaticBody3D.new()
	net.name = "CatchFloor"
	net.position = Vector3(
		TerrainScript.ORIGIN.x + float(TerrainScript.COLS) * TerrainScript.CELL * 0.5,
		TerrainScript.floor_bottom() - 2.0,
		TerrainScript.ORIGIN.y + float(TerrainScript.ROWS) * TerrainScript.CELL * 0.5)
	net.collision_layer = 1
	net.collision_mask = 0
	add_child(net)
	var net_shape := CollisionShape3D.new()
	var net_box := BoxShape3D.new()
	net_box.size = Vector3(float(TerrainScript.COLS) * TerrainScript.CELL + 120.0, 0.4,
		float(TerrainScript.ROWS) * TerrainScript.CELL + 120.0)
	net_shape.shape = net_box
	net.add_child(net_shape)


## The worn line between the camp's mouth and the lane's first waypoint, in world
## space: the ground's only idea of where the way out is.
func _corridor_line() -> PackedVector3Array:
	var line := PackedVector3Array()
	line.append(CampScript.GATE_POINT)
	line.append(Vector3(CampScript.GATE_POINT.x, 0.0,
		CampScript.GATE_POINT.z - CampScript.CAMP_TO_ROAD_METRES))
	return line


## The lane, in world space, so the trodden ground follows the same line the
## torches and the trunks do.
func _lane_line() -> PackedVector3Array:
	var offset := trail_offset()
	var line := PackedVector3Array()
	for point in RunForestScript.LANE_POINTS:
		line.append((point as Vector3) + offset)
	return line


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


## The scene half of the skills, built once under the world. `setup()` keeps the
## world it spawns into and the controller it reads the soul from; `bind_body()`
## is called by `_adopt_bodies()` for every body the world seats.
func _build_abilities() -> void:
	abilities = AbilitiesScript.new()
	abilities.name = "Abilities"
	add_child(abilities)
	abilities.setup(self, controller)


## Escape's window, on a layer above the HUD so the dim and the ledger cover the
## bars. It pauses nothing: the world is one continuous place and the menu only
## owns the pointer while it is up.
func _build_menu() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MenuLayer"
	# Above the HUD's own `LAYER` (6): the menu's dim must sit over the bars, and
	# below the tutorial card's 8, because the card is the topmost read in the game.
	layer.layer = 7
	add_child(layer)
	menu = MenuScript.new()
	menu.name = "WarbandMenu"
	layer.add_child(menu)
	menu.configure("EXIT TO TITLE")
	menu.resumed.connect(_on_menu_resumed)
	menu.load_requested.connect(_on_menu_load_requested)
	menu.exit_requested.connect(_on_menu_exit_requested)
	menu.quit_requested.connect(_on_menu_quit_requested)


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
	# A checkpoint past the cages opens the world with the lesson already behind
	# it: the cages hang open and empty and the pair are never fielded.
	if _resuming_trail():
		camp.prepare_resume()
	add_child(camp)
	camp.embed(self)

	town = TownScript.new()
	town.name = "Town"
	town.host = self
	town.position = _town_at
	add_child(town)
	town.embed(self)
	# The expedition gate is the only door the campaign has left.
	town.scene_requested.connect(_on_scene_requested)


## The word that answers the banner in the world itself: a body walking back up
## the trail sees it standing over the gap in the trees it just came through. It
## billsboards towards the camera and reads through the wood, because a sign that
## a body has to find with its nose is not a sign.
func _build_wrong_way_sign() -> void:
	var word := Label3D.new()
	word.name = "WrongWaySign"
	word.text = WRONG_WAY_TEXT
	word.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	word.no_depth_test = true
	# About a metre of letter height over a dozen metres of line: a hanging sign
	# the size of a hut, because it stands in the trees rather than on a wall.
	word.pixel_size = 0.0125
	word.font_size = 72
	word.outline_size = 16
	word.modulate = Color(0.99, 0.78, 0.26)
	word.outline_modulate = Color(0.42, 0.03, 0.02, 0.95)
	word.position = CampScript.GATE_POINT + Vector3(0.0, WRONG_WAY_SIGN_HEIGHT, 0.0)
	word.visible = false
	add_child(word)
	_wrong_way_sign = word


## The lane, and the cult standing on it. Built after the warband is seated: two
## of the eight start on the soul's own body, so there has to be one.
func _attach_trail() -> void:
	trail = TrailScript.new()
	trail.name = "Trail"
	add_child(trail)
	trail.attach(self, {
		"offset": trail_offset(),
		"ground": false,
		"arch": false,
	})


## The band between the camp's mouth and the lane, and the culler that keeps a
## wolf the squad walked past from costing a tick behind the fog. It positions
## itself off the camp's own mouth and the lane's own points, so a moved gap in
## the trees moves the band with it.
func _build_wilderness() -> void:
	wilderness = WildernessScript.new()
	wilderness.name = "Wilderness"
	add_child(wilderness)
	# `setup()` appends every wolf to `guards`, the world's one hostile list, so
	# `retarget` and the squad find them without a second registry.
	wilderness.setup(self)


## Where the lane's first waypoint lands: not the camp's mouth, but
## `Camp.CAMP_TO_ROAD_METRES` of ordinary wood past it. The camp owns that number
## and the geometry builds the corridor through the trees to match it, so the way
## out cannot creep up on the cages again.
func trail_offset() -> Vector3:
	var trail_start := Vector3(CampScript.GATE_POINT.x, 0.0,
		CampScript.GATE_POINT.z - CampScript.CAMP_TO_ROAD_METRES)
	return trail_start - (RunForestScript.LANE_POINTS[0] as Vector3)


## Where the lane's last waypoint lands: the town's own gate.
func lane_end() -> Vector3:
	var points: Array = RunForestScript.LANE_POINTS
	return (points[points.size() - 1] as Vector3) + trail_offset()


# --- the warband -----------------------------------------------------------

## Seed the warband the way the area it starts in expects, spawn one body per
## mercenary at that area's posts, and seat the soul. A resumed campaign opens on
## its checkpoint instead: the same roster and gear the save holds, standing on
## the ground the bookmark names.
func _seat_warband() -> void:
	if start_area == "checkpoint" and warband.has_checkpoint():
		_seat_checkpoint()
	elif start_area == "town":
		town.seed_warband()
		warband.roster.clear_deployment()
		bodies = controller.spawn_mercenaries(town.spawn_posts(), true)
		town.place_warband(bodies)
	else:
		camp.seed_warband()
		bodies = controller.spawn_mercenaries(camp.spawn_posts(), true)
		camp.place_warband(bodies)
	_adopt_bodies()
	if start_area == "camp":
		camp.begin_lesson()
	_on_possession_changed(1, controller.merc_for_peer(1))


## The bookmark is a place the warband already stood: the town's own fire ring,
## or a ring of posts a few metres around the trail point it holds. Nothing is
## seeded, dressed or re-taught - the roster is what the save says it is.
func _seat_checkpoint() -> void:
	if warband.checkpoint_area() == "town":
		town.seed_warband()
		warband.roster.clear_deployment()
		bodies = controller.spawn_mercenaries(town.spawn_posts(), true)
		town.place_warband(bodies)
		return
	var ground := _checkpoint_ground()
	var posts := _spawn_ring(ground, maxi(1, warband.alive_merc_ids().size()))
	bodies = controller.spawn_mercenaries(posts, true)
	camp.place_resumed(bodies)
	# The squad is out of the camp on a resumed trail: it walks with the soul.
	if squad != null:
		squad.following = true
		squad.engage_radius = 34.0


## Where a trail bookmark stands on the ground. Zero is a marker from a file that
## named no position: the lane's first stretch past the camp is the safe answer.
func _checkpoint_ground() -> Vector3:
	var point: Vector3 = warband.checkpoint_position()
	if point.is_zero_approx():
		point = Vector3(CampScript.GATE_POINT.x, 0.0, CampScript.GATE_POINT.z - 55.0)
	return TerrainScript.grounded(point)


## A ring of standable posts around a point, so a resumed squad does not spawn
## inside one body's capsule.
func _spawn_ring(at: Vector3, count: int) -> Array[Vector3]:
	var posts: Array[Vector3] = []
	for index in count:
		var angle := TAU * float(index) / float(maxi(1, count))
		posts.append(TerrainScript.grounded(
			at + Vector3(cos(angle) * 1.8, 0.0, sin(angle) * 1.8)))
	if posts.is_empty():
		posts.append(at)
	return posts


## Wire the bodies this scene just spawned: the squad list, the mob layer, the
## crawl, the projectiles, the downed/killed drops and the torch. Shared by every
## way the world can be seated, so a resume cannot forget one of them.
func _adopt_bodies() -> void:
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
		# The body's skill clock needs a scene listener before its first cue, or
		# the beat fires into nothing: one scene node, bound once per body.
		if abilities != null:
			abilities.bind_body(actor)
		_wire_crawl(actor)
		_wire_projectiles(actor)
		# A body that goes down lets go of its steel. Both the knock-down and the
		# bleed-out walk the same hook, so a body that dies without ever being
		# downed (a finisher, a lethal blow) drops exactly as one that fell does.
		if merc_id > 0:
			actor.downed_started.connect(_on_body_downed.bind(actor, merc_id))
			actor.killed.connect(_on_body_killed.bind(actor, merc_id))
		# A worn hand torch is light, and light belongs to the body carrying it.
		if merc_id > 0:
			var torch := TorchScript.new()
			actor.add_child(torch)
			torch.setup(actor, merc_id, warband)
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


## Every body's bowstring and throwing hand. A body that is not authoritative is
## somebody's prediction: it draws and releases on screen, and only the simulation
## that owns it spawns the missile that can hurt anyone.
func _wire_projectiles(actor) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var combat = actor.get("combat")
	if combat == null:
		return
	if not combat.shot.is_connected(_on_body_shot):
		combat.shot.connect(_on_body_shot.bind(actor))
	if not combat.thrown.is_connected(_on_body_thrown):
		combat.thrown.connect(_on_body_thrown.bind(actor))


## A bow released. The shot leaves along the camera's crosshair ray - the same ray
## the controller aimed the body down - and carries the bow's own charge damage.
func _on_body_shot(origin: Vector3, direction: Vector3, speed: float, charge: float,
		actor) -> void:
	if not _projectile_authority(actor):
		return
	var rig = actor.rig
	var damage := float(CombatScript.damage_for(int(rig.bow_index), charge,
		rig.ranged_scale()))
	var arrow := ArrowScript.new()
	arrow.source_id = int(actor.slot)
	arrow.shooter = actor
	arrow.hit_mask = PROJECTILE_HIT_MASK
	arrow.authoritative_damage = true
	add_child(arrow)
	arrow.launch(origin, direction, speed, damage, _projectile_exclude(actor),
		rig.last_arrow_visual_origin, 0)
	_keep_projectile(arrow)


## A blade let go of mid-swing. Same authority, same layers.
func _on_body_thrown(origin: Vector3, direction: Vector3, speed: float, charge: float,
		weapon: String, weapon_index: int, actor) -> void:
	if not _projectile_authority(actor):
		return
	var rig = actor.rig
	var damage := float(CombatScript.throw_damage(weapon, weapon_index, charge,
		rig.throw_scale()))
	var thrown := ThrownScript.new()
	thrown.weapon = weapon
	thrown.weapon_index = weapon_index
	thrown.source_id = int(actor.slot)
	thrown.shooter = actor
	thrown.hit_mask = PROJECTILE_HIT_MASK
	thrown.authoritative_damage = true
	if weapon == "dagger":
		thrown.blade_length = float(ArcherScript.dagger_profile(weapon_index).length)
	else:
		thrown.blade_length = float(ArcherScript.SWORD_DATA[
			clampi(weapon_index, 0, ArcherScript.SWORD_DATA.size() - 1)].length)
	add_child(thrown)
	thrown.launch(origin, direction, speed, damage, _projectile_exclude(actor))
	_keep_projectile(thrown)


## Who may spawn a live missile: only the body whose simulation is this machine's.
func _projectile_authority(actor) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	if not bool(actor.get("authoritative")):
		return false
	return bool(actor.get("alive"))


## The bodies and shields a shot must not hit on its first frame: the hand that
## spent it.
func _projectile_exclude(actor) -> Array[RID]:
	var excluded: Array[RID] = []
	if actor != null and is_instance_valid(actor):
		excluded.append(actor.get_rid())
		var shield = actor.rig.active_shield if actor.get("rig") != null else null
		if is_instance_valid(shield):
			excluded.append(shield.get_rid())
	return excluded


## Book a missile in the one list and hold the list to its cap.
func _keep_projectile(missile) -> void:
	if missile == null:
		return
	for index in range(projectiles.size() - 1, -1, -1):
		if not is_instance_valid(projectiles[index]):
			projectiles.remove_at(index)
	projectiles.append(missile)
	while projectiles.size() > PROJECTILE_CAP:
		var oldest = projectiles.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


func _wire_crawl(actor) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var crawl = CrawlScript.new()
	crawl.name = "Crawl"
	add_child(crawl)
	crawl.attach(actor)
	crawl.set_friends(bodies)
	_crawls.append(crawl)


## The body the soul is inside is the player's to crawl; every other downed body
## is the scene's. Re-read every frame, because the soul moves between bodies.
func _sync_crawl_control() -> void:
	var soul = controller.active_body(1)
	for crawl in _crawls:
		if is_instance_valid(crawl):
			crawl.manual = is_instance_valid(soul) and crawl.actor == soul


## The squad is `squad_drive.gd` - the same one module the cage and the trail always
## shared. In the camp it holds the clearing; once the lesson is over the camp
## tells it to escort the soul down the trail.
func _build_squad() -> void:
	squad = SquadDriveScript.new()
	squad.setup(warband, controller, loot)
	# The squad's own hands can pick a downed soul up: the same channel the G key
	# opens, keyed to the squad rather than to a peer.
	squad.revive = revive
	squad.squad_ids = squad_ids
	squad.watchers = guards
	squad.pickups = pickups
	squad.following = start_area == "town"
	squad.engage_radius = 34.0
	squad.eligible = Callable(self, "_is_free_ally")


## Who may act as a squadmate this frame: the camp answers with its latches (a
## prisoner still in a cage is not free, and the rescuer is the player's beat
## until the squad is out). A body a human soul is inside is never a squadmate,
## local or remote: the AI would be writing a second intent into a body somebody
## is already walking.
func _is_free_ally(merc_id: int) -> bool:
	if merc_id <= 0:
		return false
	if warband != null and warband.souls != null and warband.souls.occupied_by(merc_id) > 0:
		return false
	if camp == null:
		return true
	return camp.is_free(merc_id)


# --- the co-op role --------------------------------------------------------
#
# The world is the same place on every machine, but only the host owns it: a
# guest fields the bodies its save describes and follows the host's word on
# everything else. The flow is still "offline" when `_ready` runs (the session is
# seated at the end of it), so the role can only be discovered by asking later.

## Ask the flow what part this machine plays, once a second. The first "client"
## answer switches the world into its guest mode exactly once.
func _poll_role(delta: float) -> void:
	if _client or flow == null:
		return
	_role_elapsed += delta
	if _role_elapsed < ROLE_POLL_SECONDS:
		return
	_role_elapsed = 0.0
	if str(flow.warband_role()) == "client":
		_become_client()


## A guest does not replay the cages and does not write the campaign. The camp
## throws its lesson away (the host's cage state is the truth, and the opening is
## a solo beat), and from here on this machine runs no squad AI and no local mob
## brains - the session has already marked the host's mobs as replicas.
func _become_client() -> void:
	if _client:
		return
	_client = true
	if camp != null:
		camp.dismiss_lesson()
	if squad != null:
		squad.following = false


## The guards this machine may point at a body. A replica is the host's mob shown
## here: giving it a target would arm a brain that never runs, and a stale target
## is exactly what a late snapshot then drags a wolf towards.
func _local_guards() -> Array:
	if not _client:
		return guards
	var local: Array = []
	for guard in guards:
		if not is_instance_valid(guard):
			continue
		if bool(guard.get("replica")):
			continue
		local.append(guard)
	return local


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
func spawn_pickup(item_id: String, at: Vector3):
	if loot == null or item_id.is_empty():
		return null
	var pickup = loot.spawn(item_id, at)
	if pickup == null:
		return null
	pickup.taken.connect(_on_pickup_taken)
	pickups.append(pickup)
	return pickup


## A fallen enemy lets go of what it was holding. The piece comes out of its
## hand, lands on the dirt in front of the body, and joins the one loot list a
## soul reaches with `K` and a squadmate walks to. What the body still wears is
## the corpse screen's, so nothing is on offer twice.
func drop_held_weapon(enemy) -> bool:
	var item_id: String = GearDropScript.strip_enemy(enemy)
	if item_id.is_empty():
		return false
	var at: Vector3 = (enemy as Node3D).global_position
	spawn_pickup(item_id, GearDropScript.drop_point(at, GearDropScript.forward_of(enemy)))
	return true


## One hostile dies, and the world pays for it once. The wilderness band reports
## here and nowhere else - the camp's watchers and the trail's cultists have their
## own areas' handlers for the lesson's bookkeeping, but the purse belongs to the
## world, so the reward cannot be booked twice.
func _on_enemy_defeated(enemy, reward: int) -> void:
	if not is_instance_valid(enemy):
		return
	# A replica is another machine's mob shown here: the host resolves its death
	# and streams the amount through `WarbandSession.receive_reward`, so this
	# purse adds nothing of its own.
	if not _client and not bool(enemy.get("replica")):
		_pay_kill(reward)
	# The steel comes out of its hand and lands in the dirt; what it still wears is
	# the corpse screen's, so nothing is on offer twice. The body stays on the one
	# hostile list, exactly as the camp's and the trail's fallen do.
	drop_held_weapon(enemy)
	if loot != null and loot.has_method("register_corpse"):
		loot.register_corpse(enemy)
	if screen != null:
		screen.refresh()


## Book a reward into the shared purse and let the strip above it hear about it.
## `Warband` is the one funnel - it writes the same `PlayerState` credits every
## mode spends - but it announces nothing itself, so the purse is repainted here.
func _pay_kill(reward: int) -> void:
	if reward <= 0 or warband == null:
		return
	warband.award_gold(reward)
	# The strip reads `warband.gold()` and only repaints when it is told to; the
	# purse lives in `PlayerState`, so `award_gold` announces nothing by itself.
	if hud != null and hud.has_method("_refresh_purse"):
		hud.call("_refresh_purse")


## A hostile's blow lands on a warband body. The mob emits the swing; the body's
## own guard answers it, exactly as it does in the camp and on the trail - a blade
## raised into the attacker's face turns the hit, and a parry staggers the animal
## instead of cutting the body. Nothing here weighs the blow a second time: the
## mob already carries its own scale.
func _on_enemy_attack(attacker, amount: float, victim) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(victim):
		return
	# Only a body this mode drives has a guard to answer with: anything else the
	# signal names is not a fighter here and is left alone.
	if not victim.has_method("receive_melee") and not victim.has_method("take_damage"):
		return
	# A body on the floor is out of the fight and a dead one cannot be put down
	# twice: both are the roster's business now, not the mob's.
	var alive = victim.get("alive")
	if alive != null and not bool(alive):
		return
	if bool(victim.get("downed")):
		return
	var outcome := -1
	if victim.has_method("receive_melee"):
		outcome = int(victim.receive_melee(amount, WILDERNESS_SOURCE,
			attacker.global_position))
	elif victim.has_method("take_damage"):
		victim.take_damage(amount, WILDERNESS_SOURCE)
		outcome = CombatScript.DEFENSE_NONE
	if outcome == CombatScript.DEFENSE_PARRY and attacker.has_method("stagger"):
		attacker.stagger(CombatScript.PARRY_STAGGER)


## A warband body on the floor drops what it was holding. The roster is what
## dresses a body, so emptying the two hand slots *is* the unequip: the piece is
## not booked into the stash, it is lying beside the body, where a soul can take
## it back with `K` or an ally can pick it up - and where it stays if nobody does.
func drop_merc_gear(actor, merc_id: int) -> void:
	if warband == null or merc_id <= 0 or not is_instance_valid(actor):
		return
	var ids: Array[String] = GearDropScript.strip_hands(warband, merc_id)
	if ids.is_empty():
		return
	var point: Vector3 = (actor as Node3D).global_position
	var at := GearDropScript.drop_point(point, GearDropScript.forward_of(actor))
	for item_id in ids:
		spawn_pickup(item_id, at)
	controller.refresh_gear(merc_id)


func _on_body_downed(_slot: int, actor, merc_id: int) -> void:
	drop_merc_gear(actor, merc_id)
	# The player's own body is a different lesson from a squadmate's: the revive
	# card is about somebody else, this one is about what the soul can still do.
	if controller != null and actor != null and is_instance_valid(actor) \
			and actor == controller.active_body(1):
		_downed_card_pending = true
		_push_downed_card()
	_push_revive_card(actor)


## The first squadmate to go down near the player teaches the channel. A body on
## its chest is not dead: it bleeds for thirty seconds, and `G` held for five
## brings it back. The card holds the game still - the bleed clock with it - so
## the whole rule can be read while the body is still worth standing over.
func _push_revive_card(actor) -> void:
	if card == null or card.has_shown(REVIVE_LESSON_STEP):
		return
	if controller == null or revive == null:
		return
	if actor == null or not is_instance_valid(actor):
		return
	if not bool(actor.get("downed")) or not bool(actor.get("alive")):
		return
	var soul = controller.active_body(1)
	if soul == null or not is_instance_valid(soul) or soul == actor:
		return
	if not bool(soul.get("alive")) or bool(soul.get("downed")):
		return
	if soul.global_position.distance_to(actor.global_position) > REVIVE_LESSON_RADIUS:
		return
	card.show_step(REVIVE_LESSON_STEP, str(REVIVE_LESSON["kicker"]),
		str(REVIVE_LESSON["title"]), str(REVIVE_LESSON["body"]),
		str(REVIVE_LESSON["keys"]), str(REVIVE_LESSON["footnote"]))


## The soul's own body went down: that is the player's own lesson, not a
## squadmate's. It is raised on the frame the tree is free (a card that was up is
## never written over), and it names both ways out because a player who does not
## know they can leave will lie there waiting for an ally they do not have.
func _push_downed_card() -> void:
	if card == null or not _downed_card_pending:
		return
	if card.has_shown(DOWNED_LESSON_STEP):
		_downed_card_pending = false
		return
	if card.is_open() or _panel_open() or controller == null:
		return
	var soul = controller.active_body(1)
	if soul == null or not is_instance_valid(soul):
		return
	if not bool(soul.get("downed")) or not bool(soul.get("alive")):
		# Somebody stood the body up before the card could be read: what it would
		# teach is no longer true.
		_downed_card_pending = false
		return
	_downed_card_pending = false
	card.show_step(DOWNED_LESSON_STEP, str(DOWNED_LESSON["kicker"]),
		str(DOWNED_LESSON["title"]), str(DOWNED_LESSON["body"]),
		str(DOWNED_LESSON["keys"]), str(DOWNED_LESSON["footnote"]))


## The bandage lesson: the first time the soul's body is at or below 60% of its
## pool with no hostile close enough to punish the channel, the world says `6`
## out loud. A body that learned it in a fight would learn it face down.
func _update_bandage_card() -> void:
	if card == null or controller == null:
		return
	if card.is_open() or _panel_open() or card.has_shown(BANDAGE_LESSON_STEP):
		return
	var soul = controller.active_body(1)
	if soul == null or not is_instance_valid(soul):
		return
	if not bool(soul.get("alive")) or bool(soul.get("downed")):
		return
	var pool := maxf(1.0, float(soul.get("max_health")))
	if float(soul.get("health")) / pool > BANDAGE_LESSON_HEALTH:
		return
	if _hostile_near((soul as Node3D).global_position, BANDAGE_LESSON_RADIUS):
		return
	card.show_step(BANDAGE_LESSON_STEP, str(BANDAGE_LESSON["kicker"]),
		str(BANDAGE_LESSON["title"]), str(BANDAGE_LESSON["body"]),
		str(BANDAGE_LESSON["keys"]), str(BANDAGE_LESSON["footnote"]))


## Whether a hostile this machine drives is standing within `radius` of a point.
## A replica is the host's mob shown here and is not hunting anybody locally, so
## it is not in the answer.
func _hostile_near(at: Vector3, radius: float) -> bool:
	for guard in _local_guards():
		if not is_instance_valid(guard) or not bool(guard.get("alive")):
			continue
		if (guard as Node3D).global_position.distance_to(at) <= radius:
			return true
	return false


## The wrong-way sign, read off the trail's own ruler. A body only learns the road
## once it has stood within `WRONG_WAY_ARM_METRES` of town - the escape's first
## steps are 1070 m out and never raise it. After that, climbing back up the trail
## past a kilometre raises the banner; turning round drops it under 980, so a body
## standing on the line does not flicker.
func _update_wrong_way() -> void:
	if trail == null or controller == null or camp == null or not camp.escaping():
		_set_wrong_way(false)
		return
	var soul = controller.active_body(1)
	if soul == null or not is_instance_valid(soul):
		_set_wrong_way(false)
		return
	var metres: float = trail.metres_to_town((soul as Node3D).global_position)
	if metres <= WRONG_WAY_ARM_METRES:
		_wrong_way_armed = true
	if not _wrong_way_armed:
		return
	if _wrong_way:
		if metres < WRONG_WAY_CLEAR_METRES:
			_set_wrong_way(false)
	elif metres >= WRONG_WAY_TRIGGER_METRES:
		_set_wrong_way(true)


## One answer for the banner and the roadside word: they are the same sentence,
## and they go up and down together.
func _set_wrong_way(on: bool) -> void:
	if on == _wrong_way:
		return
	_wrong_way = on
	if hud != null:
		hud.set_warning(WRONG_WAY_TEXT if on else "")
	if _wrong_way_sign != null and is_instance_valid(_wrong_way_sign):
		_wrong_way_sign.visible = on


## Whether the wrong-way warning is up, for a test that must not read a private
## label.
func wrong_way() -> bool:
	return _wrong_way


func _on_body_killed(_slot: int, _source: int, actor, merc_id: int) -> void:
	drop_merc_gear(actor, merc_id)


func _on_pickup_taken(pickup) -> void:
	if camp != null:
		camp.note_pickup(pickup)
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
	# A checkpoint is the way back from a wipe; with none (the opening, a fresh
	# campaign) the wood still takes what is left.
	_reload_checkpoint()


func _all_bodies_out() -> bool:
	if bodies.is_empty():
		return false
	for actor in bodies:
		if not is_instance_valid(actor):
			continue
		if bool(actor.get("alive")) and not bool(actor.get("downed")):
			return false
	return true


# --- checkpoints (autosave) ------------------------------------------------
#
# Two moments in the campaign begin a new stretch, and each one writes the
# warband's own save with a bookmark: the camp's six watchers down and the squad
# on the road (the tutorial is over, the run starts), and the town square first
# entered. A checkpoint is written once per id, so walking back and forth does
# not hammer the disk; a wipe loads it, and the title's resume door opens on it.

func _check_checkpoints() -> void:
	if warband == null or controller == null or _wiped:
		return
	# A guest does not own the campaign: writing its own bookmark would move the
	# line every machine reloads from to wherever one guest happened to stand.
	if _client:
		return
	var actor = controller.active_body(1)
	if actor == null or not is_instance_valid(actor) or not bool(actor.get("alive")):
		return
	# The opening is behind us: the six watchers are dead and the leaving has
	# happened. The bookmark sits a little down the road, past the ambush's own
	# posts, so a reload never drops the squad inside a fight it has just lost.
	if camp != null and camp.tutorial_cleared() and warband.checkpoint_id() != "trail_start":
		var at := Vector3(CampScript.GATE_POINT.x, 0.0, CampScript.GATE_POINT.z - 60.0)
		_save_checkpoint("trail_start", "trail", TerrainScript.grounded(at),
			"THE CAMP IS BEHIND YOU")
		return
	if town != null and town.in_square(actor) and warband.checkpoint_id() != "town":
		_save_checkpoint("town", "town", actor.global_position, "HEARTHSTEAD")


func _save_checkpoint(id: String, area: String, position: Vector3, label: String) -> void:
	warband.save_checkpoint(id, area, position, label)
	if hud != null:
		hud.set_status("CHECKPOINT  /  %s" % label, 4.0)


## The wipe's way back. Only a live campaign may change scene (the regression
## harnesses keep `GameFlow.active` false), and a checkpoint whose whole squad is
## dead is not one: the wood keeps what is left, exactly as it always did.
func _reload_checkpoint() -> bool:
	if flow == null or not flow.active or warband == null or not warband.has_checkpoint():
		return false
	if hud != null:
		hud.set_status("The warband falls. It rises again at the last checkpoint.", WIPE_BEAT)
	if squad != null:
		squad.following = false
	return bool(flow.retry_checkpoint())


# --- interaction -----------------------------------------------------------

## The one `G`: a cage latch in the camp, a counter in the town, a corpse at your
## feet, or a piece of steel lying loose. The camp is asked first, because its
## latches stand in the ground a body walks on - and a camp that refused the press
## (nothing in reach) hands it on rather than eating it.
func _try_interact() -> void:
	var actor = controller.active_body(1)
	if actor == null or not is_instance_valid(actor):
		if hud != null:
			hud.set_status("The soul is loose. There is nobody to act with.", 2.5)
		return
	if camp != null and camp.interact(actor):
		return
	if town != null and not town.interact_at(1, actor.global_position).is_empty():
		return
	# A fallen body at your feet is a container: `G` opens its character screen. A
	# body that has already given everything answers false, and the press falls
	# through to the ordinary line.
	if loot != null and loot.has_method("corpse_at"):
		var corpse_id: int = loot.corpse_at(actor.global_position, LOOT_REACH)
		if corpse_id != 0 and paperdoll.open_corpse(loot, corpse_id):
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


## `TAB` is the frontier's quick swap: the body the soul is inside puts away the
## weapon set in its hands and takes up the other one. Both sets live on that
## mercenary's roster record, so which pair the hands carry is warband state and
## survives a body swap, a reload or a scene hand-off - and what the swap moved
## onto the rig is the roster's own kit through `refresh_gear()`, never a weapon
## conjured onto a body that was not carrying it.
func _swap_weapon_set() -> void:
	if warband == null or controller == null:
		return
	var merc_id: int = controller.merc_for_peer(1)
	if merc_id <= 0:
		if hud != null:
			hud.set_status("The soul is loose. There is nobody to swap for.", 2.5)
		return
	var result: Dictionary = warband.swap_weapon_set(merc_id)
	if bool(result.get("ok", false)):
		controller.refresh_gear(merc_id)
	if hud != null:
		hud.set_status(str(result.get("message", "")), 2.0)


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
	# A body on the floor outranks everything else on screen: the one thing a
	# soul can do for a squadmate is stand over it and hold the key.
	var fallen = _revive_target()
	if fallen != null:
		_write_prompt("HOLD G  ·  PICK UP %s" % warband.roster.name_of(
			int(controller.merc_of(fallen))).to_upper(), G_REVIVE_HINT)
		return
	# The counter under the body's nose wins over the camp's lesson, and the
	# lesson wins over the trail: a body can only be standing in one of them.
	if town != null and town.in_square(actor):
		text = town.prompt_line(actor)
	if text.is_empty() and camp != null:
		text = camp.prompt_line(actor)
	if text.is_empty() and trail != null and actor != null and is_instance_valid(actor):
		text = "%s   ·   %d m" % [TRAIL_OBJECTIVE,
			int(round(trail.metres_to_town(actor.global_position)))]
	_write_prompt(text, _hint_text)


## The key line: the lesson's, or the counter's, or the trail's.
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
	# The menu is a panel for the pointer's purposes - it takes the cursor - but
	# Escape closes it through its own branch rather than through `_hide_panels`.
	if menu != null and menu.is_open():
		return true
	if (screen != null and screen.is_open()) or (paperdoll != null and paperdoll.is_open()):
		return true
	return town != null and town.panels_open()


## Escape opens the warband menu. The body keeps standing where it stood, but it
## stops taking commands while the ledger is up: a click on the ledger must never
## swing a weapon. `resumed` restores the body on every way the menu closes.
func _open_menu() -> void:
	if menu == null or (card != null and card.is_open()):
		return
	menu.open()
	if controller != null:
		controller.input_enabled = false


func _on_menu_resumed() -> void:
	if controller != null:
		controller.input_enabled = true


## The menu's LOAD row. The file is read first and the flow is told where to put
## the warband second: `GameFlow.goto()` writes the warband on its way out, so a
## load that ran after it would save the world's live roster over the file it was
## about to read.
func _on_menu_load_requested() -> void:
	if menu != null:
		menu.close()
	if warband == null or flow == null:
		return
	if not warband.load_state():
		if hud != null:
			hud.set_status("No written warband to load.", 2.5)
		return
	flow.world_start = "checkpoint" if warband.has_checkpoint() else "town"
	# The flow's own constant, read off the instance: the world never spells its
	# own path a second time.
	flow.goto(flow.WORLD_SCENE)


## The menu's EXIT row: write the campaign, drop any socket this machine holds,
## and go back to the title. A guest's bodies die with the scene, so the session
## is abandoned before the hand-off rather than left pointing at them.
func _on_menu_exit_requested() -> void:
	if menu != null:
		menu.close()
	if warband != null:
		warband.save_state()
	if flow != null and flow.warband_role() != "offline":
		flow.leave_warband()
	var tree := get_tree()
	if tree == null:
		return
	# A tutorial card may be holding the tree still; the title must not open
	# behind it.
	tree.paused = false
	tree.change_scene_to_file(TITLE_SCENE)


## The menu's QUIT row. The file is written before the process leaves, so the
## last thing a campaign did is the one thing a reload needs.
func _on_menu_quit_requested() -> void:
	if warband != null:
		warband.save_state()
	get_tree().quit()


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
		"clearing_huts": int(camp.clearing.get("huts", 0)) if camp != null else 0,
		"camp_to_road": CampScript.CAMP_TO_ROAD_METRES,
		"lane_length": float(trail.forest.get("length", 0.0)) if trail != null else 0.0,
		"lane_width": float(trail.forest.get("width", 0.0)) if trail != null else 0.0,
		"torches": (trail.forest.get("torches", []) as Array).size() if trail != null else 0,
		"town_wood": int(town.wood.get("trees", 0)) if town != null else 0,
		"town_at": town.global_position if town != null else Vector3.ZERO,
		"terrain_tris": int(_terrain.get("triangles", 0)),
		"terrain_cell": float(_terrain.get("cell", 0.0)),
		"height_min": float(_terrain.get("min", 0.0)),
		"height_max": float(_terrain.get("max", 0.0)),
	}


## The point the trail's far end stands at - the town's north gate.
func town_gate() -> Vector3:
	return trail.town_gate() if trail != null else Vector3.ZERO


## The camp pocket's own size: a ragged pocket in the wood, not a walled yard.
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

## Where the campaign puts this body down: the camp for a fresh run, a saved
## checkpoint for a resumed one, or the town end for the arena's return.
func _wanted_start() -> String:
	if flow == null:
		return "camp"
	var wanted := str(flow.world_start)
	if wanted == "checkpoint":
		return "checkpoint" if warband != null and warband.has_checkpoint() else "town"
	return "town" if wanted == "town" else "camp"


## True when the world is opening on a bookmark past the cages.
func _resuming_trail() -> bool:
	return start_area == "checkpoint" and warband != null \
		and warband.has_checkpoint() and warband.checkpoint_area() != "town"


func _announce() -> void:
	var readout: Dictionary = stats()
	print("WARBAND_WORLD_READY start=%s bodies=%d guards=%d lane=%.1f road=%.0fm torches=%d trees=%d nodes=%d draws=%d shapes=%d ground=%.1f..%.1fm/%d tris"
		% [start_area, bodies.size(), guards.size(), float(readout["lane_length"]),
			float(readout["camp_to_road"]), int(readout["torches"]),
			int(readout["clearing_trees"]) + int(readout["town_wood"]),
			int(readout["nodes"]), int(readout["draws"]), int(readout["shapes"]),
			float(readout["height_min"]), float(readout["height_max"]),
			int(readout["terrain_tris"])])
