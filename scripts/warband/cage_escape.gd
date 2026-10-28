extends Node3D
## GHOST OF THE WARBAND: the camp in the deep wood, and the lesson that starts in
## it.
##
## The camp is the first quarter of one continuous world: four cages in a ragged
## pocket cut into the drowned wood, a fifth prisoner loose behind them, two
## watchers between the squad and the way out - and, a long run of ordinary trees
## past the gap in the wood, the trail that leads to town. There is no arch and no
## door here any more. The way out is a walk, and the road is not in sight of it.
##
## The node has two ways to live:
##
##   * **embedded** - `world_scene.gd` sets `host` before the node enters the
##     tree and calls `embed()` after it. The world owns the one
##     `PossessionController`, camera, `WarbandHud`, panels, tutorial card, loot
##     vacuum, revive channel and squad AI; this node brings its camp, its
##     watchers and its lesson, and writes nothing on the tree but props.
##   * **alone** - `scenes/cage_escape.tscn` builds the camp with no bodies and
##     no HUD. It is the area preview the art regression loads, because the camp
##     is otherwise only visible as a quarter of the world.
##
## What the camp owns: the four cages and their latches, the clamp that keeps a
## caged soul in its cage, the rescuer's jog and the two watchers he puts down
## himself, the six armed watchers that answer the squad leaving, the sequencer's
## beats and the cards that explain them. What it never owns in the world: the
## bodies, the camera, the HUD prompt, the revive channel or the loot vacuum.
##
## The opening is four beats, and the third one is the player's hands: see the
## four bodies, watch Corvin take the pair, step into him for the only blade in
## the camp, then walk cage to cage cutting one latch each with `G`. Nothing opens
## on its own, and the fourth latch is what puts the squad on its feet. Past the
## mouth is trees for `CAMP_TO_ROAD_METRES` before the trail's first torch.
##
## The geometry is `camp_clearing.gd` (wood, ragged stakes, cages, huts, fire) and
## the dressing is `camp_dressing.gd` (padlocks, banners, gibbets, braziers,
## litter). The layout constants below are the camp's contract: the dressing
## mirrors the pocket, the art regression reads the spawns, the world reads the
## mouth and the distance to the road.

## The prison squad. Four wretches in rags and the one who kept his shiv.
const PRISONER_NAMES := ["Ash", "Bram", "Het", "Wren"]
const RESCUER_NAME := "Corvin"
const SQUAD_SIZE := 5
const PRISONER_COUNT := 4
const RESCUER_INDEX := 4

## Cage centres, in a line facing the way out. y is the height a body spawns at.
const CAGE_POSTS := [
	Vector3(-7.6, 0.2, 6.0), Vector3(-2.6, 0.2, 6.0),
	Vector3(2.6, 0.2, 6.0), Vector3(7.6, 0.2, 6.0),
]
## Where the loose prisoner waits: between the cages and the watchers.
const RESCUER_POST := Vector3(1.4, 0.2, -23.0)
## The way out: not a gate and not a road - the gap the wood leaves between its
## trees at the camp's front line. Past it is nothing but wood for
## `CAMP_TO_ROAD_METRES`.
const GATE_POINT := Vector3(0.0, 0.0, -30.0)
const GATE_RADIUS := 3.5
const MOUTH_HALF_WIDTH := 6.0
## Flat metres of nothing but wood between the camp's front line and the road's
## first waypoint. The world places the lane off this number and the geometry
## builds the corridor through the trees to match it, so the two cannot drift.
const CAMP_TO_ROAD_METRES := 170.0
## The camp pocket: ragged, treed and smaller than the fence yard it grew out of.
## There is no fence line any more - the wood is the boundary - so these are the
## extents the dressing, the art regression and the reach checks measure against.
const YARD_HALF_WIDTH := 20.0
const YARD_FRONT := -30.0
const YARD_BACK := 22.0
## Where the rescuer's jog ends: just in front of the cage line.
const JOG_TARGET := Vector3(0.0, 0.0, 8.6)
const JOG_STOP := 1.6
## How far a caged body may stray from its own cage centre.
const CAGE_CLAMP_RADIUS := 0.95
## Half the cage's footprint. A latch is worked through the bars or from the dirt
## in front of them, so reach is measured from the cage's edge, not its centre.
const CAGE_HALF := 1.25
## How close a body has to be to a cage, edge to feet, to work its latch.
const LATCH_REACH := 2.2
## How far the cage doors rise when their latches go.
const CAGE_BAR_LIFT := 2.6
const BAR_LIFT_SPEED := 2.2
## The camp's torches: at the cages, at the watchers, and along the pocket's
## ragged edge, so the camp is a lit hole in the wood rather than a black field.
const CAMP_TORCHES := [
	[Vector3(-10.5, 0, 4.2), 0.9], [Vector3(10.5, 0, 4.2), 0.9],
	[Vector3(-5.0, 0, -26.5), 1.0], [Vector3(5.0, 0, -26.5), 1.0],
	[Vector3(-5.8, 0, -12.0), 0.75], [Vector3(-11.0, 0, -19.0), 0.8],
	[Vector3(11.0, 0, -19.0), 0.8], [Vector3(-15.5, 0, 14.0), 0.85],
	[Vector3(15.5, 0, 14.0), 0.85], [Vector3(-16.0, 0, -2.0), 0.85],
	[Vector3(16.0, 0, -2.0), 0.85],
]

## The two gate watchers: wardens out of the same kit as the rest of the wood, but
## the camp's own mooks. They stand between the cages and the mouth, turn on Corvin
## the moment he turns on them, and are thinned here so his shiv finishes the pair
## without the player's help.
##
## A watcher now fights like the body it is - its variant's blade, its variant's
## guard - so the pair's pool and blow are the camp's numbers, not the wild's:
## `PAIR_LESSON_HEALTH` is three stabs of the ironwood shiv (10 damage each), and
## `PAIR_BLOW_SCALE` halves what the pair lands, because two of them swinging at
## once would otherwise put Corvin down before the fourth stab. The six that come
## out of the wood afterwards keep the hardened pool and their full blows.
const PAIR_LESSON_HEALTH := 30.0
const PAIR_BLOW_SCALE := 0.5
const GATE_WATCHERS := [
	{"post": Vector3(-4.2, 0.1, -20.5)},
	{"post": Vector3(4.2, 0.1, -20.5)},
]
## The second wave: the ambush the whole opening walks towards, and the first time
## the player faces a *group*. They come when the squad steps out of the camp - the
## trees answer the leaving, not a kill count - and they are deliberately the
## softest bodies in the wood, because a squad that has just been handed its first
## weapons should win this fight:
##
##   * four of them, not six, and never armoured;
##   * `AMBUSH_HEALTH` 60, so two ironwood stabs or three club hits put one down;
##   * `AMBUSH_BLOW_SCALE` 0.5, so a club lands 3, a shiv 5 and a branch 7;
##   * `AMBUSH_GUARD_SCALE` 0.45 and `AMBUSH_SWING_GAP_SCALE` 1.9, so they swing
##     late and rarely turtle - an ambusher that trades blows is a fight, one that
##     guards every exchange is a wall.
##
## Everything they carry is the makeshift tier: there is no forged steel anywhere
## in this wood.
const AMBUSH_COUNT := 4
const AMBUSH_HEALTH := 60.0
const AMBUSH_BLOW_SCALE := 0.5
const AMBUSH_GUARD_SCALE := 0.45
const AMBUSH_SWING_GAP_SCALE := 1.9
const REINFORCEMENTS := [
	"club_makeshift", "dagger_ironwood", "club_makeshift", "bow_twig",
	"club_makeshift", "dagger_ironwood",
]
## How close the soul's body has to be to the mouth for the wood to answer it.
const ESCAPE_RADIUS := 6.0
## Out past the mouth, coming down the corridor between the trees.
const REINFORCE_POSTS := [
	Vector3(-3.4, 0.1, -40.0), Vector3(-2.0, 0.1, -41.0), Vector3(-0.7, 0.1, -42.0),
	Vector3(0.7, 0.1, -42.0), Vector3(2.0, 0.1, -41.0), Vector3(3.4, 0.1, -40.0),
]

const WATCHER_SOURCE := 90
## What a sword in this camp is allowed to bite: the watchers' physics layer.
## `ArenaActor` defaults to 4 (other fighters); a warband body that kept that
## mask swings through every mob in the game and damages nothing.
const WATCHER_LAYER := 2
## What lies in the camp for the squad to arm itself off once it is out: three
## makeshift blades, all of them things a body can swing.
const WEAPON_DROPS := [
	["club_makeshift", Vector3(-0.8, 0.15, -0.5)],
	["dagger_ironwood", Vector3(4.4, 0.15, -10.0)],
	["branch_heavy", Vector3(-4.6, 0.15, -16.5)],
]
## One big card per beat. The card pauses the game, so every line has to be
## worth reading: the lesson, then the exact keys, then the one way out. The only
## card that names `G` is the one where `G` cuts a latch, and no card claims a
## latch opens itself.
const STEP_CARDS := {
	0: {  # CAGED
		"kicker": "STEP 1  /  THE CAGES",
		"title": "You are a soul, not a body",
		"body": "Four prisoners hang in this camp, and your soul can enter any living body. Shift between them: that is the whole game.",
		"keys": "F1  F2  F3  F4        or        [  ]        enter another prisoner",
		"footnote": "Enter or click CONTINUE to play. TAB opens the warband, P your gear.",
	},
	1: {  # ALL_SEEN
		"kicker": "STEP 2  /  THE SHIV",
		"title": "All four seen - here he comes",
		"body": "The fifth prisoner is loose, and he is running for the cages with a knife. He is not here to talk: he goes straight at the two watchers, and he puts them down himself.",
		"keys": "Watch him work",
		"footnote": "Close this card and let him arrive - you do not have to help.",
	},
	2: {  # RESCUER_ARRIVED
		"kicker": "STEP 3  /  THE LATCHES",
		"title": "Four cages, four latches, one shiv",
		"body": "No cage opens by itself: somebody has to stand at each one and cut its latch. Only Corvin kept a blade. Take his body, then walk the cage line and cut them one at a time.",
		"keys": "F5  or  [ ]  -  take Corvin        ·        G at a cage  -  cut its latch",
		"footnote": "One latch per cage, four in all, and bare hands on a padlock cut nothing.",
	},
	3: {  # FREED
		"kicker": "STEP 4  /  OUT",
		"title": "Four latches cut, five bodies on their feet",
		"body": "The squad arms itself from what lies in the camp - you do not have to loot anything. The way on is the gap in the trees at the far end of the pocket: no road, just wood, and the trail's first torch is a long run off.",
		"keys": "W A S D  -  walk out through the gap in the trees",
		"footnote": "Whatever is standing in those trees comes when you leave, not before.",
	},
	4: {  # ESCAPING
		"kicker": "STEP 5  /  THE TRAIL",
		"title": "The trees answer: run for the road",
		"body": "Six armed watchers step out of the wood behind you, and the trail is held the whole way down. The squad comes with you. There is no door to open and nowhere to be carried - you run it.",
		"keys": "W A S D  -  run the wood        ·        LMB / RMB  -  fight",
		"footnote": "The road is a long run through the trees; the town's counters, altar and expedition gate are at its far end, on foot.",
	},
}

## Corvin's own constitution. He is not a wretch behind bars: he kept his shiv,
const SequencerScript = preload("res://scripts/warband/tutorial_sequencer.gd")
const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const ClearingScript = preload("res://scripts/warband/camp_clearing.gd")
const DressingScript = preload("res://scripts/warband/camp_dressing.gd")
const RunForestScript = preload("res://scripts/warband/run_forest.gd")
const State = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")

## The world scene that embeds this camp, or null when the camp stands alone.
## Set before the node enters the tree.
var host: Node3D = null

var warband
var controller
var sequencer
var hud
var screen
var paperdoll
var card
var loot
## The one squad module, owned by the world: a freed prisoner is driven by the
## same behaviour that escorts the soul down the trail.
var squad
var bodies: Array = []
## The camp's own watchers. `host.guards` is the world's single hostile list, so
## a watcher here is in both.
var guards: Array = []
var rescuer_id := -1
var squad_ids: Array[int] = []
var caged_ids: Array[int] = []
var clearing: Dictionary = {}

var _cage_anchors: Dictionary = {}   # merc_id -> the cage centre it is held in
var _cage_doors: Array = []          # [{node, lift}, ...]
var _pickups: Array = []
var _jogging := false
var _cage_open: Array[bool] = []     # per cage, in CAGE_POSTS order
var _watchers_awake := false
var _card_state := -1
var _steel_taken := 0
var _prompt_text := ""
var _hint_text := ""
var _lesson := false


func _ready() -> void:
	warband = host.warband if host != null else get_node_or_null("/root/Warband")
	if warband == null:
		push_error("CageEscape needs the Warband autoload")
		return
	if host == null:
		_build_night()
		_build_floor()
	_build_clearing()
	if host == null:
		_install_watchers()


## Adopt the pieces the world owns and put the camp's watchers on the field. The
## world calls this once, after the camp is in the tree and before the lesson.
func embed(world: Node3D) -> void:
	host = world
	warband = world.warband
	controller = world.controller
	loot = world.loot
	hud = world.hud
	screen = world.screen
	paperdoll = world.paperdoll
	card = world.card
	squad = world.squad
	_pickups = world.pickups
	_install_watchers()


# --- the world's side of the camp ------------------------------------------

## Where the warband stands when the campaign starts in the camp.
func spawn_posts() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for post in CAGE_POSTS:
		points.append(post)
	points.append(RESCUER_POST)
	return points


## Dress an empty warband as the prison squad (four in rags, the rescuer with a
## shiv) and mark it as the line this camp fields. A warband that already has
## bodies keeps them; a thin one is topped up with prisoners rather than bending
## the lesson around it.
func seed_warband() -> void:
	var living: Array = warband.alive_merc_ids()
	if living.is_empty():
		for prisoner in PRISONER_NAMES:
			var merc_id: int = warband.add_mercenary(str(prisoner))
			_dress_rags(merc_id)
			warband.roster.unequip(merc_id, "main")
			warband.roster.unequip(merc_id, "off")
		var rescuer: int = warband.add_mercenary(RESCUER_NAME)
		_dress_rags(rescuer)
		warband.roster.equip(rescuer, "main", "dagger_ironwood")
		living = warband.alive_merc_ids()
	else:
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
		warband.roster.equip(rescuer_id, "main", "dagger_ironwood")
	caged_ids.clear()
	for index in PRISONER_COUNT:
		caged_ids.append(squad_ids[index])
	warband.deploy_battle(squad_ids)
	_cage_open.clear()
	for index in caged_ids.size():
		_cage_open.append(false)


## The rags every prisoner in this camp is wearing, and nothing in their hands.
func _dress_rags(merc_id: int) -> void:
	# The naked set, whole: an old shirt, tight shorts, and bare head, hands and
	# feet. Nothing guards anything, and no hand carries a weapon - every piece
	# they fight in comes off a corpse or out of the stash.
	for slot in ArmorData.SLOTS:
		var garb := ArmorData.item_id(ArmorData.SET_IDS.find("naked"), slot)
		if State.ITEMS.has(garb):
			warband.roster.equip(merc_id, slot, garb)


## Put the bodies the scene spawned at the cages, point their swords at the wood
## and hold the four caged ones in. The camp's own drops go on the floor here.
func place_warband(bodies_in: Array) -> void:
	bodies = bodies_in
	for actor in bodies:
		if not is_instance_valid(actor):
			continue
		var merc_id: int = controller.merc_of(actor)
		var post := _post_for(merc_id)
		actor.global_position = post
		actor.spawn_point = post
		# `ArenaActor` is born hostile only to other arena bodies (layer 4). This
		# camp's enemies are the wilderness watchers (layer 2), and the squad must
		# never cut its own fighters, so the swords look at the mob layer only.
		actor.combat.target_mask = WATCHER_LAYER
		controller.set_bot(merc_id, false)
	for merc_id in caged_ids:
		_cage_anchors[merc_id] = _post_for(merc_id)
	# The rescuer stays on the same hundred every mercenary has: an NPC with a
	# private pool would break the contract and carry the extra health into the
	# roster. He survives the pair on the shiv's own passive instead (see the
	# squad's dagger variant), not on a bigger pool.
	for drop in WEAPON_DROPS:
		_spawn_pickup(str(drop[0]), drop[1])


## Start the lesson: the sequencer, the cards and the beat that opens the game.
## Only the camp the campaign *starts* in does this. A camp the warband walks
## back to later keeps its cages, its guards and nothing else.
func begin_lesson() -> void:
	if _lesson or caged_ids.is_empty():
		return
	_lesson = true
	sequencer = SequencerScript.new()
	sequencer.name = "Tutorial"
	add_child(sequencer)
	sequencer.state_changed.connect(_on_state_changed)
	sequencer.rescuer_ready.connect(_on_rescuer_ready)
	sequencer.begin(rescuer_id)
	sequencer.announce()
	controller.direct(1, caged_ids[0])
	_push_card(sequencer.state())


## True while the lesson is running, i.e. while the four cages hold their souls.
func lesson_running() -> bool:
	return _lesson and sequencer != null


## Whether this mercenary is free to act as a squadmate: a prisoner whose latch
## has been cut, or anybody who was never in a cage. Corvin is still not an
## escort - nobody is ever put in his body for the player - but the pair standing
## over the cages are his, and he takes them on through the squad's own module.
## That module leaves the body the player is inside alone, so the moment the soul
## steps into him the hands are the player's. Once the pair are down and the
## latches still shut he holds: the trail's cultists are not his to chase.
func is_free(merc_id: int) -> bool:
	if merc_id <= 0:
		return false
	if not lesson_running():
		return not is_cage_clamped(merc_id)
	var index := caged_ids.find(merc_id)
	if index >= 0:
		return index < _cage_open.size() and bool(_cage_open[index])
	if merc_id == rescuer_id:
		if sequencer.state() == SequencerScript.State.RESCUER_ARRIVED:
			return watchers_down() < GATE_WATCHERS.size()
		return sequencer.state() == SequencerScript.State.FREED \
			or sequencer.state() == SequencerScript.State.ESCAPING
	return true


## The lesson's prompt line, or "" when the camp has nothing to say about where
## the body stands. The world writes it to the one HUD.
func prompt_line(actor) -> String:
	if not lesson_running() or actor == null or not is_instance_valid(actor):
		return ""
	if sequencer.state() == SequencerScript.State.ESCAPING:
		# The lesson is over: the world's own line - the trail and the metres to
		# the town - is what a body needs then, not a stale instruction.
		return ""
	return sequencer.objective()


## The lesson's key line, or "" when the body is not the camp's business.
func hint_line(actor) -> String:
	if not lesson_running() or actor == null or not is_instance_valid(actor):
		return ""
	if not _in_camp(actor) and sequencer.state() != SequencerScript.State.ESCAPING:
		return ""
	return sequencer.hint()


## How many latches have been cut, 0..4. One per cage, in any order, and the
## fourth is what looses the squad: this is a progress count, not an all-or-nothing
## answer.
func cages_open_count() -> int:
	var count := 0
	for open in _cage_open:
		if bool(open):
			count += 1
	return count


func cages_open() -> bool:
	for open in _cage_open:
		if not bool(open):
			return false
	return not _cage_open.is_empty()


func is_cage_clamped(merc_id: int) -> bool:
	var index := caged_ids.find(merc_id)
	if index < 0:
		return false
	return index >= _cage_open.size() or not bool(_cage_open[index])


func cage_anchor_for(merc_id: int) -> Vector3:
	return _cage_anchors.get(merc_id, Vector3.ZERO)


## Watchers of the camp's that are no longer standing.
func watchers_down() -> int:
	var down := 0
	for watcher in guards:
		if not is_instance_valid(watcher) or not bool(watcher.get("alive")):
			down += 1
	return down


## Steel the squad has picked up, whoever picked it up.
func steel_taken() -> int:
	return _steel_taken


func allies_armed() -> int:
	return squad.armed_count() if squad != null else 0


func ally_engaged() -> bool:
	return squad != null and squad.engaged


func pickups() -> Array:
	return _pickups


## A pickup left the floor (a squadmate's or the player's). Counted silently: the
## escape never asks the player to loot anything.
func note_pickup() -> void:
	_steel_taken += 1
	if sequencer != null:
		sequencer.note_weapon_looted()
	if screen != null:
		screen.refresh()


# --- running ---------------------------------------------------------------

func _process(delta: float) -> void:
	_advance_cage_doors(delta)


func _physics_process(delta: float) -> void:
	if not lesson_running() or controller == null:
		return
	_rescuer_jog()
	_maintain_watchers()
	_clamp_caged_bodies()
	_check_escape()


# --- the camp --------------------------------------------------------------

## Build the camp's own bones: the ragged pocket in the deep wood, the four cages,
## the huts and the fire, and then the dressing that reads it. Everything that may
## not be planted over - the cages, the altar, the huts, the fire, the torches, the
## dressing's own posts, and the walk from the cages to the gap in the trees - is
## handed to the geometry as `keep_clear`, because the wood is planted *inside* the
## pocket as well as around it.
func _build_clearing() -> void:
	var keep_clear: Array = []
	for post in CAGE_POSTS:
		keep_clear.append({"point": post, "radius": 3.1})
	for post in DressingScript.GIBBET_POSTS:
		keep_clear.append({"point": post, "radius": 3.2})
	for post in DressingScript.BANNER_POSTS:
		keep_clear.append({"point": post, "radius": 2.2})
	for post in DressingScript.BRAZIER_POSTS:
		keep_clear.append({"point": post, "radius": 2.0})
	for entry in CAMP_TORCHES:
		keep_clear.append({"point": entry[0], "radius": 1.6})
	keep_clear.append({"point": RESCUER_POST, "radius": 2.2})
	for watcher in GATE_WATCHERS:
		keep_clear.append({"point": watcher["post"], "radius": 2.0})
	# The walk the lesson is played on: cage to cage, then down the pocket to the
	# gap in the trees. The wood closes in around it but never on it.
	for post in ClearingScript.WALK_SPINE:
		keep_clear.append({"point": post, "radius": 4.2})
	clearing = ClearingScript.build(self, {
		"half_width": YARD_HALF_WIDTH,
		"front": YARD_FRONT,
		"back": YARD_BACK,
		"cage_posts": CAGE_POSTS,
		"mouth": GATE_POINT,
		"mouth_half_width": MOUTH_HALF_WIDTH,
		"to_road": CAMP_TO_ROAD_METRES,
		"torches": CAMP_TORCHES,
		"keep_clear": keep_clear,
	}, RunForestScript.night_style())
	_cage_doors.clear()
	for entry in clearing.get("doors", []) as Array:
		_cage_doors.append({"node": entry, "lift": 0.0})
	DressingScript.build(self)


## Every cage door rises when its latch goes: the bars climb out of the frame and
## the prisoner is out of the lesson.
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


func _post_for(merc_id: int) -> Vector3:
	var index := caged_ids.find(merc_id)
	if index >= 0:
		return CAGE_POSTS[index]
	return RESCUER_POST


func _in_camp(actor) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var at: Vector3 = actor.global_position
	return absf(at.x) <= YARD_HALF_WIDTH + 6.0 and at.z >= YARD_FRONT - 10.0 \
		and at.z <= YARD_BACK + 6.0


## Spawn a piece of cultist steel into the world's one loot vacuum.
func _spawn_pickup(item_id: String, at: Vector3) -> void:
	if item_id.is_empty():
		return
	if host != null:
		host.spawn_pickup(item_id, at)


# --- the squad and the rescuer ---------------------------------------------

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


# --- the watchers ----------------------------------------------------------

## The two watchers between the cages and the mouth: real wilderness mobs with a
## camp profile (`cage_watcher.gd`), so they read as the wood's own creatures and
## die in a few stabs. They only turn to hunt once the first latch goes.
func _install_watchers() -> void:
	for index in GATE_WATCHERS.size():
		var spec: Dictionary = GATE_WATCHERS[index]
		# Corvin's pair are the lesson's mooks: three shiv stabs each, half blows.
		var watcher := _add_watcher(spec["post"],
			"CampWatcher%d" % (guards.size() + 1), "", PAIR_LESSON_HEALTH)
		watcher.blow_scale = PAIR_BLOW_SCALE


func _add_watcher(at: Vector3, label: String, weapon: String = "",
		health: float = WatcherScript.HARDENED_HEALTH) -> Node3D:
	var watcher := WatcherScript.new()
	watcher.name = label
	watcher.mob_id = "hollow_warden"
	watcher.health_pool = health
	watcher.position = at
	add_child(watcher)
	watcher.global_position = at
	if controller != null:
		watcher.player = controller.active_body(1)
	watcher.defeated.connect(_on_watcher_defeated)
	watcher.attacked.connect(_on_watcher_attack)
	if not weapon.is_empty():
		watcher.arm(weapon)
	guards.append(watcher)
	if host != null:
		host.guards.append(watcher)
	return watcher


## The pair wake the moment Corvin is at the cages - he is going straight at them,
## and a watcher that waited to be noticed would be a prop. They take him as their
## quarry, which is also what keeps them off the caged bodies while he works, and
## the squad module that runs him swings back. Waking has nothing to do with a
## latch: a player who walks up to the cages is already in the fight.
func _maintain_watchers() -> void:
	if guards.is_empty() or _watchers_awake:
		return
	if sequencer == null or sequencer.state() != SequencerScript.State.RESCUER_ARRIVED:
		return
	_watchers_awake = true
	var prey = controller.body_of(rescuer_id) if controller != null else null
	for watcher in guards:
		if not is_instance_valid(watcher) or not bool(watcher.get("alive")):
			continue
		watcher.mob_wake()
		if prey != null and is_instance_valid(prey):
			watcher.hunt(prey)


func _on_watcher_defeated(enemy, _reward: int) -> void:
	if sequencer != null:
		sequencer.note_guard_killed()
	# The steel comes out of its hand and lands in the dirt: a watcher that falls
	# leaves the piece it was swinging where a body can pick it up with K, and
	# the squad can see it. What is left on the body is the rag it wore, which is
	# the corpse screen's business.
	if is_instance_valid(enemy) and loot != null:
		_drop_held_weapon(enemy)
		if loot.has_method("register_corpse"):
			loot.register_corpse(enemy)
	# Nothing opens on a death: the latches are the player's own walk from cage to
	# cage, and a corpse in the dirt has never cut one.


## Take the catalog piece out of a fallen body's hand and put it on the ground
## beside it, through the world that owns the one loot list.
func _drop_held_weapon(enemy) -> bool:
	if host != null and host.has_method("drop_held_weapon"):
		return bool(host.drop_held_weapon(enemy))
	return false



## The ambush: six watchers out of the wood past the mouth, each carrying the
## makeshift weapon it will drop when it falls. They are pointed at the nearest
## body on the frame they exist, so they charge in instead of waiting to be
## noticed.
func _spawn_reinforcements() -> void:
	var prey = nearest_standing_body(REINFORCE_POSTS[2])
	for index in AMBUSH_COUNT:
		var post: Vector3 = REINFORCE_POSTS[index % REINFORCE_POSTS.size()]
		var watcher := _add_watcher(post, "CampWatcher%d" % (guards.size() + 1),
			str(REINFORCEMENTS[index % REINFORCEMENTS.size()]), AMBUSH_HEALTH)
		watcher.blow_scale = AMBUSH_BLOW_SCALE
		watcher.guard_scale = AMBUSH_GUARD_SCALE
		watcher.swing_gap_scale = AMBUSH_SWING_GAP_SCALE
		if prey != null:
			watcher.hunt(prey)


## The nearest standing body to a point, through the world's own answer.
func nearest_standing_body(point: Vector3):
	if host != null:
		return host.nearest_standing_body(point)
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


## A watcher's swing lands on the warband body it was hunting. The mob emits the
## blow; the scene applies it through the body's own guard, exactly like the
## frontier's `_on_enemy_attack`.
func _on_watcher_attack(attacker, amount: float, victim) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(victim):
		return
	# The blow already carries the body's own `blow_scale` - the pair lands half a
	# swing, the ambush lands half a swing, a hardened body lands all of it - so
	# the scene weighs nobody a second time here.
	if victim.has_method("receive_melee"):
		victim.receive_melee(amount, WATCHER_SOURCE, attacker.global_position)
	elif victim.has_method("take_damage"):
		victim.take_damage(amount, WATCHER_SOURCE)


# --- sequencer -------------------------------------------------------------

## Raise the beat's card (once). The card pauses the game; the player reads it,
## presses Enter or clicks CONTINUE, and the lesson starts where it left off.
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
		hud.set_status(objective, 6.0)
	_write_prompt(objective, objective)
	if state == SequencerScript.State.FREED and squad != null:
		squad.following = false
	match state:
		SequencerScript.State.ALL_SEEN:
			_jogging = true
		SequencerScript.State.RESCUER_ARRIVED:
			# A player who was already wearing Corvin when the beat arrived is in
			# his hands already: the card must not ask for a body they are in.
			if controller != null and controller.merc_for_peer(1) == rescuer_id \
					and sequencer != null:
				sequencer.note_rescuer_taken()
		SequencerScript.State.ESCAPING:
			# The squad stops holding the camp and runs the wood with the soul:
			# the same module, one escort clause.
			if squad != null:
				squad.following = true
				squad.engage_radius = 34.0
			if screen != null:
				screen.refresh()


## The rescuer is at the cages with the shiv, and he does not wait there: the
## squad module takes him over on the next frame and he goes at the pair. The
## soul is NOT moved into him for the player - taking his body is the beat.
func _on_rescuer_ready(merc_id: int) -> void:
	_jogging = false
	var actor = controller.body_of(merc_id) if controller != null else null
	if actor != null and is_instance_valid(actor):
		actor.accept_network_input(Vector2.ZERO, false)
	if hud != null:
		hud.set_status("Corvin is at the cages. Press F5 (or [ ]) to take his body - then G at each cage.", 6.0)


## A possession happened. The world owns the controller, so it calls this even
## when the camp's lesson is not running; only the lesson reads it.
func note_possession(merc_id: int) -> void:
	if sequencer == null:
		return
	if caged_ids.has(merc_id):
		sequencer.note_body_entered(merc_id)
	if merc_id == rescuer_id:
		sequencer.note_rescuer_taken()


# --- the latches -----------------------------------------------------------

## The camp's share of the one `G`. True when the press was the camp's: a latch
## was cut, or the body is standing at a shut cage with nothing to cut it with and
## has been told so. False hands the press on to the town counters and the floor.
func interact(actor) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var index := latch_target(actor)
	if index < 0:
		return false
	if not holds_blade(actor):
		_set_status("Nothing to cut the latch with.", 2.5)
		return true
	return open_latch(index)


## The nearest still-closed cage the body can reach its latch of, or -1. Reach is
## measured from the cage's own edge, so a body standing at the bars and a body
## standing a step back are both at the padlock.
func latch_target(actor) -> int:
	if actor == null or not is_instance_valid(actor) or _cage_open.is_empty():
		return -1
	var at: Vector3 = actor.global_position
	var best := -1
	var best_gap := LATCH_REACH
	for index in CAGE_POSTS.size():
		if index < _cage_open.size() and bool(_cage_open[index]):
			continue
		var post: Vector3 = CAGE_POSTS[index]
		var gap := maxf(0.0, Vector2(at.x - post.x, at.z - post.z).length() - CAGE_HALF)
		if gap <= best_gap:
			best_gap = gap
			best = index
	return best


## Whether the body has a blade in its hands to work a latch with: the rig's main
## hand, or a second weapon in the off hand. A fist, a shield or a bow is not a
## knife.
func holds_blade(actor) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var rig = actor.get("rig")
	if rig == null or not is_instance_valid(rig):
		return false
	if str(rig.weapon) in ["sword", "dagger", "dual"]:
		return true
	return bool(rig.off_weapon_active) and str(rig.off_weapon_kind) in ["sword", "dagger"]


## One latch, cut: the door lifts, the prisoner's clamp is gone and the sequencer
## books the cage. The fourth cut is what looses the squad. Returns false only
## when the cage is already open or does not exist - the press was not consumed.
func open_latch(index: int) -> bool:
	if index < 0 or index >= CAGE_POSTS.size() or index >= _cage_open.size():
		return false
	if bool(_cage_open[index]):
		return false
	_cage_open[index] = true
	var cut := cages_open_count()
	if sequencer != null:
		sequencer.note_cage_opened(index)
	if cages_open():
		_set_status("The fourth latch falls. The squad is out and arming itself.", 4.0)
	else:
		_set_status("Latch cut. %d of %d cages open." % [cut, CAGE_POSTS.size()], 2.5)
	return true


## The ambush is the leaving. Once the squad is out, the soul's body reaching the
## gap in the trees is what calls the wood down: the state turns and the six walk
## out of it on the same frame.
func _check_escape() -> void:
	if sequencer == null or sequencer.state() != SequencerScript.State.FREED:
		return
	var actor = controller.active_body(1) if controller != null else null
	if actor == null or not is_instance_valid(actor):
		return
	var flat := Vector2(actor.global_position.x - GATE_POINT.x,
		actor.global_position.z - GATE_POINT.z)
	if flat.length() > ESCAPE_RADIUS:
		return
	if not sequencer.note_escaped():
		return
	_spawn_reinforcements()
	# The road's own forty were holding their posts through the whole opening, a
	# long run of wood away; the same leaving that brings the six out of the trees
	# puts them on the squad's heels.
	if host != null and host.get("trail") != null:
		host.trail.wake_road(actor)
	_set_status("The trees answer: six armed watchers come out of the dark.", 4.0)


# --- the prompt ------------------------------------------------------------

## Write the prompt through the one HUD (the world's, when embedded).
func _write_prompt(prompt: String, hint: String) -> void:
	if hud == null:
		return
	if prompt != _prompt_text:
		_prompt_text = prompt
		hud.set_prompt(prompt)
	if hint != _hint_text:
		_hint_text = hint
		hud.set_hint(hint)


func _set_status(text: String, seconds: float = 2.5) -> void:
	if hud != null:
		hud.set_status(text, seconds)


# --- standing alone --------------------------------------------------------

## The preview's night: the trail's own, so the camp is lit exactly as it is
## inside the world.
func _build_night() -> void:
	preload("res://scripts/world/environment_kit.gd").build(self, RunForestScript.night_style())


## The preview's floor: under the pocket and far enough into the wood for every
## tree the clearing plants to stand on something, out to the road's first waypoint.
func _build_floor() -> void:
	var mat: Material = preload("res://scripts/world/texture_library.gd").ground_material(
		RunForestScript.night_style())
	var front := YARD_FRONT - CAMP_TO_ROAD_METRES - 40.0
	var back := YARD_BACK + ClearingScript.WOOD_DEPTH + 40.0
	var half := YARD_HALF_WIDTH + ClearingScript.WOOD_DEPTH + 40.0
	var centre := Vector3(0.0, -0.3, (front + back) * 0.5)
	var size := Vector3(half * 2.0, 0.6, back - front)
	var floor_body := StaticBody3D.new()
	floor_body.name = "CampFloor"
	floor_body.position = centre
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	add_child(floor_body)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	floor_body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	floor_body.add_child(shape)
