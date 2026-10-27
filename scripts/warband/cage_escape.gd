extends Node3D
## GHOST OF THE WARBAND: the opening beat - the cage escape.
##
## A night cultist camp yard: four prisoners in iron cages, a fifth loose behind
## the gate, and two guards between the squad and the way out. The whole scene is
## the tutorial for possession, so it is built from the merged pieces rather than
## invented beside them: `PossessionController` owns the bodies, `WarbandLoot`
## drops the cultist steel, `ReviveChannel` + `CrawlToSafety` keep a downed body
## playable, `WarbandHud` reads the soul and `TutorialSequencer` holds the order.
##
## The one thing this scene does that no arena does is hold a body still: while
## the lesson is on its first beat the four caged bodies can be entered (that is
## the instruction) but a per-frame distance clamp keeps each of them inside its
## own cage. The rescuer's latch releases the clamp and raises the cage bars.
##
## Everything is primitives in code: a flat yard, a low palisade with a gate gap,
## four bar cages, a couple of crates and a stone altar prop, low moonlight, torch
## fire and fog. No frontier, no cultist wave file, no town scene preloaded.

signal scene_requested(path: String)

const ControllerScript = preload("res://scripts/warband/possession_controller.gd")
const SequencerScript = preload("res://scripts/warband/tutorial_sequencer.gd")
const HudScript = preload("res://scripts/warband/warband_hud.gd")
const CardScript = preload("res://scripts/warband/tutorial_card.gd")
const ScreenScript = preload("res://scripts/warband/warband_screen.gd")
const PaperdollScript = preload("res://scripts/warband/warband_paperdoll.gd")
const LootScript = preload("res://scripts/warband/loot_vacuum.gd")
const CrawlScript = preload("res://scripts/warband/crawl_to_safety.gd")
const ReviveScript = preload("res://scripts/warband/revive_channel.gd")
const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Geo = preload("res://scripts/geo.gd")
const State = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const SeatLoadout = preload("res://scripts/seat_loadout.gd")

## The prison squad. Four wretches in rags and the one who kept his shiv.
const PRISONER_NAMES := ["Ash", "Bram", "Het", "Wren"]
const RESCUER_NAME := "Corvin"
const SQUAD_SIZE := 5
const PRISONER_COUNT := 4
const RESCUER_INDEX := 4

## Cage centres, in a line facing the gate. y is the height a body spawns at.
const CAGE_POSTS := [
	Vector3(-7.6, 0.2, 6.0), Vector3(-2.6, 0.2, 6.0),
	Vector3(2.6, 0.2, 6.0), Vector3(7.6, 0.2, 6.0),
]
## Where the loose prisoner waits: inside the gate, behind the guards.
const RESCUER_POST := Vector3(1.4, 0.2, -23.0)
## The arch. Walking a freed body inside `GATE_RADIUS` of it ends the tutorial.
const GATE_POINT := Vector3(0.0, 0.0, -24.5)
const GATE_RADIUS := 3.0
## Where the rescuer's jog ends: just in front of the cage line.
const JOG_TARGET := Vector3(0.0, 0.0, 8.6)
const JOG_STOP := 1.6
## How far a caged body may stray from its own cage centre.
const CAGE_CLAMP_RADIUS := 0.95
## How far the cage doors rise when the latches go.
const CAGE_BAR_LIFT := 2.6
const BAR_LIFT_SPEED := 2.2
const LOOT_REACH := 2.6

## The two gate watchers: the antlered hollow warden silhouette, thinned in
## `cage_watcher.gd` so three dagger stabs end one. They stand by the gate, turn
## on the squad when the first latch goes, and are slow enough to learn to block.
const GATE_WATCHERS := [
	{"post": Vector3(-4.2, 0.1, -20.5)},
	{"post": Vector3(4.2, 0.1, -20.5)},
]
## The one hit a watcher needs to land for the lesson: light, and telegraphed.
const WATCHER_SOURCE := 90
## What a sword in this camp is allowed to bite: the watchers' physics layer.
## `ArenaActor` defaults to 4 (other fighters); a warband body that kept that
## mask swings through every mob in the game and damages nothing.
const WATCHER_LAYER := 2
## Cultist steel along the walk from the cages to the gate.
const WEAPON_DROPS := [
	["sword_short", Vector3(-0.8, 0.15, -0.5)],
	["dagger_iron", Vector3(4.4, 0.15, -10.0)],
	["sword_arming", Vector3(-4.6, 0.15, -16.5)],
]
## One big card per beat. The card pauses the game, so every line has to be
## worth reading: the lesson, then the exact keys, then one way out.
const STEP_CARDS := {
	0: {  # CAGED
		"kicker": "STEP 1  /  THE CAGES",
		"title": "You are a soul, not a body",
		"body": "Four prisoners hang in this camp, and your soul can enter any living body. Shift between them: that is the whole game.",
		"keys": "F1  F2  F3  F4        or        [  ]        enter another prisoner",
		"footnote": "Press G, Enter or click CONTINUE to play. TAB opens the warband, P your gear.",
	},
	1: {  # ALL_SEEN
		"kicker": "STEP 2  /  THE SHIV",
		"title": "All four seen - here he comes",
		"body": "The fifth prisoner is loose, and he is running for the cages with a knife.",
		"keys": "Wait for him",
		"footnote": "Close this card to let him arrive.",
	},
	2: {  # RESCUER_ARRIVED
		"kicker": "STEP 3  /  THE LATCHES",
		"title": "Corvin has the shiv",
		"body": "He is through with the shiv and he is not moving. Take his body yourself, then walk to each cage and cut its latch. Four cages, four latches - and the watchers wake when the first one falls.",
		"keys": "F5  or  [ ]  take Corvin        ·        G  cut a latch",
		"footnote": "Nothing happens until you are in his body: only his hands carry the shiv.",
	},
	3: {  # FREED
		"kicker": "STEP 4  /  ARM YOURSELF",
		"title": "The squad is out. Take their steel.",
		"body": "Loot the cultist weapons with K - a picked-up blade goes straight into your hands. Then put down the two watchers at the gate: three stabs each.",
		"keys": "K  loot        ·        LMB / RMB  fight        ·        E  revive",
		"footnote": "The watchers are slow and light. Hold RMB to block, then stab.",
	},
	4: {  # ESCAPING
		"kicker": "STEP 5  /  THE GATE",
		"title": "The way is open",
		"body": "Walk into the gate arch at the north end of the camp and press G.",
		"keys": "G  leave the camp for town",
		"footnote": "The town is where the warband lives between battles.",
	},
}

## Where the escape leads. The town hub is another worktree's file, so the path
## is resolved when the gate opens instead of preloaded here; if neither exists
## the player simply stays in the camp with the gate standing open.
const TOWN_PATHS := ["res://town_hub.tscn", "res://scenes/town_hub.tscn"]

var warband
var controller
var sequencer
var hud
var card
var screen
var paperdoll
var loot
var revive
var camera: Camera3D
var bodies: Array = []
var guards: Array = []
var crawls: Array = []
var rescuer_id := -1
var squad_ids: Array[int] = []
var caged_ids: Array[int] = []
var _cage_anchors: Dictionary = {}   # merc_id -> the cage centre it is held in
var _cage_doors: Array = []          # [{node, lift}, ...]
var _pickups: Array = []
var _guard_tick := 0
var _jogging := false
var _reviving := false
var _cage_open: Array[bool] = []   # per cage, in CAGE_POSTS order
var _watchers_awake := false
var _card_state := -1
## Set the first time a freed ally swings at a watcher; the regression reads it.
var _ally_engaged := false
## Steel taken by anyone, counted across the whole tutorial so a squadmate's
## pickup during the latches still counts once the fight starts.
var _steel_taken := 0
var _prompt_text := ""
var _hint_text := ""

var _ground_mat: StandardMaterial3D
var _wood_mat: StandardMaterial3D
var _iron_mat: StandardMaterial3D
var _stone_mat: StandardMaterial3D

func _ready() -> void:
	warband = get_node_or_null("/root/Warband")
	if warband == null:
		push_error("CageEscape needs the Warband autoload")
		return
	_seed_warband()
	_build_world()
	camera = Camera3D.new()
	camera.name = "CampCamera"
	camera.current = true
	camera.fov = 62.0
	camera.near = 0.08
	camera.far = 220.0
	camera.position = Vector3(0, 14, 30)
	add_child(camera)
	camera.look_at(Vector3(0, 1, 0))

	sequencer = SequencerScript.new()
	sequencer.name = "Tutorial"
	add_child(sequencer)
	sequencer.state_changed.connect(_on_state_changed)
	sequencer.rescuer_ready.connect(_on_rescuer_ready)
	sequencer.gate_ready.connect(_on_gate_ready)
	sequencer.begin(rescuer_id)

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
	_build_watchers()
	_build_ui()
	_cage_open.clear()
	for index in caged_ids.size():
		_cage_open.append(false)
	controller.possession_changed.connect(_on_possession_changed)
	controller.transfer_refused.connect(_on_transfer_refused)
	controller.possession_released.connect(_on_possession_released)
	sequencer.announce()
	if not caged_ids.is_empty():
		controller.direct(1, caged_ids[0])
	# Capture the mouse before the card opens: the card remembers the mode it
	# found and restores it, and the mode it should find is the game's.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_push_card(sequencer.state())
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.bind(self)

func _process(delta: float) -> void:
	if controller == null:
		return
	var panel_open := _panel_open()
	var wanted := Input.MOUSE_MODE_VISIBLE if panel_open else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != wanted:
		Input.mouse_mode = wanted
	_advance_cage_doors(delta)

func _physics_process(delta: float) -> void:
	if controller == null:
		return
	_rescuer_jog()
	_drive_allies(delta)
	controller.physics_step(delta)
	_maintain_watchers(delta)
	_clamp_caged_bodies()
	_tick_revive(delta)
	_update_prompt()
	_update_hint()

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
		KEY_G:
			_try_interact()
			get_viewport().set_input_as_handled()
		KEY_B:
			_try_finish_fight()
			get_viewport().set_input_as_handled()

## `E` is the revive channel here, so the key is consumed before the actor layer
## can read it as a step. It only ever swallows the key when a downed body is in
## reach - a tutorial must not steal the standard move.
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

# --- seeding ---------------------------------------------------------------

## The prison squad. An empty warband is dressed for the camp: four prisoners in
## rags with empty hands and the rescuer with a shiv. A warband that already has
## bodies keeps its gear (it is the player's warband), but the first five are the
## ones in the yard and the rescuer is guaranteed a blade if he has none.
func _seed_warband() -> void:
	var living: Array = warband.alive_merc_ids()
	if living.is_empty():
		for prisoner in PRISONER_NAMES:
			var merc_id: int = warband.add_mercenary(str(prisoner))
			_dress_rags(merc_id)
			warband.roster.unequip(merc_id, "main")
			warband.roster.unequip(merc_id, "off")
		var rescuer: int = warband.add_mercenary(RESCUER_NAME)
		_dress_rags(rescuer)
		warband.roster.equip(rescuer, "main", "dagger_makeshift")
		living = warband.alive_merc_ids()
	else:
		# The lesson needs four cages and a fifth body: a thin warband is topped
		# up with prisoners rather than bending the tutorial around it.
		while living.size() < SQUAD_SIZE:
			var extra: int = warband.add_mercenary("Wretch %d" % (living.size() + 1))
			_dress_rags(extra)
			living.append(extra)
	squad_ids.clear()
	for index in SQUAD_SIZE:
		squad_ids.append(int(living[index]))
	rescuer_id = squad_ids[RESCUER_INDEX]
	var main_id := str(warband.roster.equipped_of(rescuer_id).get("main", ""))
	if main_id.is_empty():
		warband.roster.equip(rescuer_id, "main", "dagger_makeshift")
	caged_ids.clear()
	for index in PRISONER_COUNT:
		caged_ids.append(squad_ids[index])
	# Only the prison squad fields: the scene has exactly five bodies to place,
	# so the tutorial deploys its own line rather than borrowing the last one.
	warband.deploy_battle(squad_ids)

func _dress_rags(merc_id: int) -> void:
	for slot in ArmorData.SLOTS:
		var armor_id := "armor_makeshift_%s" % slot
		if State.ITEMS.has(armor_id):
			warband.roster.equip(merc_id, slot, armor_id)

func _spawn_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for post in CAGE_POSTS:
		points.append(post)
	points.append(RESCUER_POST)
	return points

## Give every body the post its mercenary owns, and hold the four caged ones in.
func _place_bodies() -> void:
	for actor in bodies:
		if not is_instance_valid(actor):
			continue
		var merc_id: int = controller.merc_of(actor)
		var post := _post_for(merc_id)
		actor.global_position = post
		actor.spawn_point = post
		actor.bounds = 60.0
		# `ArenaActor` is born hostile only to other arena bodies (layer 4). This
		# camp's enemies are the wilderness watchers (layer 2), and the squad must
		# never cut its own fighters, so the swords look at the mob layer only.
		actor.combat.target_mask = WATCHER_LAYER
		# Nobody in this camp fights on their own: the prisoners are the lesson
		# and the rescuer is the script. Only the two guards are bots.
		controller.set_bot(merc_id, false)
	for merc_id in caged_ids:
		_cage_anchors[merc_id] = _post_for(merc_id)

func _post_for(merc_id: int) -> Vector3:
	var index := caged_ids.find(merc_id)
	if index >= 0:
		return CAGE_POSTS[index]
	return RESCUER_POST

# --- world -----------------------------------------------------------------

func _build_world() -> void:
	_ground_mat = Geo.material(Color(0.10, 0.10, 0.09), 0.0, 0.95)
	_wood_mat = Geo.material(Color(0.19, 0.15, 0.11), 0.0, 0.9)
	_iron_mat = Geo.material(Color(0.19, 0.19, 0.20), 0.55, 0.55)
	_stone_mat = Geo.material(Color(0.26, 0.25, 0.24), 0.0, 0.9)

	_build_night()
	# The yard floor, then the wider dark field so the horizon is not a void.
	_solid_box(Vector3(34.0, 0.6, 44.0), Vector3(0, -0.3, -4.0), _ground_mat)
	var field := Geo.box(self, Vector3(220.0, 0.3, 220.0), Vector3(0, -0.78, 0), _ground_mat)
	field.name = "CampField"
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Low palisade: solid walls of logs with a gap at the gate.
	var wall_height := 1.9
	for side in [-1.0, 1.0]:
		_solid_box(Vector3(0.6, wall_height, 44.0), Vector3(side * 17.0, wall_height * 0.5, -4.0), _wood_mat)
	_solid_box(Vector3(34.0, wall_height, 0.6), Vector3(0, wall_height * 0.5, 18.0), _wood_mat)
	for side in [-1.0, 1.0]:
		_solid_box(Vector3(14.0, wall_height, 0.6), Vector3(side * 10.0, wall_height * 0.5, -26.0), _wood_mat)
	# Log tops over the walls: silhouette against the fog, no extra collision.
	for index in 22:
		for side in [-1.0, 1.0]:
			Geo.cylinder(self, 0.16, 0.14, 2.3, Vector3(side * 17.0, 1.15, -24.0 + index * 2.0), _wood_mat, 6)
	for index in 9:
		Geo.cylinder(self, 0.16, 0.14, 2.3, Vector3(-16.0 + index * 4.0, 1.15, 18.0), _wood_mat, 6)

	_build_gate()
	for index in caged_ids.size():
		_build_cage(index, CAGE_POSTS[index])
	_build_props()
	_torch(Vector3(-10.5, 0, 4.2), 0.9)
	_torch(Vector3(10.5, 0, 4.2), 0.9)
	_torch(Vector3(-3.0, 0, -22.5), 1.0)
	_torch(Vector3(3.0, 0, -22.5), 1.0)
	_torch(Vector3(0, 0, -12.0), 0.75)

func _build_night() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.10, 0.12, 0.18)
	env.ambient_light_energy = 0.85
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.07, 0.11)
	env.fog_density = 0.018
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.name = "Night"
	world_env.environment = env
	add_child(world_env)

	var moon := DirectionalLight3D.new()
	moon.name = "Moonlight"
	moon.light_color = Color(0.58, 0.66, 0.92)
	moon.light_energy = 0.34
	moon.shadow_enabled = false
	moon.rotation_degrees = Vector3(-54, -38, 0)
	add_child(moon)

## The way out: two heavy posts, a crossbeam, a brazier burning on either side.
func _build_gate() -> void:
	for side in [-1.0, 1.0]:
		_solid_box(Vector3(0.5, 4.6, 0.5), Vector3(side * 3.0, 2.3, -26.0), _wood_mat)
		Geo.cylinder(self, 0.42, 0.34, 0.2, Vector3(side * 3.0, 4.55, -26.0), _iron_mat, 8)
		Geo.sphere(self, 0.22, Vector3(side * 3.0, 4.85, -26.0), _flame_material())
		var light := OmniLight3D.new()
		light.name = "GateLight"
		light.position = Vector3(side * 3.0, 4.6, -26.0)
		light.light_color = Color(1.0, 0.62, 0.28)
		light.light_energy = 2.2
		light.omni_range = 14.0
		add_child(light)
	Geo.box(self, Vector3(7.4, 0.5, 0.5), Vector3(0, 4.8, -26.0), _wood_mat)
	var label := Label3D.new()
	label.text = "GATE"
	label.position = Vector3(0, 5.4, -26.0)
	label.font_size = 96
	label.pixel_size = 0.012
	label.modulate = Color(1.0, 0.78, 0.5)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func _flame_material() -> StandardMaterial3D:
	var mat := Geo.material(Color(1.0, 0.62, 0.24))
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.48, 0.12)
	mat.emission_energy_multiplier = 3.0
	return mat

func _torch(at: Vector3, scale: float) -> void:
	Geo.cylinder(self, 0.11 * scale, 0.08 * scale, 2.6, at + Vector3(0, 1.3, 0), _wood_mat, 8)
	Geo.sphere(self, 0.17 * scale, at + Vector3(0, 2.72, 0), _flame_material())
	var light := OmniLight3D.new()
	light.name = "Torch"
	light.position = at + Vector3(0, 2.6, 0)
	light.light_color = Color(1.0, 0.56, 0.22)
	light.light_energy = 2.4 * scale + 0.6
	light.omni_range = 15.0
	light.omni_attenuation = 1.3
	add_child(light)

## One cage: a slab floor, four corner posts, fixed bars on three sides, and a
## door of bars on the gate side that rises when the rescuer works the latch.
func _build_cage(index: int, at: Vector3) -> void:
	var cage := Node3D.new()
	cage.name = "Cage%d" % (index + 1)
	cage.position = Vector3(at.x, 0.0, at.z)
	add_child(cage)
	Geo.box(cage, Vector3(2.5, 0.1, 2.5), Vector3(0, -0.03, 0), _wood_mat)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			Geo.box(cage, Vector3(0.17, 2.9, 0.17), Vector3(sx * 1.15, 1.45, sz * 1.15), _iron_mat)
	for step in 5:
		var offset := -0.8 + step * 0.4
		Geo.cylinder(cage, 0.05, 0.05, 2.7, Vector3(offset, 1.4, 1.15), _iron_mat, 6)
		Geo.cylinder(cage, 0.05, 0.05, 2.7, Vector3(-1.15, 1.4, offset), _iron_mat, 6)
		Geo.cylinder(cage, 0.05, 0.05, 2.7, Vector3(1.15, 1.4, offset), _iron_mat, 6)
	Geo.box(cage, Vector3(2.5, 0.12, 0.12), Vector3(0, 2.78, -1.15), _iron_mat)
	var door := Node3D.new()
	door.name = "Door"
	door.position = Vector3(0, 0, -1.15)
	cage.add_child(door)
	for step in 6:
		Geo.cylinder(door, 0.045, 0.045, 2.7, Vector3(-1.0 + step * 0.4, 1.4, 0), _iron_mat, 6)
	Geo.box(door, Vector3(2.4, 0.1, 0.1), Vector3(0, 1.1, 0), _iron_mat)
	_cage_doors.append({"node": door, "lift": 0.0})

## Camp dressing: crate stacks, barrels and a cold stone altar. Props only - the
## real sacrificial altar belongs to the town hub.
func _build_props() -> void:
	var crate_at := [Vector3(-13.0, 0, -8.0), Vector3(-12.2, 0, -6.4), Vector3(13.4, 0, 12.0),
		Vector3(12.4, 0.9, 12.4), Vector3(13.1, 0, -14.5)]
	for index in crate_at.size():
		var crate := Geo.box(self, Vector3(0.9, 0.9, 0.9), crate_at[index] + Vector3(0, 0.45, 0), _wood_mat)
		crate.rotation.y = 0.17 * float(index) - 0.3
	for point in [Vector3(-13.6, 0, 3.0), Vector3(14.2, 0, 2.0), Vector3(-8.0, 0, -19.0)]:
		Geo.cylinder(self, 0.36, 0.32, 0.95, point + Vector3(0, 0.48, 0), _wood_mat, 12)
	# The cult's cold altar, behind the cages.
	var altar := Node3D.new()
	altar.name = "ColdAltar"
	altar.position = Vector3(0, 0, 12.5)
	add_child(altar)
	Geo.box(altar, Vector3(2.6, 0.9, 1.3), Vector3(0, 0.45, 0), _stone_mat)
	Geo.box(altar, Vector3(3.0, 0.18, 1.6), Vector3(0, 0.99, 0), _stone_mat)
	Geo.cylinder(altar, 0.34, 0.5, 0.24, Vector3(0, 1.2, 0), _iron_mat, 12)
	var stain := Geo.material(Color(0.20, 0.03, 0.03), 0.0, 0.7)
	Geo.box(altar, Vector3(1.6, 0.02, 0.9), Vector3(0, 1.09, 0), stain)

func _advance_cage_doors(delta: float) -> void:
	var step := BAR_LIFT_SPEED * delta
	for index in _cage_doors.size():
		var entry: Dictionary = _cage_doors[index]
		var open := index < _cage_open.size() and bool(_cage_open[index])
		var lift := move_toward(float(entry["lift"]), CAGE_BAR_LIFT if open else 0.0, step)
		entry["lift"] = lift
		var node: Node3D = entry["node"]
		if is_instance_valid(node):
			node.position.y = lift

func _solid_box(size: Vector3, at: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	add_child(body)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	return body

# --- the squad -------------------------------------------------------------

## While the cages hold, every caged body is snapped back inside its own cage.
## Possession moves the soul, not the cage: this is the only thing that makes the
## first beat a tutorial instead of four free bodies.
func _clamp_caged_bodies() -> void:
	for index in caged_ids.size():
		if index < _cage_open.size() and bool(_cage_open[index]):
			continue
		var merc_id := int(caged_ids[index])
		var actor = controller.body_of(merc_id)
		if actor == null or not is_instance_valid(actor):
			continue
		var anchor: Vector3 = _cage_anchors.get(int(merc_id), actor.global_position)
		var flat := Vector3(actor.global_position.x - anchor.x, 0.0, actor.global_position.z - anchor.z)
		if flat.length() <= CAGE_CLAMP_RADIUS:
			continue
		var snapped := anchor + flat.normalized() * CAGE_CLAMP_RADIUS
		actor.global_position = Vector3(snapped.x, actor.global_position.y, snapped.z)
		actor.velocity.x = 0.0
		actor.velocity.z = 0.0

## The cultist steel this camp is carrying, in spawn order.
func pickups() -> Array:
	return _pickups.duplicate()

func is_cage_clamped(merc_id: int) -> bool:
	var index := caged_ids.find(merc_id)
	if index < 0:
		return false
	return index >= _cage_open.size() or not bool(_cage_open[index])

func cage_anchor_for(merc_id: int) -> Vector3:
	return _cage_anchors.get(merc_id, Vector3.ZERO)

func cages_open() -> bool:
	for open in _cage_open:
		if not bool(open):
			return false
	return not _cage_open.is_empty()

## How many latches the player has cut, 0..4.
func cages_open_count() -> int:
	var count := 0
	for open in _cage_open:
		if bool(open):
			count += 1
	return count

## The fourth prisoner seen starts the rescuer's walk. He is not a bot: the scene
## drives his legs with the same authoritative input frame a peer would send, so
## a jailbreak is a walk, not a teleport.
func _rescuer_jog() -> void:
	if not _jogging:
		return
	var actor = controller.body_of(rescuer_id)
	if actor == null or not is_instance_valid(actor):
		return
	var to: Vector3 = JOG_TARGET - actor.global_position
	to.y = 0.0
	if to.length() <= JOG_STOP:
		_jogging = false
		actor.move_direction = Vector2.ZERO
		actor.run_requested = false
		sequencer.note_rescuer_arrived()
		return
	var direction := to.normalized()
	actor.accept_network_input(Vector2(direction.x, direction.z), true)

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
	# A hand pickup snaps into the soul's hands when it is a real upgrade.
	loot.equip_target = Callable(self, "_loot_owner")
	for drop in WEAPON_DROPS:
		var pickup = loot.spawn(str(drop[0]), drop[1])
		if pickup != null:
			pickup.taken.connect(_on_pickup_taken)
			_pickups.append(pickup)

## Which mercenary a picked-up piece should be worn by, or -1.
func _loot_owner(peer_id: int) -> int:
	var actor = controller.body_for_peer(peer_id)
	if actor == null or not is_instance_valid(actor):
		return -1
	if not bool(actor.get("alive")) or bool(actor.get("downed")):
		return -1
	return controller.merc_for_peer(peer_id)

func _on_pickup_taken(pickup) -> void:
	_steel_taken += 1
	sequencer.note_weapon_looted()
	if hud != null and pickup != null:
		hud.set_status("%s is in hand." % str(pickup.label_text()), 2.5)
	if screen != null:
		screen.refresh()

# --- the freed squad's AI --------------------------------------------------

## Once a cage opens, the prisoner inside it stops being scenery: they arm
## themselves from the cultist steel on the ground and go for the watchers. This
## is deliberately a scene driver rather than the arena's `_bot_step`, because a
## squadmate's job is "loot, then close on a watcher", and the watchers are mobs
## the arena bot cannot see.
func _drive_allies(_delta: float) -> void:
	if controller == null or sequencer == null:
		return
	if sequencer.state() == SequencerScript.State.CAGED \
			or sequencer.state() == SequencerScript.State.ALL_SEEN:
		return
	var player_body = controller.active_body(1)
	for merc_id in squad_ids:
		if not _is_free_ally(int(merc_id)):
			continue
		var actor = controller.body_of(int(merc_id))
		if actor == null or not is_instance_valid(actor):
			continue
		if actor == player_body:
			continue
		if not bool(actor.get("alive")) or bool(actor.get("downed")):
			_hold(actor)
			continue
		actor.combat.damage_enabled = true
		var gear: Dictionary = warband.roster.equipped_of(int(merc_id))
		var roster_armed := not str(gear.get("main", "")).is_empty() \
			or not str(gear.get("off", "")).is_empty()
		# A body whose roster says armed but whose hands are empty is wearing a
		# stale loadout: re-dress it once before deciding it cannot fight.
		if roster_armed and not _holds_weapon(actor):
			_refresh_rig(int(merc_id))
		var armed := roster_armed and _holds_weapon(actor)
		# 1. An unarmed prisoner looks for steel first.
		if not armed:
			var pickup = _nearest_pickup_for(actor)
			if pickup != null:
				if actor.global_position.distance_to(pickup.global_position) <= 1.5:
					_hold(actor)
					_ally_take(actor, int(merc_id), pickup)
				else:
					_move_towards(actor, pickup.global_position)
				continue
		# 2. Armed, or nothing left to grab: go at the watchers.
		var watcher = _nearest_watcher(actor)
		if watcher == null:
			_hold(actor)
			continue
		var to: Vector3 = watcher.global_position - actor.global_position
		to.y = 0.0
		var distance := to.length()
		actor.combat.set_aim(watcher.get_aim_position())
		if distance > 2.0:
			_move_towards(actor, watcher.global_position)
			continue
		_hold(actor)
		if actor.rig.weapon == "bow":
			if actor.combat.can_draw():
				actor.combat.begin_draw()
			elif actor.rig.draw_amount >= 0.85:
				actor.combat.release_draw()
		elif actor.combat.clash_cooldown <= 0.0:
			actor.combat.begin_melee()
			_ally_engaged = true

## Whether the body is actually swinging something: the rig, not the roster.
func _holds_weapon(actor) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	if str(actor.rig.weapon) in ["sword", "dagger", "dual", "bow"]:
		return true
	return bool(actor.rig.staff_active) or bool(actor.rig.off_weapon_active)

## A body that is out of its cage and standing in the squad, or the rescuer once
## he has arrived. The player's own body is filtered by the caller.
func _is_free_ally(merc_id: int) -> bool:
	var index := caged_ids.find(merc_id)
	if index >= 0:
		return index < _cage_open.size() and bool(_cage_open[index])
	# The rescuer is the player's objective, not a squadmate: he stands still with
	# the shiv until the latches are cut, so he can never steal the beat by
	# charging the watchers on his own.
	return sequencer.state() == SequencerScript.State.FREED \
		or sequencer.state() == SequencerScript.State.ESCAPING \
		or sequencer.state() == SequencerScript.State.TOWN

func _move_towards(actor, point: Vector3) -> void:
	var to: Vector3 = point - actor.global_position
	to.y = 0.0
	if to.length_squared() <= 0.0001:
		_hold(actor)
		return
	var direction := to.normalized()
	actor.accept_network_input(Vector2(direction.x, direction.z), true)

func _hold(actor) -> void:
	actor.accept_network_input(Vector2.ZERO, false)

func _nearest_pickup_for(actor):
	var best = null
	var best_distance := 40.0
	for pickup in _pickups:
		if not is_instance_valid(pickup) or bool(pickup.collected):
			continue
		var distance: float = actor.global_position.distance_to(pickup.global_position)
		if distance < best_distance:
			best_distance = distance
			best = pickup
	return best

func _nearest_watcher(actor):
	var best = null
	var best_distance := 60.0
	for watcher in guards:
		if not is_instance_valid(watcher) or not bool(watcher.get("alive")):
			continue
		var distance: float = actor.global_position.distance_to(watcher.global_position)
		if distance < best_distance:
			best_distance = distance
			best = watcher
	return best

## A squadmate takes a drop for themselves: the vacuum books it and the piece is
## worn by that body (the player's pickup rule would arm the soul instead).
func _ally_take(actor, merc_id: int, pickup) -> void:
	var item_id := str(pickup.item_id)
	var result: Dictionary = loot.quick_loot(pickup, 0)
	if not bool(result.get("ok", false)):
		return
	var auto: Dictionary = warband.auto_equip(merc_id, item_id)
	# The roster is the truth, but the body in the yard still holds the old kit:
	# re-dress the live rig or a squadmate "carries" a sword it never draws.
	_refresh_rig(merc_id)
	if bool(auto.get("ok", false)) and hud != null:
		hud.set_status("%s takes the %s." % [warband.roster.name_of(merc_id),
			State.ITEMS.get(item_id, {}).get("name", item_id)], 2.5)
	actor.combat.stop()

## Re-apply a mercenary's current roster kit to the body standing in the scene.
func _refresh_rig(merc_id: int) -> void:
	if controller == null or merc_id <= 0:
		return
	controller.refresh_gear(merc_id)

## Watchers that are no longer standing.
func watchers_down() -> int:
	var down := 0
	for watcher in guards:
		if not is_instance_valid(watcher) or not bool(watcher.get("alive")):
			down += 1
	return down

## Steel the squad has picked up, whoever picked it up.
func steel_taken() -> int:
	return _steel_taken

## How many freed allies are holding a weapon, and whether any has swung at a
## watcher. Both are read by the regression.
func allies_armed() -> int:
	var count := 0
	var player_body = controller.active_body(1)
	for merc_id in squad_ids:
		if not _is_free_ally(int(merc_id)):
			continue
		var actor = controller.body_of(int(merc_id))
		if actor == null or not bool(actor.get("alive")):
			continue
		# The soul's own body is not an ally: its gear is the player's business.
		if actor == player_body:
			continue
		var gear: Dictionary = warband.roster.equipped_of(int(merc_id))
		var in_roster := not str(gear.get("main", "")).is_empty() \
			or not str(gear.get("off", "")).is_empty()
		if in_roster and _holds_weapon(actor):
			count += 1
	return count

func ally_engaged() -> bool:
	return _ally_engaged

# --- the watchers ----------------------------------------------------------

## Two antlered watchers, not arena bodies: they are real wilderness mobs with a
## camp profile (`cage_watcher.gd`), so they read as the wood's own creatures and
## die in a few stabs. They only turn to hunt once the first latch goes.
func _build_watchers() -> void:
	for index in GATE_WATCHERS.size():
		var spec: Dictionary = GATE_WATCHERS[index]
		var watcher := WatcherScript.new()
		watcher.name = "CampWatcher%d" % (index + 1)
		watcher.mob_id = "hollow_warden"
		add_child(watcher)
		watcher.global_position = spec["post"]
		watcher.player = controller.active_body(1)
		watcher.defeated.connect(_on_watcher_defeated)
		watcher.attacked.connect(_on_watcher_attack)
		guards.append(watcher)

## Keep the watchers pointed at whichever body the soul is wearing and, once the
## first cage is open, let them know the camp is awake.
func _maintain_watchers(delta: float) -> void:
	if guards.is_empty():
		return
	# Watchers hunt whoever is closest once the squad is loose: a freed prisoner
	# is a real threat, not a spectator.
	var nearest = controller.active_body(1)
	var best := INF
	for body in bodies:
		if not is_instance_valid(body) or not bool(body.get("alive")) or bool(body.get("downed")):
			continue
		var distance: float = body.global_position.distance_to(guards[0].global_position) \
			if is_instance_valid(guards[0]) else 0.0
		if distance < best:
			best = distance
			nearest = body
	if nearest != null and is_instance_valid(nearest):
		for watcher in guards:
			if is_instance_valid(watcher) and bool(watcher.get("alive")):
				watcher.player = nearest
	if cages_open_count() > 0 and not _watchers_awake:
		_watchers_awake = true
		for watcher in guards:
			if is_instance_valid(watcher) and bool(watcher.get("alive")):
				watcher.mob_wake()
	_guard_tick += 1

func _on_watcher_defeated(enemy, _reward: int) -> void:
	sequencer.note_guard_killed()
	if hud != null and is_instance_valid(enemy):
		hud.set_status("The watcher folds. One left." if sequencer.guards_down() == 1
			else "Both watchers are down.", 3.0)
	_update_hint()

## A watcher's swing lands on the warband body it was hunting. The mob emits the
## blow; the scene applies it through the body's own guard, exactly like the
## frontier's `_on_enemy_attack`.
func _on_watcher_attack(attacker, amount: float, victim) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(victim):
		return
	if victim.has_method("receive_melee"):
		victim.receive_melee(amount, WATCHER_SOURCE, attacker.global_position)
	elif victim.has_method("take_damage"):
		victim.take_damage(amount, WATCHER_SOURCE)

# --- sequencer -------------------------------------------------------------

## Raise the beat's card (once). The card pauses the game; the player reads it,
## presses G or clicks CONTINUE, and the lesson starts where it left off.
func _push_card(state: int) -> void:
	if card == null or state == _card_state:
		return
	if not STEP_CARDS.has(state):
		return
	_card_state = state
	var content: Dictionary = STEP_CARDS[state]
	card.show_step("step_%d" % state, str(content["kicker"]), str(content["title"]),
		str(content["body"]), str(content["keys"]), str(content["footnote"]))

func _on_state_changed(state: int, objective: String) -> void:
	_push_card(state)
	if hud != null:
		# The tutorial line lives top-centre for six seconds; the crosshair
		# prompt keeps the standing instruction between banners.
		hud.set_status(objective, 6.0)
		_prompt_text = objective
		hud.set_prompt(objective)
		_update_hint()
	# Entering the fight reconciles kills and steel the squad already landed
	# while the cages were still being cut.
	if state == SequencerScript.State.FREED:
		sequencer.note_battle_state(watchers_down(), _steel_taken)
	match state:
		SequencerScript.State.ALL_SEEN:
			_jogging = true
		SequencerScript.State.ESCAPING:
			if screen != null:
				screen.refresh()

## The rescuer is through and stands still: the soul is NOT moved for the player.
## Taking his body is the beat - F5 or [ ] - and no latch opens until Corvin's
## hands are the player's hands.
func _on_rescuer_ready(merc_id: int) -> void:
	_jogging = false
	_hold(controller.body_of(merc_id))
	if hud != null:
		hud.set_status("Corvin is through with the shiv. Press F5 (or [ ]) to take his body.", 6.0)

func _on_gate_ready() -> void:
	var path := town_scene_path()
	if hud != null:
		hud.set_status("The gate is open. Out of the camp.", 6.0)
	scene_requested.emit(path)

## Where the escape leads: whichever of the town hub paths this build actually
## has, so the hand-off works whichever worktree landed the file. Nothing is
## loaded here and the player is never moved out of the camp by this scene.
func town_scene_path() -> String:
	for path in TOWN_PATHS:
		if ResourceLoader.exists(str(path)):
			return str(path)
	return str(TOWN_PATHS[TOWN_PATHS.size() - 1])

## The gate is a door, not a trigger: the player walks into the arch and presses
## G, exactly like every other object in this game.
func _gate_in_reach() -> bool:
	var actor = controller.active_body(1)
	if actor == null or not is_instance_valid(actor):
		return false
	var flat := Vector3(actor.global_position.x - GATE_POINT.x, 0.0,
		actor.global_position.z - GATE_POINT.z)
	return flat.length() <= GATE_RADIUS

# --- possession ------------------------------------------------------------

func _on_possession_changed(peer_id: int, merc_id: int) -> void:
	if peer_id == 1 and hud != null:
		hud.set_body(controller.active_body(1), warband.roster.name_of(merc_id), merc_id)
	if caged_ids.has(merc_id):
		sequencer.note_body_entered(merc_id)
	if merc_id == rescuer_id:
		sequencer.note_rescuer_taken()

func _on_transfer_refused(_peer_id: int, merc_id: int, reason: String) -> void:
	if hud != null:
		hud.set_status("%s: %s" % [warband.roster.name_of(merc_id), reason], 2.5)

func _on_possession_released(_peer_id: int, reason: String) -> void:
	if hud != null:
		hud.set_body(null, "", -1)
		hud.set_status("The warband is down (%s)" % reason, 4.0)

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

# --- revive ----------------------------------------------------------------

func _revive_target():
	var actor = controller.active_body(1)
	if actor == null or not is_instance_valid(actor):
		return null
	var best = null
	var best_distance := Contracts.REVIVE_REACH
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
	if target == null:
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

# --- looting and prompts ---------------------------------------------------

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
		_refresh_rig(controller.merc_for_peer(1))
	hud.set_status(str(result.get("message", "")), 2.5)

## `G` is the tutorial's one interaction key: cut a latch, take the steel at your
## feet, or leave through the arch. Anything else repeats the objective.
func _try_interact() -> void:
	if _try_cage_latch():
		return
	var pickup = _nearest_pickup()
	if pickup != null:
		_try_loot()
		return
	if sequencer.state() == SequencerScript.State.ESCAPING and _gate_in_reach():
		sequencer.note_gate_reached()
		return
	if sequencer.state() == SequencerScript.State.ESCAPING:
		hud.set_status("Walk into the gate arch, then press G.", 3.0)
		return
	hud.set_status(sequencer.objective(), 4.0)

## The cage whose bars are closest to `point` while it is still shut, or -1.
func _cage_in_reach():
	var actor = controller.active_body(1)
	if actor == null or not is_instance_valid(actor):
		return -1
	var best := -1
	var best_distance := 3.2
	for index in caged_ids.size():
		if index < _cage_open.size() and bool(_cage_open[index]):
			continue
		var anchor: Vector3 = CAGE_POSTS[index]
		var flat := Vector3(actor.global_position.x - anchor.x, 0.0, actor.global_position.z - anchor.z)
		if flat.length() <= best_distance:
			best_distance = flat.length()
			best = index
	return best

## Cut one latch. Only the rescuer carries the shiv, so only his body can open a
## cage - which is the reason the soul is forced into him in the first place.
func _try_cage_latch() -> bool:
	if sequencer.state() != SequencerScript.State.RESCUER_ARRIVED:
		return false
	var index: int = _cage_in_reach()
	if index < 0:
		return false
	if controller.merc_for_peer(1) != rescuer_id:
		hud.set_status("Only Corvin has the shiv. Press F5 to take his body.", 3.0)
		return true
	_open_cage(index)
	return true

func _open_cage(index: int) -> void:
	if index < 0 or index >= _cage_open.size() or bool(_cage_open[index]):
		return
	_cage_open[index] = true
	sequencer.note_cage_opened(index)
	var name: String = warband.roster.name_of(int(caged_ids[index]))
	if hud != null:
		hud.set_status("Latch cut. %s is free (%d/%d)." % [name,
			cages_open_count(), caged_ids.size()], 3.0)
	_update_hint()

## `B` closes the fight out: the survivors walk the camp and the drops go to the
## shared stash. Refused while a guard is still on his feet, which is the one
## thing the tutorial must not shortcut.
func _try_finish_fight() -> void:
	if not cages_open():
		hud.set_status("The latches are still shut (%d/4)." % cages_open_count(), 2.0)
		return
	if sequencer.guards_down() < guards.size():
		hud.set_status("The guards still hold the gate.", 2.0)
		return
	var survivors: Array = []
	for body in bodies:
		if is_instance_valid(body) and bool(body.get("alive")) and not bool(body.get("downed")):
			survivors.append(body)
	var sweep: Dictionary = loot.sweep(survivors)
	hud.set_status("The camp is quiet.  %d pieces gathered." % int(sweep.get("collected", 0)), 5.0)
	if screen != null:
		screen.refresh()

func _update_prompt() -> void:
	if hud == null or _reviving or sequencer == null:
		return
	var text := ""
	var target = _revive_target()
	if target != null:
		text = "Hold E - revive %s" % warband.roster.name_of(int(controller.merc_of(target)))
	else:
		var pickup = _nearest_pickup()
		var cage: int = _cage_in_reach()
		if pickup != null:
			text = "K - loot %s" % str(pickup.label_text())
		elif cage >= 0 and sequencer.state() == SequencerScript.State.RESCUER_ARRIVED:
			text = "G - cut the latch" if controller.merc_for_peer(1) == rescuer_id \
				else "F5  -  take Corvin's body"
		elif _gate_in_reach() and sequencer.state() == SequencerScript.State.ESCAPING:
			text = "G - leave the camp"
		else:
			text = sequencer.objective()
	# The objective is rebuilt from live counters every frame; the label is only
	# touched when the line itself changes.
	if text != _prompt_text:
		_prompt_text = text
		hud.set_prompt(text)

## The standing key line: the sequencer's beat hint, refined by whatever the body
## is standing next to. Rebuilt every frame and only written when it changes, so
## a player who looks away can always find the next button.
func _update_hint() -> void:
	if hud == null or sequencer == null:
		return
	var text: String = sequencer.hint()
	if _revive_target() != null:
		text = "Hold E - revive the downed body beside you   ·   G - cut a latch"
	elif _gate_in_reach() and sequencer.state() == SequencerScript.State.ESCAPING:
		text = "G - leave the camp for town"
	elif _cage_in_reach() >= 0 and sequencer.state() == SequencerScript.State.RESCUER_ARRIVED:
		if controller.merc_for_peer(1) != rescuer_id:
			text = "F5  or  [ ]  -  take Corvin's body: only his shiv cuts a latch"
		else:
			text = "G - cut this cage's latch   (%d of %d opened)" % [
				cages_open_count(), caged_ids.size()]
	if text != _hint_text:
		_hint_text = text
		hud.set_hint(text)

# --- ui --------------------------------------------------------------------

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
	paperdoll.changed.connect(func() -> void:
		if paperdoll.selected_merc > 0:
			_refresh_rig(paperdoll.selected_merc))
	card = CardScript.new()
	card.name = "TutorialCard"
	add_child(card)
