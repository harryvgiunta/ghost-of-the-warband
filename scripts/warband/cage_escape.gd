extends Node3D
## GHOST OF THE WARBAND: the camp clearing, and the lesson that starts in it.
##
## The camp is the first quarter of one continuous world: four cages in a
## clearing in the drowned wood, a fifth prisoner loose behind them, two watchers
## between the squad and the way out - and, past the clearing's mouth, the trail
## that leads to town. There is no arch and no door here any more. The way out is
## a walk.
##
## The node has two ways to live:
##
##   * **embedded** - `world_scene.gd` sets `host` before the node enters the
##     tree and calls `embed()` after it. The world owns the one
##     `PossessionController`, camera, `WarbandHud`, panels, tutorial card, loot
##     vacuum, revive channel and squad AI; this node brings its clearing, its
##     watchers and its lesson, and writes nothing on the tree but props.
##   * **alone** - `scenes/cage_escape.tscn` builds the clearing with no bodies
##     and no HUD. It is the area preview the art regression loads, because the
##     clearing is otherwise only visible as a quarter of the world.
##
## What the camp owns: the four cages and their latches, the clamp that keeps a
## caged soul in its cage, the rescuer's jog, the two watchers and the six armed
## reinforcements out of the trees, the sequencer's beats and the cards that
## explain them. What it never owns in the world: the bodies, the camera, the HUD
## prompt, the revive channel or the loot vacuum.
##
## The geometry is `camp_clearing.gd` (fence, wood, cages, fire) and the dressing
## is `camp_dressing.gd` (padlocks, banners, gibbets, braziers, litter). The
## layout constants below are the camp's contract: the dressing mirrors the yard,
## the art regression reads the spawns, the world reads the mouth.

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
## The clearing's mouth, where the fence stops and the trail starts. The old camp
## arch stood here and opened a scene; now the gap is simply the way out.
const GATE_POINT := Vector3(0.0, 0.0, -42.0)
const GATE_RADIUS := 3.5
const MOUTH_HALF_WIDTH := 7.0
## The clearing: the yard's own bounds (the dressing mirrors them), 60 x 68 m of
## open ground inside the fence line with the treeline just past it.
const YARD_HALF_WIDTH := 30.0
const YARD_FRONT := -42.0
const YARD_BACK := 26.0
## Where the rescuer's jog ends: just in front of the cage line.
const JOG_TARGET := Vector3(0.0, 0.0, 8.6)
const JOG_STOP := 1.6
## How far a caged body may stray from its own cage centre.
const CAGE_CLAMP_RADIUS := 0.95
## How far the cage doors rise when the latches go.
const CAGE_BAR_LIFT := 2.6
const BAR_LIFT_SPEED := 2.2
## The camp's torches: at the cages, at the mouth, and round the clearing's rim so
## 60 x 68 m of ground is a lit clearing in the wood rather than a black field.
const CAMP_TORCHES := [
	[Vector3(-10.5, 0, 4.2), 0.9], [Vector3(10.5, 0, 4.2), 0.9],
	[Vector3(-5.0, 0, -38.5), 1.0], [Vector3(5.0, 0, -38.5), 1.0],
	[Vector3(0, 0, -12.0), 0.75], [Vector3(-14.0, 0, -30.0), 0.8],
	[Vector3(14.0, 0, -30.0), 0.8], [Vector3(-14.0, 0, 16.0), 0.8],
	[Vector3(14.0, 0, 16.0), 0.8],
	[Vector3(-27.0, 0, 25.0), 0.85], [Vector3(27.0, 0, 25.0), 0.85],
	[Vector3(-27.0, 0, 8.0), 0.85], [Vector3(27.0, 0, 8.0), 0.85],
	[Vector3(-27.0, 0, -10.0), 0.85], [Vector3(27.0, 0, -10.0), 0.85],
	[Vector3(-20.0, 0, -36.0), 0.85], [Vector3(20.0, 0, -36.0), 0.85],
]

## The two gate watchers: the antlered hollow warden silhouette, thinned in
## `cage_watcher.gd` so three dagger stabs end one. They stand between the cages
## and the mouth, turn on the squad when the first latch goes, and are slow
## enough to learn to block.
const GATE_WATCHERS := [
	{"post": Vector3(-4.2, 0.1, -20.5)},
	{"post": Vector3(4.2, 0.1, -20.5)},
]
## The second wave: six armed watchers out of the trees at the clearing's mouth
## once the first pair is down. Each carries the weapon it drops.
const REINFORCEMENTS := [
	"sword_short", "dagger_iron", "sword_arming",
	"sword_short", "dagger_iron", "sword_arming",
]
const REINFORCE_DELAY := 2.5
## On the trail side of the mouth, coming down out of the trees into the clearing.
const REINFORCE_POSTS := [
	Vector3(-3.4, 0.1, -48.0), Vector3(-2.0, 0.1, -49.0), Vector3(-0.7, 0.1, -50.0),
	Vector3(0.7, 0.1, -50.0), Vector3(2.0, 0.1, -49.0), Vector3(3.4, 0.1, -48.0),
]

const WATCHER_SOURCE := 90
## What a sword in this camp is allowed to bite: the watchers' physics layer.
## `ArenaActor` defaults to 4 (other fighters); a warband body that kept that
## mask swings through every mob in the game and damages nothing.
const WATCHER_LAYER := 2
## Cultist steel along the walk from the cages to the mouth.
const WEAPON_DROPS := [
	["sword_short", Vector3(-0.8, 0.15, -0.5)],
	["dagger_iron", Vector3(4.4, 0.15, -10.0)],
	["sword_arming", Vector3(-4.6, 0.15, -16.5)],
]
## One big card per beat. The card pauses the game, so every line has to be
## worth reading: the lesson, then the exact keys, then the one way out.
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
		"title": "The squad is out. Hold the clearing.",
		"body": "The squad arms itself from the dead - you do not have to loot anything. Put down the watchers in front of you: three stabs each, and six more come out of the trees when the first two fall.",
		"keys": "LMB / RMB  fight        ·        E  revive",
		"footnote": "The watchers are slow and light. Hold RMB to block, then stab.",
	},
	4: {  # ESCAPING
		"kicker": "STEP 5  /  THE TRAIL",
		"title": "The way out is the trail through the wood",
		"body": "The clearing's mouth opens onto a trail of torchlight, rags and bones, cut through the dark wood. The squad comes with you and the town is at the far end of it. There is no door to open and nowhere to be carried - you walk it.",
		"keys": "W A S D  -  walk the trail        ·        the squad follows",
		"footnote": "The town's counters, its altar and its expedition gate are at the far end, on foot.",
	},
}

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
var _reinforcements := false
var _reinforce_in := -1.0
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
		warband.roster.equip(rescuer, "main", "dagger_makeshift")
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
		warband.roster.equip(rescuer_id, "main", "dagger_makeshift")
	caged_ids.clear()
	for index in PRISONER_COUNT:
		caged_ids.append(squad_ids[index])
	warband.deploy_battle(squad_ids)
	_cage_open.clear()
	for index in caged_ids.size():
		_cage_open.append(false)


## The rags every prisoner in this camp is wearing, and nothing in their hands.
func _dress_rags(merc_id: int) -> void:
	for slot in ArmorData.SLOTS:
		var armor_id := "armor_makeshift_%s" % slot
		if State.ITEMS.has(armor_id):
			warband.roster.equip(merc_id, slot, armor_id)


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
## has been cut, or anybody who was never in a cage. The rescuer is the player's
## beat, not the AI's, until the squad is out (rule 9).
func is_free(merc_id: int) -> bool:
	if merc_id <= 0:
		return false
	if not lesson_running():
		return not is_cage_clamped(merc_id)
	var index := caged_ids.find(merc_id)
	if index >= 0:
		return index < _cage_open.size() and bool(_cage_open[index])
	if merc_id == rescuer_id:
		return sequencer.state() == SequencerScript.State.FREED \
			or sequencer.state() == SequencerScript.State.ESCAPING
	return true


## `G` at the camp: cut the latch in reach, or say why not. Returns true when the
## camp answered, so the world's one interaction handler can fall through to the
## town and to the loot on the ground.
func try_interact() -> bool:
	if not lesson_running():
		return false
	if sequencer.state() != SequencerScript.State.RESCUER_ARRIVED:
		return false
	var index := _cage_in_reach()
	if index < 0:
		return false
	if controller.merc_for_peer(1) != rescuer_id:
		_set_status("Only Corvin has the shiv. Press F5 to take his body.", 3.0)
		return true
	_open_cage(index)
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
	if _cage_in_reach() >= 0 and sequencer.state() == SequencerScript.State.RESCUER_ARRIVED:
		return "G - cut the latch" if controller.merc_for_peer(1) == rescuer_id \
			else "F5  -  take Corvin's body"
	return sequencer.objective()


## The lesson's key line, or "" when the body is not the camp's business.
func hint_line(actor) -> String:
	if not lesson_running() or actor == null or not is_instance_valid(actor):
		return ""
	if not _in_camp(actor) and sequencer.state() != SequencerScript.State.ESCAPING:
		return ""
	if _cage_in_reach() >= 0 and sequencer.state() == SequencerScript.State.RESCUER_ARRIVED:
		if controller.merc_for_peer(1) != rescuer_id:
			return "F5  or  [ ]  -  take Corvin's body: only his shiv cuts a latch"
		return "G - cut this cage's latch   (%d of %d opened)" % [
			cages_open_count(), caged_ids.size()]
	return sequencer.hint()


## How many latches the player has cut, 0..4.
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
	if _reinforce_in > 0.0:
		_reinforce_in -= delta
		if _reinforce_in <= 0.0:
			_reinforce_in = -1.0
			_spawn_reinforcements()
	_maintain_watchers()
	_clamp_caged_bodies()


# --- the clearing ----------------------------------------------------------

func _build_clearing() -> void:
	var keep_clear: Array = []
	for post in DressingScript.GIBBET_POSTS:
		keep_clear.append({"point": post, "radius": 3.2})
	clearing = ClearingScript.build(self, {
		"half_width": YARD_HALF_WIDTH,
		"front": YARD_FRONT,
		"back": YARD_BACK,
		"cage_posts": CAGE_POSTS,
		"mouth": GATE_POINT,
		"mouth_half_width": MOUTH_HALF_WIDTH,
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
		_add_watcher(spec["post"], "CampWatcher%d" % (guards.size() + 1))


func _add_watcher(at: Vector3, label: String, weapon: String = "") -> Node3D:
	var watcher := WatcherScript.new()
	watcher.name = label
	watcher.mob_id = "hollow_warden"
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


## Keep the camp's watchers pointed at whichever body is the closest threat - the
## world's one hostile driver does the aiming - and, once the first cage is open,
## let them know the camp is awake.
func _maintain_watchers() -> void:
	if guards.is_empty():
		return
	if cages_open_count() > 0 and not _watchers_awake:
		_watchers_awake = true
		for watcher in guards:
			if is_instance_valid(watcher) and bool(watcher.get("alive")):
				watcher.mob_wake()


func _on_watcher_defeated(enemy, _reward: int) -> void:
	if sequencer != null:
		sequencer.note_guard_killed()
	if is_instance_valid(enemy) and enemy.has_method("take_weapon_item"):
		var item_id := str(enemy.take_weapon_item())
		if not item_id.is_empty():
			_spawn_pickup(item_id, enemy.global_position + Vector3(0.3, 0.0, 0.2))
	# The wood answers the first pair: six armed watchers come in off the trail.
	if watchers_down() >= 2 and not _reinforcements:
		_reinforcements = true
		_reinforce_in = REINFORCE_DELAY
		_set_status("Something moves in the trees: six armed watchers come in.", 3.0)


## The second wave: six watchers out of the treeline at the mouth, each carrying
## the weapon it will drop when it falls. They are pointed at the warband on the
## frame they exist, so they charge in instead of waiting to spot somebody.
func _spawn_reinforcements() -> void:
	var prey = nearest_standing_body(REINFORCE_POSTS[2])
	for index in REINFORCEMENTS.size():
		var post: Vector3 = REINFORCE_POSTS[index % REINFORCE_POSTS.size()]
		var watcher := _add_watcher(post, "CampWatcher%d" % (guards.size() + 1),
			str(REINFORCEMENTS[index]))
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
		hud.set_status(objective, 6.0)
	_write_prompt(objective, objective)
	# Entering the fight reconciles kills and steel the squad already landed
	# while the cages were still being cut.
	if state == SequencerScript.State.FREED:
		sequencer.note_battle_state(watchers_down(), _steel_taken)
		if squad != null:
			squad.following = false
	match state:
		SequencerScript.State.ALL_SEEN:
			_jogging = true
		SequencerScript.State.ESCAPING:
			# The squad stops holding the clearing and walks the trail with the
			# soul: the same module, one escort clause.
			if squad != null:
				squad.following = true
				squad.engage_radius = 34.0
			if screen != null:
				screen.refresh()


## The rescuer is through and stands still: the soul is NOT moved for the player.
## Taking his body is the beat - F5 or [ ] - and no latch opens until Corvin's
## hands are the player's hands.
func _on_rescuer_ready(merc_id: int) -> void:
	_jogging = false
	var actor = controller.body_of(merc_id) if controller != null else null
	if actor != null and is_instance_valid(actor):
		actor.accept_network_input(Vector2.ZERO, false)
	if hud != null:
		hud.set_status("Corvin is through with the shiv. Press F5 (or [ ]) to take his body.", 6.0)


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

## The cage whose bars are closest to the standing body while it is still shut,
## or -1.
func _cage_in_reach() -> int:
	if controller == null:
		return -1
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
## cage - which is the reason the soul has to be taken in the first place.
func _open_cage(index: int) -> void:
	if index < 0 or index >= _cage_open.size() or bool(_cage_open[index]):
		return
	_cage_open[index] = true
	sequencer.note_cage_opened(index)
	var who: String = warband.roster.name_of(int(caged_ids[index]))
	_set_status("Latch cut. %s is free (%d/%d)." % [who, cages_open_count(),
		caged_ids.size()], 3.0)


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

## The preview's night: the trail's own, so the clearing is lit exactly as it is
## inside the world.
func _build_night() -> void:
	preload("res://scripts/world/environment_kit.gd").build(self, RunForestScript.night_style())


## The preview's floor, wider than the fence and the mouth on every side.
func _build_floor() -> void:
	var mat: Material = preload("res://scripts/world/texture_library.gd").ground_material(
		RunForestScript.night_style())
	var centre := Vector3(0.0, -0.3, (YARD_FRONT + YARD_BACK) * 0.5)
	var size := Vector3(YARD_HALF_WIDTH * 2.0 + 90.0, 0.6, YARD_BACK - YARD_FRONT + 120.0)
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
