extends Node3D
## GHOST OF THE WARBAND: the camp in the deep wood, and the first five minutes.
##
## The camp is the first quarter of one continuous world: five cages scattered
## through a ragged pocket cut into the drowned wood, two watchers between the
## squad and the way out - and, a long run of ordinary trees past the gap in the
## wood, the trail that leads to town. There is no arch and no door here any more.
## The way out is a walk, and the road is not in sight of it.
##
## The node has two ways to live:
##
##   * **embedded** - `world_scene.gd` sets `host` before the node enters the
##     tree and calls `embed()` after it. The world owns the one
##     `PossessionController`, camera, `WarbandHud`, panels, tips, loot vacuum,
##     revive channel and squad AI; this node brings its camp, its watchers and
##     its opening, and writes nothing on the tree but props.
##   * **alone** - `scenes/cage_escape.tscn` builds the camp with no bodies and
##     no HUD. It is the area preview the art regression loads, because the camp
##     is otherwise only visible as a quarter of the world.
##
## What the camp owns: the five cages and their latches, the clamp that keeps a
## caged body in its cage, the shiv lying in the dirt and the two watchers the
## player puts down with it, the four armed watchers that answer the squad
## leaving, the sequencer's beats, the first fight's own lesson
## (`duel_lesson.gd`) and the one-line tips that name each key. What it never
## owns in the world: the bodies, the camera, the HUD prompt, the revive channel
## or the loot vacuum.
##
## The opening is played, not read. The player wakes inside the first of the five:
##
##   1. cut the latch on its own cage with `G` - bare hands, a nail, a padlock;
##   2. step out and get its bearings: the camp, the fire, the cages in the trees;
##   3. the objective arrives - free the rest of the warband - over a gold arrow
##      on the camp's only blade and a pair of watchers to use it on, each key
##      named at the moment it is needed;
##   4. five bodies on their feet, and the objective turns over: run to the town;
##   5. the gap in the trees is the leaving, and the wood answers it.
##
## Nothing opens on its own, and nothing is explained in a paragraph. Past the
## mouth is trees for `CAMP_TO_ROAD_METRES` before the trail's first torch.
##
## The geometry is `camp_clearing.gd` (wood, ragged stakes, cages, huts, fire) and
## the dressing is `camp_dressing.gd` (padlocks, banners, gibbets, braziers,
## litter). The layout constants below are the camp's contract: the dressing
## mirrors the pocket, the art regression reads the spawns, the world reads the
## mouth and the distance to the road.

## The warband, five of them, held in the wood. The player wakes inside the first.
const PRISONER_NAMES := ["Ash", "Bram", "Het", "Wren"]
const LEADER_NAME := "Corvin"
const SQUAD_SIZE := 5
const CAGE_COUNT := 5
## The cage the campaign opens in: the first of the five the player can wear.
const OWN_CAGE := 0

## Cage centres, scattered through the pocket rather than in a line: the squad is
## held across the camp, so the first quest is a walk around it. y is the height a
## body spawns at. Every cage faces the mouth (local -Z), so each is approached
## from the front, and every one is clear of the fire, the huts, the altar and
## both watchers.
const CAGE_POSTS := [
	Vector3(0.0, 0.2, 6.0),        # the player's own cage, centre of the camp
	Vector3(-10.0, 0.2, 12.0),     # behind the fire, against the lean-to
	Vector3(9.5, 0.2, 13.4),       # the far right of the pocket
	Vector3(-17.0, 0.2, -18.5),    # deep left, down by the collapsed den
	Vector3(12.0, 0.2, -9.5),      # right, between the cages and the watchers
]
## The dressings a campaign starts with, lying on the altar's dirt where a player
## walking to the shiv will see them: five, so the first fight can be answered with
## `6` five times. They are the player's - picked up with `K` into the shared stash
## - and the squad's own medicine never draws on that stash.
const STARTING_BANDAGES := 5
const BANDAGE_ITEM := "bandage_linen"
## Five spots at the cold altar (`ColdAltar` stands at (0, 0, 12.5)): three along
## the slab's lip and two on the dirt in front, spread far enough apart that five
## separate pieces read as five.
const START_BANDAGE_POSTS := [
	Vector3(-1.1, 1.14, 12.5), Vector3(0.0, 1.14, 12.5), Vector3(1.1, 1.14, 12.5),
	Vector3(-0.6, 0.15, 11.2), Vector3(0.6, 0.15, 11.2),
]
## How far the freed body has to step from its own cage to have got its bearings:
## out of the bars and a pace further, so the beat is a step and not a timer.
const BEARINGS_RADIUS := 4.2
## The walk the opening is played on, kept clear of every tree: out of the player's
## cage, back to the altar for the blade, then each cage in turn, then down the
## pocket to the gap in the trees.
const WALK_ROUTE := [
	Vector3(0.0, 0.0, 6.0), Vector3(-2.15, 0.0, 11.0), Vector3(-10.0, 0.0, 12.0),
	Vector3(0.0, 0.0, 10.0), Vector3(9.5, 0.0, 13.4), Vector3(0.0, 0.0, 2.0),
	Vector3(-17.0, 0.0, -18.5), Vector3(12.0, 0.0, -9.5), Vector3(0.0, 0.0, -12.0),
	Vector3(0.0, 0.0, -22.0), Vector3(0.0, 0.0, -29.0),
]
## Corvin's shiv, on the dirt at the foot of the cold altar - the stone he jogs
## past on his way to the cages, and the one lit place at the back of the camp. The
## pair threw it there, so the first weapon the player ever holds is a thing on the
## ground a few paces behind where his body lands, picked up with `K`, and marked
## by `lesson_arrow.gd` until it is taken.
##
## It sits inside the altar's ring of skull-topped sticks (radius 3.05 m) and clear
## of the four cold candles (1.9 m) and the bone heap beside the steps, so the
## gold arrow has dark dirt under it rather than stone.
const LESSON_SHIV := "dagger_ironwood"
const SHIV_POST := Vector3(-2.15, 0.15, 11.0)
## How close the body has to come to the shiv before the tip that asks for `K` is
## offered. It matches the world's own loot reach (`world_scene.LOOT_REACH`), so
## the tip arrives on exactly the frames `K` works: a new player presses it and
## never meets a "too far away" line in between.
const SHIV_CARD_RADIUS := 2.6
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
## How far a caged body may stray from its own cage centre. The clamp, not the
## bars alone, is what holds a body in: legs that walk against the metal are
## snapped back on the frame they leave it.
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
## the camp's own mooks and the player's first fight. They stand between the cages
## and the mouth, sleep until a body is holding the shiv, and then come at that
## body.
##
## They are the softest thing in the game on purpose, because everything about the
## first fight is being taught while it happens:
##
##   * `PAIR_LESSON_HEALTH` 21 is two stabs of the ironwood shiv (10 a hit);
##   * `PAIR_BLOW_SCALE` 0.5 halves what they land, so a body can be hit twice and
##     keep fighting;
##   * `PAIR_WINDUP_SCALE` 2.4 stretches the 0.55 s windup to 1.3 s: that long
##     raised club is the window the guard tip is written for, and a windup the
##     wood actually uses cannot be answered by somebody who has just read about it;
##   * `PAIR_SWING_GAP_SCALE` 2.2 waits 3.3 s between swings;
##   * `PAIR_GUARD_SCALE` 0 never braces, so the player's cuts always land and a
##     new player is never looking at a watcher with its guard up.
##
## The four that come out of the wood afterwards keep the hardened pool, their
## own guard and their full blows.
const PAIR_LESSON_HEALTH := 21.0
const PAIR_BLOW_SCALE := 0.5
const PAIR_WINDUP_SCALE := 2.4
const PAIR_SWING_GAP_SCALE := 2.2
const PAIR_GUARD_SCALE := 0.0
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
##   * `AMBUSH_HEALTH` 42, so four ironwood stabs - half again what a camp watcher
##     had before the 30% cut - put one down;
##   * `AMBUSH_BLOW_SCALE` 0.5, so a club lands 3, a shiv 5 and a branch 7;
##   * `AMBUSH_GUARD_SCALE` 0.45 and `AMBUSH_SWING_GAP_SCALE` 1.9, so they swing
##     late and rarely turtle - an ambusher that trades blows is a fight, one that
##     guards every exchange is a wall.
##
## Everything they carry is the makeshift tier: there is no forged steel anywhere
## in this wood.
const AMBUSH_COUNT := 4
const AMBUSH_HEALTH := 42.0
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
	["dagger_ironwood", Vector3(1.4, 0.15, -27.0)],
	["branch_heavy", Vector3(-4.6, 0.15, -16.5)],
]
## The opening's whole script: one key line and one command, offered once, from
## the beat that has the question. A tip never opens a page and never pauses the
## game. These ids are what the world's `WarbandTips` dedupes on.
const TIP_CAGE := "opening_cage"
const TIP_WALK := "opening_walk"
const TIP_BLADE := "opening_blade"
const TIP_SWING := "opening_swing"
const TIP_GUARD := "opening_guard"
const TIP_LATCH := "opening_latch"
const TIP_BODIES := "opening_bodies"
const TIP_RUN := "opening_run"
const OPENING_TIPS := {
	TIP_CAGE: {"keys": "G", "text": "PICK THE LATCH"},
	TIP_WALK: {"keys": "W A S D", "text": "WALK · THE MOUSE LOOKS"},
	TIP_BLADE: {"keys": "K", "text": "TAKE THE IRONWOOD SHIV"},
	TIP_SWING: {"keys": "LMB", "text": "CUT · THE WHEEL STABS AND CHOPS"},
	TIP_GUARD: {"keys": "HOLD RMB", "text": "GUARD · LET GO TO SWING"},
	TIP_LATCH: {"keys": "G", "text": "CUT EVERY LATCH"},
	TIP_BODIES: {"keys": "F1 [ ]", "text": "STEP INTO A SQUADMATE"},
	TIP_RUN: {"keys": "W A S D", "text": "RUN TO THE TOWN"},
}

## The word over the latch arrow, and the one over the arrow at the gap in the
## trees once the squad is out. A marker with a word is a place a body can walk
## to; the camp has no signposts and no road in sight.
const LATCH_MARKER_LABEL := "PRESS G"
const RUN_MARKER_LABEL := "RUN TO TOWN"

const SequencerScript = preload("res://scripts/warband/tutorial_sequencer.gd")
const DuelScript = preload("res://scripts/warband/duel_lesson.gd")
const CombatScript = preload("res://scripts/combat.gd")
const SfxScript = preload("res://scripts/audio/sfx.gd")
const ArrowScript = preload("res://scripts/warband/lesson_arrow.gd")
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
## The first fight's lesson: the blade, the cuts, the guard. Started when the
## freed body gets its bearings.
var duel
var hud
var screen
var paperdoll
## The one hint channel: a key and a command under the crosshair, never a page.
var tips
var loot
## The one squad module, owned by the world: a freed prisoner is driven by the
## same behaviour that escorts the soul down the trail.
var squad
var bodies: Array = []
## The camp's own watchers. `host.guards` is the world's single hostile list, so
## a watcher here is in both.
var guards: Array = []
var squad_ids: Array[int] = []
var caged_ids: Array[int] = []
var clearing: Dictionary = {}

var _cage_anchors: Dictionary = {}   # merc_id -> the cage centre it is held in
var _cage_doors: Array = []          # [{node, lift}, ...]
var _pickups: Array = []
## The one drop the lesson owns: `LESSON_SHIV` on the dirt at `SHIV_POST`. Taking
## it is what arms the player and what wakes the pair.
var _shiv_pickup
## The bouncing arrow over that drop, shown while the lesson wants it walked to
## and taken.
var _shiv_marker
## The arrow over the nearest cage that is still shut, labelled `PRESS G`: the
## cages are scattered through the camp, and a body that just finished a fight
## has no reason to go looking for four padlocks in the trees. Shown once the
## blade is in hand, until the last latch goes.
var _latch_marker
## The arrow over the gap in the trees once the squad is free, labelled `RUN TO
## TOWN`. It is hidden again the moment the mouth is crossed, where the trail
## (and the world's own metres-to-town line) takes over.
var _run_marker
var _cage_open: Array[bool] = []     # per cage, in CAGE_POSTS order
var _watchers_awake := false
## The watcher whose windup raised the guard tip: the body it is taught on.
var _guard_teacher: WeakRef = null
var _steel_taken := 0
var _lesson := false
## True when the world opens on a checkpoint past this camp: the cages stand
## empty and open, the pair never wake, and no opening runs. Set before the camp
## enters the tree, because `_ready` and `embed` are where the watchers and the
## choice of opening would otherwise happen.
var _resume := false


func _ready() -> void:
	warband = host.warband if host != null else get_node_or_null("/root/Warband")
	if warband == null:
		push_error("CageEscape needs the Warband autoload")
		return
	if host == null:
		_build_night()
		_build_floor()
	_build_clearing()
	if host == null and not _resume:
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
	tips = world.tips
	squad = world.squad
	_pickups = world.pickups
	if not _resume:
		_install_watchers()


# --- the world's side of the camp ------------------------------------------

## Where the warband stands when the campaign starts in the camp: the five cages,
## the player in the first of them.
func spawn_posts() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for post in CAGE_POSTS:
		points.append(post)
	return points


## Dress an empty warband as the prison squad - five in rags, none of them armed -
## and mark it as the line this camp fields. A warband that already has bodies
## keeps them; a thin one is topped up with prisoners rather than bending the
## opening around it.
##
## Nobody carries a weapon on a new campaign: the camp's only blade is
## `LESSON_SHIV` on the dirt, and taking it with `K` is the beat that arms the
## player and wakes the pair.
func seed_warband() -> void:
	var living: Array = warband.alive_merc_ids()
	var fresh := living.is_empty()
	if fresh:
		for prisoner in PRISONER_NAMES:
			var merc_id: int = warband.add_mercenary(str(prisoner))
			_dress_rags(merc_id)
			warband.roster.unequip(merc_id, "main")
			warband.roster.unequip(merc_id, "off")
		var leader: int = warband.add_mercenary(LEADER_NAME)
		_dress_rags(leader)
		living = warband.alive_merc_ids()
	else:
		while living.size() < SQUAD_SIZE:
			var extra: int = warband.add_mercenary("Wretch %d" % (living.size() + 1))
			_dress_rags(extra)
			living.append(extra)
	squad_ids.clear()
	for index in SQUAD_SIZE:
		squad_ids.append(int(living[index]))
	if fresh:
		for merc_id in squad_ids:
			warband.roster.unequip(merc_id, "main")
			warband.roster.unequip(merc_id, "off")
	caged_ids.clear()
	for index in CAGE_COUNT:
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
## and hold all five caged ones in. The camp's own drops go on the floor here.
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
	# The camp arms its own squad: three makeshift pieces on the dirt, so the four
	# other prisoners give themselves a blade the moment their latch is cut.
	for drop in WEAPON_DROPS:
		_spawn_pickup(str(drop[0]), drop[1])
	# And the dressings a campaign opens with, at the altar: exactly `STARTING_BANDAGES`
	# pieces, so a player who walks straight to the blade finds five bandages under
	# it and can answer the first fight with `6`.
	for post in START_BANDAGE_POSTS:
		_spawn_pickup(BANDAGE_ITEM, post)
	# And the shiv itself, lying where the pair threw it: the first weapon in the
	# game and the beat the opening is built around. It gets a big gold arrow
	# hanging over it - a body in a cage cannot see a dagger in the dirt, and "walk
	# to your shiv" is a place, not a sentence.
	_shiv_pickup = _spawn_pickup(LESSON_SHIV, SHIV_POST)
	_shiv_marker = _spawn_marker("ShivMarker", "")
	# The latch arrow and the way out: both are parked until the beat that owns
	# them, because a marker with nothing to say is noise over a dark camp.
	_latch_marker = _spawn_marker("LatchMarker", LATCH_MARKER_LABEL)
	_run_marker = _spawn_marker("RunMarker", RUN_MARKER_LABEL)


## One gold arrow, hidden until its beat wants it. `word` is the label over the
## arrow ("" for none: the shiv already floats its own name).
func _spawn_marker(marker_name: String, word: String):
	var marker = ArrowScript.new()
	marker.name = marker_name
	add_child(marker)
	if not word.is_empty():
		marker.set_label(word)
	marker.visible = false
	return marker


## Start the opening: the sequencer, the first fight's own lesson and the tip that
## names the first key. Only the camp the campaign *starts* in does this. A camp
## the warband walks back to later keeps its cages, its guards and nothing else.
func begin_lesson() -> void:
	if _lesson or caged_ids.is_empty():
		return
	_lesson = true
	sequencer = SequencerScript.new()
	sequencer.name = "Tutorial"
	add_child(sequencer)
	sequencer.state_changed.connect(_on_state_changed)
	duel = DuelScript.new()
	duel.name = "Duel"
	add_child(duel)
	duel.tip_wanted.connect(_on_duel_tip)
	duel.step_changed.connect(_on_duel_step)
	# The soul wakes in the first of the five. It is not a body swap the player
	# has to find: the game opens inside a prisoner.
	controller.direct(1, caged_ids[OWN_CAGE])
	sequencer.begin()
	_play_tip(TIP_CAGE)


## True while the opening is running, i.e. while the cages hold the squad.
func lesson_running() -> bool:
	return _lesson and sequencer != null


## True once the leaving has happened: the camp is behind the squad and the wood
## is on its heels. A camp opened on a checkpoint has no sequencer and answers
## false, because nothing about that save is escaping.
func escaping() -> bool:
	return sequencer != null and sequencer.state() == SequencerScript.State.ESCAPING


## Throw the opening away. A guest in a co-op campaign walks into this camp, but
## the cages are the host's and the opening is a solo beat: a clamped body would
## refuse the host's snapshots, and the guest should not be taught somebody else's
## first minute. The camp is left exactly as it looks after the squad has left it
## - every cage open, nobody held - and with no sequencer `is_free()` answers true
## for everybody.
func dismiss_lesson() -> void:
	_lesson = false
	if sequencer != null:
		sequencer.queue_free()
		sequencer = null
	if duel != null:
		duel.queue_free()
		duel = null
	for marker in [_shiv_marker, _latch_marker, _run_marker]:
		if marker != null and is_instance_valid(marker):
			marker.visible = false
	caged_ids.clear()
	_cage_anchors.clear()
	_cage_open.clear()
	for index in CAGE_POSTS.size():
		_cage_open.append(true)
	for entry in _cage_doors:
		entry["lift"] = CAGE_BAR_LIFT
		var node: Node3D = entry["node"]
		if is_instance_valid(node):
			node.position.y = CAGE_BAR_LIFT


## The world is opening on a checkpoint past this camp. Called before the camp is
## added to the tree: the wood still builds - it is the same place - but the pair
## are never fielded and no lesson starts.
func prepare_resume() -> void:
	_resume = true


## Stand the warband in a camp it has already left: the four cages hang open and
## empty, nobody is clamped, and the squad is free to follow. There are no
## watchers because the checkpoint was only written after they fell.
func place_resumed(bodies_in: Array) -> void:
	bodies = bodies_in
	for actor in bodies:
		if not is_instance_valid(actor):
			continue
		var merc_id: int = controller.merc_of(actor)
		actor.combat.target_mask = WATCHER_LAYER
		controller.set_bot(merc_id, false)
	caged_ids.clear()
	_cage_anchors.clear()
	_cage_open.clear()
	for index in CAGE_POSTS.size():
		_cage_open.append(true)
	for entry in _cage_doors:
		entry["lift"] = CAGE_BAR_LIFT
		var node: Node3D = entry["node"]
		if is_instance_valid(node):
			node.position.y = CAGE_BAR_LIFT


## The opening is behind the warband: the leaving happened and the six watchers
## it called out of the wood are dead. That - not a timer - is the moment the
## trail begins and the first checkpoint is worth writing. A world that opened on
## a bookmark past the cages never ran the opening, so it has nothing to clear.
func tutorial_cleared() -> bool:
	if sequencer == null:
		return false
	return sequencer.state() == SequencerScript.State.ESCAPING \
		and sequencer.guards_down() >= SequencerScript.GUARD_COUNT


## Whether this mercenary is free to act as a squadmate: a body whose latch has
## been cut, or anybody who was never in a cage. The four still shut in the wood
## are held by the clamp, not by a script - `SquadDrive` simply has nobody free to
## move until their cage opens.
func is_free(merc_id: int) -> bool:
	if merc_id <= 0:
		return false
	if not lesson_running():
		return not is_cage_clamped(merc_id)
	return not is_cage_clamped(merc_id)


## The opening's prompt line, or "" when the camp has nothing to say about where
## the body stands. The world writes it to the one HUD. The first fight's lesson
## outranks the sequencer: while it is teaching - walk, take the blade, swing,
## guard - the line has to be about that. The warband count rides along with it,
## because the quest is what the whole opening is for and one line can carry two
## short facts.
func prompt_line(actor) -> String:
	if not lesson_running() or actor == null or not is_instance_valid(actor):
		return ""
	if duel != null and duel.active():
		var command: String = duel.objective()
		if sequencer.state() == SequencerScript.State.FREEING:
			return "%s   ·   warband %d/%d" % [command, sequencer.cages_opened(),
				SequencerScript.CAGE_COUNT]
		return command
	if sequencer.state() == SequencerScript.State.ESCAPING:
		# The opening is over: the world's own line - the trail and the metres to
		# the town - is what a body needs then, not a stale instruction.
		return ""
	return sequencer.objective()


## The opening's key line, or "" when the body is not the camp's business.
func hint_line(actor) -> String:
	if not lesson_running() or actor == null or not is_instance_valid(actor):
		return ""
	if duel != null and duel.active():
		return duel.hint()
	if not _in_camp(actor) and sequencer.state() != SequencerScript.State.ESCAPING:
		return ""
	return sequencer.hint()


## How many latches have been cut, 0..5, the player's own cage included. One per
## cage, in any order, and the fifth is what looses the squad: this is a progress
## count, not an all-or-nothing answer.
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


func pickups() -> Array:
	return _pickups


## A pickup left the floor (a squadmate's or the player's). Counted silently: the
## escape never asks the player to loot anything - but the shiv the lesson put on
## the dirt is the exception, because taking it is what arms the player and wakes
## the pair.
func note_pickup(pickup = null) -> void:
	_steel_taken += 1
	if sequencer != null:
		sequencer.note_weapon_looted()
	if duel != null and pickup != null and is_instance_valid(pickup) \
			and pickup == _shiv_pickup:
		if duel.note_shiv_taken():
			_set_status("The ironwood shiv is in your hand. The pair are awake.", 4.0)
	if screen != null:
		screen.refresh()


# --- running ---------------------------------------------------------------

func _process(delta: float) -> void:
	_advance_cage_doors(delta)
	_update_shiv_marker()
	_update_latch_marker()
	_update_run_marker()
	_maybe_bearings()


func _physics_process(_delta: float) -> void:
	if not lesson_running() or controller == null:
		return
	_maintain_watchers()
	_duel_tick()
	_clamp_caged_bodies()
	_check_escape()


# --- the camp --------------------------------------------------------------

## Build the camp's own bones: the ragged pocket in the deep wood, the five cages,
## the huts and the fire, and then the dressing that reads it. Everything that may
## not be planted over - the cages, the altar, the huts, the fire, the torches, the
## dressing's own posts, and the walk from cage to cage out to the gap in the trees
## - is handed to the geometry as `keep_clear`, because the wood is planted *inside*
## the pocket as well as around it.
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
	for watcher in GATE_WATCHERS:
		keep_clear.append({"point": watcher["post"], "radius": 2.0})
	# The walk the opening is played on: the player's own cage, the altar the blade
	# lies at, each scattered cage in turn, then down the pocket to the gap in the
	# trees. The wood closes in around it but never on it.
	for point in WALK_ROUTE:
		keep_clear.append({"point": point, "radius": 4.2})
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
## the body inside is out of the opening.
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


## While a cage holds, its body is snapped back inside it. Possession moves the
## soul, not the cage: this is the only thing that keeps five staggered bodies
## held until their own padlock goes.
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
	return CAGE_POSTS[OWN_CAGE]


func _in_camp(actor) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var at: Vector3 = actor.global_position
	return absf(at.x) <= YARD_HALF_WIDTH + 6.0 and at.z >= YARD_FRONT - 10.0 \
		and at.z <= YARD_BACK + 6.0


## Spawn a piece of cultist steel into the world's one loot vacuum.
func _spawn_pickup(item_id: String, at: Vector3):
	if item_id.is_empty():
		return null
	if host != null:
		return host.spawn_pickup(item_id, at)
	return null


# --- the watchers ----------------------------------------------------------

## Turn a watcher loose on the wood: a mob standing on the town's ring is still
## inside a body's safe ground, so a watcher that kept the default centre would
## stand its post while a blade came at it. Until this is called - the pair before
## the lesson, anything nobody has woken - the camp is quiet ground and the mob
## engages nobody. `escape_run` points its road watchers at the same gate.
func _loose_watcher(watcher) -> void:
	watcher.safe_center = _safe_center()


## The town's own ring, which is the only one this camp is near.
func _safe_center() -> Vector3:
	if host != null and host.has_method("lane_end"):
		return host.lane_end()
	return Vector3(0.0, 0.0, -100000.0)


## The two watchers between the cages and the mouth: real wilderness mobs with a
## camp profile (`cage_watcher.gd`), so they read as the wood's own creatures and
## die in a few stabs. They only turn to hunt once the first latch goes.
func _install_watchers() -> void:
	for index in GATE_WATCHERS.size():
		var spec: Dictionary = GATE_WATCHERS[index]
		# The pair are the lesson's mooks: three shiv stabs each, half blows, a
		# long telegraph before each swing, and no guard to break through.
		var watcher := _add_watcher(spec["post"],
			"CampWatcher%d" % (guards.size() + 1), "", PAIR_LESSON_HEALTH)
		watcher.blow_scale = PAIR_BLOW_SCALE
		watcher.windup_scale = PAIR_WINDUP_SCALE
		watcher.swing_gap_scale = PAIR_SWING_GAP_SCALE
		watcher.guard_scale = PAIR_GUARD_SCALE


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


## The pair wake the moment a body is holding the shiv, and not one frame before:
## the opening walks the player to the weapon first, and two watchers coming at an
## empty-handed body would be the opposite of a help. They take the body the soul
## is actually in - the one that took their quarry's blade - as the quarry, which
## is also what keeps them off the caged prisoners.
func _maintain_watchers() -> void:
	if guards.is_empty() or _watchers_awake:
		return
	if duel == null or not duel.fighting():
		return
	_watchers_awake = true
	var prey = controller.active_body(1) if controller != null else null
	for watcher in guards:
		if not is_instance_valid(watcher) or not bool(watcher.get("alive")):
			continue
		_loose_watcher(watcher)
		watcher.mob_wake()
		if prey != null and is_instance_valid(prey):
			watcher.hunt(prey)


func _on_watcher_defeated(enemy, _reward: int) -> void:
	if sequencer != null:
		sequencer.note_guard_killed()
	if duel != null and watchers_down() >= GATE_WATCHERS.size():
		duel.note_fight_over()
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
		_loose_watcher(watcher)
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
## frontier's `_on_enemy_attack`. The guard's answer is what the first fight is
## waiting for: a blow that lands on a raised blade is the player's proof that the
## tip was worth pressing.
func _on_watcher_attack(attacker, amount: float, victim) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(victim):
		return
	# The blow already carries the body's own `blow_scale` - the pair lands half a
	# swing, the ambush lands half a swing, a hardened body lands all of it - so
	# the scene weighs nobody a second time here.
	var outcome := -1
	if victim.has_method("receive_melee"):
		outcome = int(victim.receive_melee(amount, WATCHER_SOURCE,
			attacker.global_position))
	elif victim.has_method("take_damage"):
		victim.take_damage(amount, WATCHER_SOURCE)
	# The sound belongs to the blow, not to the lesson: a watcher's club that
	# lands crunches (Sfx reads the piece in its hand), and one that meets a
	# raised blade rings instead.
	if outcome == CombatScript.DEFENSE_NONE:
		SfxScript.landed(attacker, victim.global_position + Vector3.UP)
	elif outcome > CombatScript.DEFENSE_NONE:
		# The defender is what decides the metal: a wooden shield is a thud, a
		# shiv is a thin clang, a raised blade rings.
		SfxScript.defense(attacker.global_position,
			outcome == CombatScript.DEFENSE_PARRY, victim)
	if outcome >= 0 and controller != null and victim == controller.active_body(1) \
			and duel != null and duel.fighting():
		if outcome == CombatScript.DEFENSE_BLOCK or outcome == CombatScript.DEFENSE_WEAK_BLOCK:
			if duel.note_guarded():
				_set_status("Your guard holds. The pair are yours to finish.", 3.0)
			else:
				_set_status("Blocked - a shiv softens a blow, it does not stop one.", 2.5)
		elif outcome == CombatScript.DEFENSE_PARRY:
			_set_status("Parried - the blow slides off your blade.", 2.5)


# --- sequencer -------------------------------------------------------------

# --- the tips --------------------------------------------------------------

## One opening tip, once. `OPENING_TIPS` holds the copy: a key line and a command,
## never a page.
func _play_tip(id: String) -> bool:
	if tips == null or not OPENING_TIPS.has(id):
		return false
	var content: Dictionary = OPENING_TIPS[id]
	return bool(tips.tip(id, str(content["keys"]), str(content["text"])))


## The first fight asked for a hint: name the key it is asking about.
func _on_duel_tip(slot: int) -> void:
	match slot:
		DuelScript.Tip.MOVE:
			_play_tip(TIP_WALK)
		DuelScript.Tip.FETCH:
			_play_tip(TIP_BLADE)
		DuelScript.Tip.SWING:
			_play_tip(TIP_SWING)
		DuelScript.Tip.GUARD:
			_play_tip(TIP_GUARD)


func _on_state_changed(state: int, _objective: String) -> void:
	# The markers are a frame behind otherwise: a state can change inside a physics
	# tick, and the arrow the beat just asked for has to be standing before the
	# player walks at it.
	_update_latch_marker()
	_update_run_marker()
	match state:
		SequencerScript.State.LOOSE:
			# Out of the bars: the next thing to learn is walking.
			_play_tip(TIP_WALK)
		SequencerScript.State.FREEING:
			# The objective - free the warband - arrives with the camp's own
			# lesson: walk to the blade under the gold arrow. The tip names the
			# key, the prompt names the job, and the pair stay asleep until the
			# blade is in hand.
			#
			# From this frame on every cage the player opens is an escort: an ally
			# that followed only after the leaving used to stand in the camp and
			# wander its own post while the soul walked off, which is the report
			# "the band splits up". `is_free` still holds the cages shut, so the
			# four still caged do nothing until their own latch goes.
			if squad != null:
				squad.following = true
				squad.engage_radius = 34.0
			_begin_duel()
		SequencerScript.State.WARBAND:
			# Five bodies on their feet and the objective turns over: the way on
			# is the town, down the trail, on foot. The squad keeps following -
			# the last latch is not a reason to leave anybody standing in the
			# wood.
			_play_tip(TIP_RUN)
			_update_run_marker()
		SequencerScript.State.ESCAPING:
			# The squad stops holding the camp and runs the wood with the soul:
			# the same module, one escort clause.
			if squad != null:
				squad.following = true
				squad.engage_radius = 34.0
			if screen != null:
				screen.refresh()


## A possession happened. The world owns the controller so it calls this even when
## the opening is not running; here it is worth one tip: the first time the soul
## steps into a body that is already out of its cage, name the other bodies.
func note_possession(merc_id: int) -> void:
	if sequencer == null or merc_id <= 0:
		return
	if caged_ids.has(merc_id) and not is_cage_clamped(merc_id):
		_play_tip(TIP_BODIES)


# --- the first fight's lesson ----------------------------------------------

## The shiv's arrow lives exactly as long as the errand does: from the moment the
## lesson starts asking for a walk to the moment the drop leaves the dirt. It is
## polled rather than pushed, so a pickup taken by anybody - the player, a
## squadmate, a sweep - takes the arrow with it.
func _update_shiv_marker() -> void:
	if _shiv_marker == null or not is_instance_valid(_shiv_marker):
		return
	var live: bool = _shiv_pickup != null and is_instance_valid(_shiv_pickup) \
		and not bool(_shiv_pickup.get("collected"))
	var wanted: bool = live and duel != null \
		and (duel.step() == DuelScript.Step.MOVE or duel.step() == DuelScript.Step.FETCH)
	if wanted != _shiv_marker.visible:
		_shiv_marker.visible = wanted
	if wanted:
		_shiv_marker.anchor_at((_shiv_pickup as Node3D).global_position)


## The nearest cage whose latch is still on, to a body, or -1 when the squad is
## out (or the camp has no cages to speak of). The cages are scattered through the
## camp, so the arrow is never "the first one on the list" - it is the one a body
## would walk to next.
func _nearest_closed_cage(actor = null) -> int:
	var at: Vector3 = (actor as Node3D).global_position if actor != null \
		and is_instance_valid(actor) else CAGE_POSTS[OWN_CAGE]
	var best := -1
	var best_gap := INF
	for index in CAGE_POSTS.size():
		if index < _cage_open.size() and bool(_cage_open[index]):
			continue
		var post: Vector3 = CAGE_POSTS[index]
		var gap := Vector2(at.x - post.x, at.z - post.z).length()
		if gap < best_gap:
			best_gap = gap
			best = index
	return best


## The latch arrow: out of the cage, armed, and the cages are the errand. Anchored
## at the nearest shut cage's own bars, on the side the approach walks from, so the
## arrow hangs over the latch the player is about to reach for.
func _update_latch_marker() -> void:
	if _latch_marker == null or not is_instance_valid(_latch_marker):
		return
	var walker = controller.active_body(1) if controller != null else null
	var index := _nearest_closed_cage(walker)
	var armed: bool = duel != null and is_instance_valid(duel) and duel.armed()
	var wanted := index >= 0 and armed
	if wanted != _latch_marker.visible:
		_latch_marker.visible = wanted
	if wanted:
		var post: Vector3 = CAGE_POSTS[index]
		_latch_marker.anchor_at(post + Vector3(0.0, 0.0, CAGE_HALF))


## The way out: five bodies on their feet, the gold arrow stands in the gap in the
## trees, and it comes down the moment the mouth is crossed (the trail's own line
## takes over beyond it) or the wood answers the leaving.
func _update_run_marker() -> void:
	if _run_marker == null or not is_instance_valid(_run_marker):
		return
	var freed: bool = sequencer != null \
		and sequencer.state() == SequencerScript.State.WARBAND
	var wanted := freed and not _mouth_crossed()
	if wanted != _run_marker.visible:
		_run_marker.visible = wanted
	if wanted:
		_run_marker.anchor_at(GATE_POINT)


## Whether the soul's body is at or past the gap in the trees. The arrow has done
## its job the moment a body is standing on the mouth: the trail, its torches and
## the HUD's metres take it from there.
func _mouth_crossed() -> bool:
	var actor = controller.active_body(1) if controller != null else null
	if actor == null or not is_instance_valid(actor):
		return false
	return (actor as Node3D).global_position.z <= GATE_POINT.z + 1.0


## The bearings beat ends on a fact, not a timer: the freed body stepping away
## from its own cage. Polled, because nothing emits a signal for a walk.
func _maybe_bearings() -> void:
	if sequencer == null or sequencer.state() != SequencerScript.State.LOOSE:
		return
	var actor = controller.active_body(1) if controller != null else null
	if actor == null or not is_instance_valid(actor):
		return
	var anchor: Vector3 = CAGE_POSTS[OWN_CAGE]
	var flat := Vector2((actor as Node3D).global_position.x - anchor.x,
		(actor as Node3D).global_position.z - anchor.z)
	if flat.length() < BEARINGS_RADIUS:
		return
	sequencer.note_looked_around()


## The freed body gets its bearings: the opening moves on to the objective, and the
## first fight's lesson starts on the frame the walk does. A body that already
## holds a blade (a campaign that came back to the camp armed) skips the fetch -
## there is nothing on the dirt to teach it.
func _begin_duel() -> void:
	if duel == null:
		return
	duel.wake()
	if duel.step() != DuelScript.Step.MOVE:
		return
	var actor = controller.active_body(1) if controller != null else null
	if actor != null and is_instance_valid(actor) and holds_blade(actor):
		duel.note_shiv_taken()


## The duel's two polls, both things nobody emits a signal for: the body standing
## on the blade (the tip that says `K`) and a watcher's windup (the tip that says
## `RMB`).
func _duel_tick() -> void:
	if duel == null:
		return
	if duel.step() == DuelScript.Step.MOVE:
		var walker = controller.active_body(1) if controller != null else null
		if walker == null or not is_instance_valid(walker):
			return
		# The errand is "be armed", not "take that exact piece": a body that picked
		# up any blade on the way - the camp leaves three on the dirt - is as armed
		# as the lesson needs and the pair wake for it.
		if holds_blade(walker):
			if duel.note_shiv_taken():
				_set_status("A blade is in your hands. The pair are awake.", 4.0)
			return
		if _shiv_pickup == null or not is_instance_valid(_shiv_pickup) \
				or bool(_shiv_pickup.get("collected")):
			return
		var gap: float = walker.global_position.distance_to(_shiv_pickup.global_position)
		if gap <= SHIV_CARD_RADIUS:
			duel.note_shiv_near()
		return
	if duel.step() != DuelScript.Step.FIGHT:
		return
	var body = controller.active_body(1) if controller != null else null
	if body == null or not is_instance_valid(body) or not bool(body.get("alive")) \
			or bool(body.get("downed")):
		# The body the lesson is taught on is on the floor. Whatever happens next -
		# a revive, a body swap, the wipe - the hints have said what they can, and
		# the HUD goes back to the opening's line instead of nagging a body that
		# cannot read it.
		duel.note_fight_over()
		return
	var alive := 0
	var winding = null
	for watcher in guards:
		if not is_instance_valid(watcher) or not bool(watcher.get("alive")):
			continue
		alive += 1
		if winding == null and str(watcher.get("state")) == "WINDUP":
			winding = watcher
	if alive <= 0:
		duel.note_fight_over()
		return
	if winding != null and not duel.guard_tip():
		if duel.note_windup(winding.get_instance_id(), alive):
			# The tip is up and this is the one safe frame to put the teacher
			# inside its own strike reach, so the blow the player is told to guard
			# actually arrives.
			_guard_teacher = weakref(winding)
			_close_guard_teacher()


## Slide the watcher teaching the guard into its own strike reach, along the
## bearing it already holds. A warden chooses its swing from `reach + TRADE_REACH`
## (3.5 m) and does not walk the gap during the windup, while the blow only lands
## at `reach` (2.35 m, 2.49 m by the strike) - so the blow the player is told to
## answer would otherwise be a swing that falls short. Done on the frame the tip
## is raised, so nothing is seen moving.
func _close_guard_teacher() -> void:
	var body = controller.active_body(1) if controller != null else null
	if body == null or not is_instance_valid(body):
		return
	var teacher = _guard_teacher.get_ref() if _guard_teacher != null else null
	if teacher == null or not is_instance_valid(teacher):
		return
	if _strike_would_land(teacher, body):
		return
	var offset: Vector3 = (teacher as Node3D).global_position - (body as Node3D).global_position
	offset.y = 0.0
	if offset.length_squared() < 0.0001:
		return
	var profile = teacher.get("profile")
	if not (profile is Dictionary):
		return
	var reach := float((profile as Dictionary).get("reach", 0.0))
	if reach <= 0.0:
		return
	(teacher as Node3D).global_position = (body as Node3D).global_position \
		+ offset.normalized() * reach * 0.8


## Whether the blow a watcher is winding up would actually arrive from where it
## stands.
func _strike_would_land(watcher, body) -> bool:
	if watcher == null or not is_instance_valid(watcher):
		return false
	if body == null or not is_instance_valid(body):
		return false
	var profile = watcher.get("profile")
	if not (profile is Dictionary):
		return false
	var reach := float((profile as Dictionary).get("reach", 0.0))
	if reach <= 0.0:
		return false
	return watcher.global_position.distance_to(body.global_position) <= reach


## A duel beat changed. The HUD's prompt and key line are polled by the world
## every frame; this only has to keep the two arrows honest on the frame the beat
## turns over.
func _on_duel_step(_step: int) -> void:
	_update_shiv_marker()
	_update_latch_marker()
	_update_run_marker()


# --- the latches -----------------------------------------------------------

## The camp's share of the one `G`. True when the press was the camp's: a latch
## was cut, or the body is standing at a shut cage with nothing to cut it with and
## has been told so. False hands the press on to the town counters and the floor.
##
## The player's own cage is the exception to the blade: it is worked from inside,
## with whatever a prisoner has - a nail, a rib, the hasp bent against the post -
## and getting out of it is the first step of the game. Every other cage is a cut
## and needs steel.
func interact(actor) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var index := latch_target(actor)
	if index < 0:
		return false
	if not holds_blade(actor) and index != OWN_CAGE:
		_set_status("Nothing to cut the latch with.", 2.5)
		return true
	var opened := open_latch(index)
	if opened:
		# The lock, the chain and the tick of the padlock. It is played here, on
		# the player's press, and never inside `open_latch`: a resumed campaign
		# opens every cage in one call and must not sound like a locksmith.
		SfxScript.play("cage_latch", CAGE_POSTS[index] + Vector3.UP * 1.1)
	return opened


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


## One latch, cut: the door lifts, that body's clamp is gone and the sequencer
## books the cage. The fifth cut is what puts the warband on its feet. Returns
## false only when the cage is already open or does not exist - the press was not
## consumed.
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
		_set_status("The last latch falls. The warband is on its feet.", 4.0)
	elif cut >= 2:
		# The second cage is the first proof the soul can wear another body; the
		# quest bar is not the place to say so.
		_play_tip(TIP_BODIES)
	else:
		_set_status("Latch cut. %d of %d." % [cut, CAGE_POSTS.size()], 2.5)
	return true


## The ambush is the leaving. Once the warband is out, the soul's body reaching the
## gap in the trees is what calls the wood down: the state turns and the four walk
## out of it on the same frame.
func _check_escape() -> void:
	if sequencer == null or sequencer.state() != SequencerScript.State.WARBAND:
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
	# The road's own cultists were holding their posts through the whole opening, a
	# long run of wood away; the same leaving that brings the four out of the trees
	# puts them on the squad's heels.
	if host != null and host.get("trail") != null:
		host.trail.wake_road(actor)
	_set_status("The trees answer: four armed watchers come out of the dark.", 4.0)


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
