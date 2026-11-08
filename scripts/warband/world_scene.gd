extends Node3D
## GHOST OF THE WARBAND: the campaign, as one continuous world.
##
## Hearthstead is where a run starts: the walled square with its counters, its
## altar, the recruiter's board and the two gates that lead out of it. Walking is
## the only way anywhere - there is no scene door to press - and the two
## directions are the two things to do: **the road**, 1,374 m of wood with a
## cage, cultists and warcamps on it, ending at the deep wood where the
## Horned Thing holds his patch; and **the Hollow**, the descent under the square.
## They stand in **one coordinate space** on **one ground**: `terrain.gd`'s
## heightfield, with the town square padded flat into a rolling forest floor.
##
## The band a run opens with is one naked body standing in that square: nothing
## is issued, and every piece he ends the campaign in was won off a body he put
## down - one piece per kill, onto a field body this world owns (`arm_one_piece`,
## from `_arm_from_kill`). The second body is the one cage on the road, or the
## recruiter's desk in the square.
##
## It owns the things a warband scene must own exactly once - the
## `PossessionController` and its bodies, the camera, the `WarbandHud`, the
## warband screen, the paperdoll, the tips, the ability scene, the
## campaign menu, the loot vacuum, the revive channel, the downed-crawl, the
## branded runner, and the wilderness band on the way out - and it builds the
## areas that bring only their own geometry and their own business:
##
##   * `Wood` - `wood_boss.gd`: the ragged pocket at the road's far end and the
##     demon in it. No fences and no cages: a hole in the trees with a fire, and
##     the Horned Thing standing in the middle of it.
##   * `Trail` - `escape_run.gd`: the 915 m way through the wood, with the twenty
##     cultists on it. There is no lane: a faint worn line between trunks that
##     stand in it, marked by a pair of torches every twelve metres. Its first
##     waypoint is `Camp.CAMP_TO_ROAD_METRES` of ordinary wood past the camp's
##     mouth, so the way on is a long walk and not the other side of a hedge.
##   * `Town` - `town_hub.gd`: the square at the far end, walled on three sides,
##     open where the trail comes in.
##
## Nothing in this scene changes scene: walking is the only way between the three
## places, and the campaign menu's own doors go through `GameFlow`.
##
## Keys: O warband, ESC the campaign menu (resume, save, load, settings, leave,
## quit), TAB quick weapon swap, P paperdoll, G interact and the revive hold,
## K manual loot (never advertised), R the branded sigil, X shoulder swap.
## Q and E are held to strafe, WASD to walk, so neither is a press key. The camp's
## lesson adds F1-F5 and `[` `]`.


const ControllerScript = preload("res://scripts/warband/possession_controller.gd")
const HudScript = preload("res://scripts/warband/warband_hud.gd")
const ScreenScript = preload("res://scripts/warband/warband_screen.gd")
## The `P` panel is the corpse screen, which extends the paperdoll: a living body's
## gear and a dead body's pockets are the same panel, so every equip path, the
## change signal and `is_open()` are unchanged.
const PaperdollScript = preload("res://scripts/warband/corpse_loot_panel.gd")
const GearDropScript = preload("res://scripts/warband/gear_drop.gd")
const TipsScript = preload("res://scripts/warband/warband_tips.gd")
const LootScript = preload("res://scripts/warband/loot_vacuum.gd")
const CrawlScript = preload("res://scripts/warband/crawl_to_safety.gd")
const ReviveScript = preload("res://scripts/warband/revive_channel.gd")
const BrandedScript = preload("res://scripts/warband/branded_runner.gd")
const SquadDriveScript = preload("res://scripts/warband/squad_drive.gd")
const Perf = preload("res://scripts/perf_probe.gd")
## The arena loop: the director that runs a wave campaign and the plate it reads.
const RogueliteDirectorScript = preload("res://scripts/roguelite/run_director.gd")
const RogueliteHudScript = preload("res://scripts/roguelite/roguelite_hud.gd")
## The F12 overlay asks this world for its own line through the overlay's group.
const PerfOverlayScript = preload("res://scripts/perf_overlay.gd")
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
const WoodScript = preload("res://scripts/warband/wood_boss.gd")
const TrailScript = preload("res://scripts/warband/escape_run.gd")
const TownScript = preload("res://scripts/warband/town_hub.gd")
const RunForestScript = preload("res://scripts/warband/run_forest.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
## What a slot is read with when a kill arms a body: an empty slot and the naked
## set a body is born in are both bare, and a piece is called by its own name.
const EquipmentRules = preload("res://scripts/equipment_rules.gd")
const State = preload("res://scripts/player_state.gd")
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
## The two places the quartermaster's orders happen: the caged soldier strung
## down the wood, and three warcamps of watchers near the town wall. Both take the
## world the way an area does and build only their own content.
const SoldierCagesScript = preload("res://scripts/warband/soldier_cages.gd")
const WatcherWarrenScript = preload("res://scripts/warband/watcher_warren.gd")
## The take-it-all: shift and a right click on a body or a drop, the body ducks
## and the warband takes everything on it in one go.
const LootHandScript = preload("res://scripts/warband/loot_hand.gd")
## The tiny loot window a plain right click on a body opens, and the looted list
## every booked piece is written to.
const LootFeedScript = preload("res://scripts/warband/loot_feed.gd")
## The campaign's map sheet. One page, drawn by one `_draw()`, opened with `M`.
const WorldMapScript = preload("res://scripts/warband/world_map.gd")
## The delve: the Weeping Hollow's mouth in the square, the counter a party and its
## delve inventory are made up at, and the cave instance it goes down into.
const DelveAreaScript = preload("res://scripts/warband/delve_area.gd")
const ArenaAreaScript = preload("res://scripts/warband/arena_area.gd")

## How far past the lane's far end the town square stands. The lane ends at the
## town's north gate; the square's centre is this far beyond it.
const TOWN_BEHIND := 30.0
## Half-size of the flat pad cut into the field for the town. It has to be wider
## than the stockade ring (`town_hub.WALL_RADIUS` 22) or the wall stakes would be
## planted on the field's own rolling ground - and not much wider, because every
## metre past the wall is a flat apron of pale pad outside a dark stockade, which
## reads as concrete rather than as a clearing.
const TOWN_PAD := 26.0
## How close a body has to stand to something to loot it by hand.
const LOOT_REACH := 2.6
## `ArenaActor` clamps a body to a square around the world origin, and the town
## stands more than a kilometre and a third south of the camp: this is the whole
## map, with room to spare. A bound that fitted one area would wall the world in
## halfway down the trail - and a bound that stops a step short of the gate is
## worse than either, because the body simply stops walking in the middle of the
## road and nothing on screen says why.
const BODY_BOUNDS := 1900.0
## A watcher only takes an interest in a body it can plausibly reach: without
## this the camp's guards would run the whole trail after a squad that left.
const AGGRO_RADIUS := 55.0
## Physics ticks between two party brain ticks. The squad's brains are decisions,
## not physics: a body whose intent is rewritten every 50 ms walks the same
## ground as one rewritten every 16, and the tick it is granted carries the whole
## elapsed time - the same rule `MobLod` gives a mob its skipped frames. The
## soul's own body never waits for it: the controller integrates every tick.
const SQUAD_TICKS := 3
## The source a wilderness blow is booked under, beside the camp's watchers (90)
## and the trail's cultists (91): damage scaling, the threat a body remembers and
## the death record all name an attacker family by number, and the band on the way
## out is its own family.
const WILDERNESS_SOURCE := 92
## What a warband missile may strike: the world (1) and the wood's own bodies (2).
## A squadmate is deliberately not in the set - the warband's swords do not cut
## its own, and neither do its arrows.
const PROJECTILE_HIT_MASK := 1 | 2
## A thrown piece finds the warband's own bodies as well as the wood's: a blade
## that sticks in a player is the whole point of throwing one, and the thrower's
## own body is excluded at launch. Arrows keep to the world and the mobs.
const THROWN_HIT_MASK := 1 | 2 | 4
## A ceiling on live missiles, oldest freed first, so a long trail fight cannot
## grow the tree without bound.
const PROJECTILE_CAP := 64
## How long the warband lies in the mud before the world stops pretending.
const WIPE_BEAT := 2.5
## The band a fallen squadmate is taught in: close enough that the player is in
## the fight that put them down, wide enough that the tip does not wait for a body
## to fall at their feet.
const REVIVE_LESSON_RADIUS := 12.0
const REVIVE_LESSON_STEP := "lesson_revive"
## The door the menu's "exit to title" row opens.
const TITLE_SCENE := "res://title.tscn"
## What a co-op guest is told when it reaches for a latch, a counter or the
## Hollow's mouth: those are worked from the host's own hands. A corpse and a
## drop are the guest's to search, and ride the intent channel like a swing.
const GUEST_HANDS_TEXT := "Co-op: latches, counters and the Hollow's mouth are the host's to work."
## The world's three one-line lessons. Each is a key and a command, offered once,
## the first time the fact it names is true: a squadmate down, the player's own
## body down, and a wound with nobody near enough to punish a bandage. They are
## the same channel the opening teaches with - nothing pauses, nothing is read.
const REVIVE_LESSON := {"keys": "HOLD G", "text": "PICK UP A FALLEN SQUADMATE"}
const BANDAGE_LESSON := {"keys": "Z", "text": "BANDAGE · +35 · HOLD STILL"}
const DOWNED_LESSON := {"keys": "HOLD G   F1", "text": "YOU ARE DOWN · AN ALLY LIFTS YOU"}


## The score is the wood's, and the town is where the run ends: the first frame
## the soul stands in the square the soundtrack fades out, and it comes back only
## if the squad walks back out through the gate. Long enough that arriving reads as
## relief rather than a cut, because the last kilometre of trail is a chase.
const TOWN_FADE_SECONDS := 2.5
## How far past the square a body must walk before the score is back. The band
## between the two answers is the hysteresis: a soul standing on the line keeps
## the track it already has instead of stuttering the whole soundtrack.
const TOWN_QUIET_MARGIN := 6.0

## The damage lesson's two numbers: a bandage is three seconds of wrapping and 35
## health, and it is taught the first time a body is badly hurt with nobody close
## enough to punish the channel. The radius is a fight's breath, not the whole wood.
const BANDAGE_LESSON_STEP := "lesson_bandage"
const BANDAGE_LESSON_HEALTH := 0.6
const BANDAGE_LESSON_RADIUS := 22.0
const DOWNED_LESSON_STEP := "lesson_downed"

var warband
var flow
## The mixer, for the one thing a place changes about it: the town has no score.
var audio
var controller
var camera: Camera3D
var hud
## The one ability scene for the campaign: bodies are bound as they are adopted.
var abilities
## Escape's window: the warband's own quick menu, on a layer above the HUD.
var menu
var screen
var paperdoll
## The one hint channel: a key and a command under the crosshair.
var tips
var loot
var revive
var branded
var brand_hud
var squad
## Ticks banked toward the party's next brain tick, and the time they added up to
## (`SQUAD_TICKS`). Seeded full, so the first tick of the world drives the band.
var _squad_ticks := SQUAD_TICKS
var _squad_delta := 0.0
## Ticks banked toward the next retarget sweep (the same `SQUAD_TICKS` budget).
var _retarget_ticks := 0
## The band between the camp's mouth and the lane. Built after the warband is
## seated, because a wolf's first target is a real body.
var wilderness
## The quartermaster's orders, where they happen: the caged soldier down the
## wood, and the warcamps of watchers near the town.
var soldier_cages
var watcher_warren
## The take-it-all, the loot window, the looted list, and the campaign's map sheet.
var loot_hand
var loot_feed
var world_map
## The delve (`delve_area.gd`): the mouth in the square and the instance below.
var delve_area
## The arena (`arena_area.gd`): the ring above the world, and the warband it
## stands against the party.
var arena
## The arena run: director, island and its plate. Always present; idle until the
## Start Run Portal opens a run.
var roguelite
var roguelite_hud
## The three areas. Each is the same script its standalone preview uses.
var wood
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
## "town" (Hearthstead - where a fresh run and a resumed save both stand),
## "checkpoint" (the autosave's bookmark) or "guest" (a co-op guest fielding the
## host's bodies). Read from `GameFlow.world_start`.
var start_area := "town"

var _crawls: Array = []
## Every arrow and thrown blade in flight. Nothing else in this mode owns them.
var projectiles: Array = []
var _reviving := false
var _prompt_text := ""
## The player's own body went down while a panel was up: the tip is offered on
## the first frame the screen is clear again rather than written over a read.
var _downed_tip_pending := false
var _roster_elapsed := 0.0
var _wipe_beat := -1.0
var _wiped := false
## True when this machine is a co-op guest. The flow connects before the world
## opens, so the role is known from the first line of `_ready`: a client fields
## the host's bodies but does not own the world - it writes no checkpoint, runs no
## squad AI, drops and books nothing, and never swings a mob the session has
## marked as a replica.
var _client := false
## The body the soul was watching on the last frame, so the HUD line changes
## exactly when the watch does.
var _watched_body = null
## A guest's revive is the host's channel; this is the guest's own count of it,
## for the prompt.
var _guest_revive := 0.0
## What the heightfield was baked to: `{triangles, cell, min, max}`.
var _terrain: Dictionary = {}
## Bodies currently wearing the arena's dress because they stand in the square.
## The campaign's gear is restored the moment one walks out of the walls.
var _town_dressed: Dictionary = {}
var _roguelite_was_running := false
## Where the town square stands, worked out before the ground so its pad can be
## cut into the field.
var _town_at := Vector3.ZERO


func _ready() -> void:
	# The F12 overlay (`perf_overlay.gd`) reads its world line from this group.
	add_to_group(PerfOverlayScript.CONTEXT_GROUP)
	warband = get_node_or_null("/root/Warband")
	if warband == null:
		push_error("WarbandWorld needs the Warband autoload")
		return
	flow = get_node_or_null("/root/GameFlow")
	audio = get_node_or_null("/root/Audio")
	_client = flow != null and str(flow.warband_role()) == "client"
	start_area = _wanted_start()
	# The shared blood art is generated once per process. Left to the first blow
	# that needs it, the walk over its six images lands inside the damage frame
	# of a session's first fight; here it lands inside the load.
	BloodFx.prewarm()
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
	_build_delve()
	_build_roguelite()
	if _client:
		_become_client()
	# The soul is wired before it is seated: the very first possession is the
	# field's first seen body, and a signal connected afterwards would miss it.
	_wire_possession()
	_seat_warband()
	# The band comes after the seating: a wolf's first target is a real body.
	_build_wilderness()
	_attach_trail()
	_build_brand()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_write_prompt("")
	_announce()
	if flow != null:
		# `bind()` is where the flow seats the session on these bodies: a host
		# opens its socket, a guest tells the host it can be put into one.
		flow.bind(self)
	# The orders' ground and the map sheet come last. The cages need the lane the
	# wood has grown and the town's wall to stand against; the warcamps need the
	# hostile list the areas have filled; and a guest fields neither.
	_build_orders()
	_build_map()


func _process(delta: float) -> void:
	Perf.begin("world.process")
	_note_hitch()
	_tick_frame(delta)
	Perf.end()


## A frame long enough to be felt is written to the log, once a second at most,
## with what the world can see of it: the frame's own time, the physics steps it
## ran, the draw calls and the count of bodies below. A session that stuttered can
## then be read back from its log instead of described from memory - the report
## "it freezes when a room comes into range" is what this line was added for.
const HITCH_USEC := 45000
var _last_frame_us := 0
var _hitch_clock := 0.0

func _note_hitch() -> void:
	var now := Time.get_ticks_usec()
	var spent := now - _last_frame_us if _last_frame_us > 0 else 0
	_last_frame_us = now
	_hitch_clock += float(spent) / 1000000.0
	if spent < HITCH_USEC or _hitch_clock < 1.0:
		return
	_hitch_clock = 0.0
	Log.event("hitch", "a frame the player would feel", {
		"ms": roundi(float(spent) / 1000.0),
		"tick": Engine.get_physics_frames(),
		"fps": roundi(Engine.get_frames_per_second()),
		# The engine's own split: process is the drawn frame's CPU, physics the
		# steps it ran. A hitch whose physics figure is small and whose process
		# figure is also small is neither - it is the GPU or the driver, and the
		# draw-call count beside it says which way to look.
		"process_ms": snappedf(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0, 0.01),
		"physics_ms": snappedf(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0, 0.01),
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"guards": guards.size() if guards != null else 0,
		"below": delve_area != null and delve_area.cave != null,
	}, Log.LEVEL_WARN)


func _tick_frame(delta: float) -> void:
	if controller == null:
		return
	var panel_open := _panel_open()
	var wanted := Input.MOUSE_MODE_VISIBLE if panel_open else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != wanted:
		Input.mouse_mode = wanted
	_tick_revive(delta)


## The F12 overlay's line about this world (`perf_overlay.gd`): what the frame
## is running, which is what its timings are read against.
func perf_context() -> PackedStringArray:
	var living := 0
	var total := 0
	for body in bodies:
		if is_instance_valid(body):
			total += 1
			if body.get("alive") == true:
				living += 1
	# The wilderness wolves and the warren's wardens append themselves to
	# `guards`, so the one list is every hostile the world runs. A parked body
	# (`dormant`, the culler's sleep) has no physics tick and no draw call.
	var hostiles := 0
	var parked := 0
	for guard in guards:
		if is_instance_valid(guard) and guard.get("alive") == true:
			hostiles += 1
			if guard.get("dormant") == true:
				parked += 1
	var missiles := 0
	for missile in projectiles:
		if is_instance_valid(missile):
			missiles += 1
	var drops := 0
	for drop in pickups:
		if is_instance_valid(drop):
			drops += 1
	return PackedStringArray([
		"world    %d/%d bodies   %d hostiles (%d parked)   %d missiles   %d drops"
		% [living, total, hostiles, parked, missiles, drops]])


func _physics_process(delta: float) -> void:
	Perf.begin("world.physics")
	_step_world(delta)
	Perf.end()


func _step_world(delta: float) -> void:
	if controller == null:
		return
	# A soul with no body of its own says whose it is watching.
	_sync_watch()
	# The squad's brains write a body's intent for this frame, so they run before
	# the controller integrates it; the watchers tick themselves. A guest does not
	# run them: its bodies are the host's to drive, and a second brain on the same
	# body is a fight with itself.
	_sync_crawl_control()
	if squad != null and not _client:
		# The band's brains run every `SQUAD_TICKS`, on the time they skipped.
		_squad_ticks += 1
		_squad_delta += delta
		if _squad_ticks >= SQUAD_TICKS:
			Perf.begin("squad.drive")
			# How the party picks its fights is the warband's, set from the menu.
			squad.party_mode = warband.party_mode
			squad.drive(_squad_delta)
			# The band's own fights, as the notifier reads them: a break-off is said
			# once and then stands under the roster until the ally is back.
			if hud != null:
				hud.set_aggro(squad.engaged_allies())
			Perf.end()
			_squad_ticks = 0
			_squad_delta = 0.0
	controller.physics_step(delta)
	# A replica is a mob the session is showing, not one this machine owns: it is
	# handed no target, so no local sense ever wakes it behind the host's back.
	# Every hostile against every body every tick was a hundred distance checks a
	# tick for a decision nothing can notice being 50 ms old: the same budget the
	# band's own brains run on.
	_retarget_ticks += 1
	if _retarget_ticks >= SQUAD_TICKS:
		_retarget_ticks = 0
		Perf.begin("squad.retarget")
		SquadDriveScript.retarget(_local_guards(), _targetable_bodies(), AGGRO_RADIUS)
		Perf.end()
	# The delve's own clock: dens that wake, a party that falls, the eye's sky.
	if arena != null:
		Perf.begin("arena.tick")
		arena.tick(delta)
		Perf.end()
	if delve_area != null:
		Perf.begin("delve.tick")
		delve_area.tick(delta)
		Perf.end()
	if roguelite != null:
		Perf.begin("roguelite.tick")
		roguelite.tick(delta)
		Perf.end()
	Perf.begin("world.books")
	_sync_roster(delta)
	_sync_field()
	_sync_town_dress()
	Perf.end()
	Perf.begin("world.prompts")
	_update_prompt()
	_push_downed_tip()
	_update_bandage_tip()
	Perf.end()
	Perf.begin("world.flow")
	_sync_town_music()
	_check_checkpoints()
	_check_wipe(delta)
	Perf.end()


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
				paperdoll.open(_soul_merc())
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if roguelite_hud != null and roguelite_hud.close_top():
				get_viewport().set_input_as_handled()
				return
			# The warband's window is the menu: close it, close whatever panel is
			# under it, or open it. The menu is the settings page's door now, so
			# Escape no longer opens a second, narrower settings window.
			if menu != null and menu.is_open():
				# One page at a time: the controls and sound pages hand the frame
				# back, and only the menu itself closes on the next press.
				if not menu.back():
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
		KEY_H:
			# Fast travel home: the map's own verb, and only while the sheet is
			# open. `H` rather than `T`, which is the throw binding the controller
			# reads before this handler.
			if world_map != null and world_map.is_open():
				world_map.travel_home()
				get_viewport().set_input_as_handled()
		KEY_M:
			# One page, and it never pauses: the map is something a body reads
			# while it keeps walking. Above it is the wood's sheet; below, the
			# Hollow's own plan of the floor.
			if delve_area != null and delve_area.in_cave(_soul()) and delve_area.map != null:
				if world_map != null and world_map.is_open():
					world_map.close()
				if _panel_open():
					_hide_panels()
				delve_area.map.toggle()
				get_viewport().set_input_as_handled()
			elif world_map != null:
				if delve_area != null and delve_area.map != null and delve_area.map.is_open():
					delve_area.map.close()
				if _panel_open():
					_hide_panels()
				world_map.toggle()
				get_viewport().set_input_as_handled()
		KEY_R:
			_activate_brand()
			get_viewport().set_input_as_handled()
		KEY_G:
			_try_interact()
			get_viewport().set_input_as_handled()
		KEY_B:
			_cycle_party_mode()
			get_viewport().set_input_as_handled()


## `B` steps the party to its next mode (`Warband.cycle_party_mode`: OFFENSIVE,
## DEFENSIVE, PASSIVE) and says the answer - a lent warband's refusal included - on
## the status line. The squad list's party line and the menu's row follow the books.
func _cycle_party_mode() -> void:
	if warband == null:
		return
	var result: Dictionary = warband.cycle_party_mode()
	if hud != null:
		hud.set_status(str(result.get("message", "")), 2.5)


## `G` held is the revive channel: hold it for `REVIVE_CHANNEL_SECONDS` (five) on a
## downed squadmate and the body stands up on `REVIVE_HEALTH_FRACTION` of its pool.
## The key is consumed on press only when a downed body is actually in reach, so a
## tap of `G` still cuts a latch, opens a counter or searches a corpse when nobody
## is on the floor beside you; releasing early drops the work and spends nothing.
func _input(event: InputEvent) -> void:
	if _loot_click(event):
		return
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
		{"rect": Rect2(-WoodScript.YARD_HALF_WIDTH, WoodScript.YARD_FRONT,
			WoodScript.YARD_HALF_WIDTH * 2.0,
			WoodScript.YARD_BACK - WoodScript.YARD_FRONT),
			"y": TerrainScript.PAD_Y, "blend": 14.0},
		{"rect": Rect2(_town_at.x - TOWN_PAD, _town_at.z - TOWN_PAD,
			TOWN_PAD * 2.0, TOWN_PAD * 2.0), "y": TerrainScript.PAD_Y, "blend": 16.0},
	]
	# What feet have worn, painted into the ground's own map: the line of torches,
	# the deep wood's pocket, its corridor out through the trees and its ruts, and the
	# ring of the town's square with the road in through its gate.
	var worn := [
		{"points": _lane_line(), "half_width": 3.2, "strength": 0.95},
	]
	worn.append_array(WoodScript.trodden_ground())
	worn.append_array(TownScript.trodden_ground(_town_at))
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
	# A guest is connected before this world opens, so its soul is its own ENet
	# peer from the first frame; the host and a solo game are peer 1.
	if _client:
		controller.local_peer_id = multiplayer.get_unique_id()
	# TAB and the revive hold are this scene's verbs, run on the authority for
	# whichever soul pressed them.
	controller.world_action = Callable(self, "_on_world_action")
	# The wood's own bodies join the host's rewind: a guest's blade has to find
	# the watcher the guest's screen showed, not the one that has moved since.
	controller.lag_extras = Callable(self, "_lag_bodies")


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
	tips = TipsScript.new()
	tips.name = "Tips"
	add_child(tips)


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
	# below the tips' 7, because the prompt under the crosshair is read over it.
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
	# The take-it-all. It lives beside the vacuum because it is the vacuum's other
	# hand: the same booking path, started by a gesture instead of a key.
	loot_hand = LootHandScript.new()
	loot_hand.name = "LootHand"
	add_child(loot_hand)
	loot_hand.setup(self)
	# Every piece the warband books - the soul's hands, a squadmate's, a sweep's -
	# is one line on the looted list.
	loot_feed = LootFeedScript.new()
	loot_feed.name = "LootFeed"
	add_child(loot_feed)
	loot.booked.connect(_on_loot_booked)


func _on_loot_booked(item_id: String, collector_peer: int) -> void:
	note_booked(item_id, "" if collector_peer > 0 else "squad")
	# The booking happened here; every other soul's own loot list is told the same
	# line, or a guest's list stays empty for the whole session while its warband
	# is the same one being fed.
	if flow != null and flow.session != null:
		flow.session.announce_booked(item_id, collector_peer)


## One line on the looted list, from this machine's own booking or from the
## host's. `who` is empty for the soul whose hands took it.
func note_booked(item_id: String, who: String = "") -> void:
	if loot_feed != null and not item_id.is_empty():
		loot_feed.note(item_id, who)


## The orders' ground: the caged soldier down the wood and three warcamps of
## watchers near the town. Both take this world the way an area does - they are
## built from the lane the trail has already grown - and both know to field
## nothing on a guest, whose wood is the host's.
func _build_orders() -> void:
	soldier_cages = SoldierCagesScript.new()
	soldier_cages.name = "SoldierCages"
	add_child(soldier_cages)
	soldier_cages.setup(self)
	watcher_warren = WatcherWarrenScript.new()
	watcher_warren.name = "WatcherWarren"
	add_child(watcher_warren)
	watcher_warren.setup(self)


## The map sheet. `M` opens it; it draws from this world, so it is built with one.
func _build_map() -> void:
	world_map = WorldMapScript.new()
	world_map.name = "WorldMap"
	add_child(world_map)
	world_map.configure(self)


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
	wood = WoodScript.new()
	wood.name = "Wood"
	wood.host = self
	add_child(wood)

	town = TownScript.new()
	town.name = "Town"
	town.host = self
	town.position = _town_at
	add_child(town)
	town.embed(self)


## The delve stands in the square the town just built, and hands the squad its
## cave map and the soul its party when a party goes down.
func _build_delve() -> void:
	delve_area = DelveAreaScript.new()
	delve_area.name = "Delve"
	add_child(delve_area)
	delve_area.setup(self)
	arena = ArenaAreaScript.new()
	arena.name = "Arena"
	add_child(arena)
	arena.setup(self)


## The roguelite loop's own node and plate. Built with the other areas so the
## director can answer a request made before the first run, and so a guest's HUD
## exists before the host's first state arrives.
func _build_roguelite() -> void:
	roguelite = RogueliteDirectorScript.new()
	roguelite.name = "Roguelite"
	add_child(roguelite)
	roguelite.setup(self)
	roguelite_hud = RogueliteHudScript.new()
	roguelite_hud.name = "RoguelitePlate"
	add_child(roguelite_hud)
	roguelite_hud.setup(self, roguelite)
	var ledger = get_node_or_null("/root/Roguelite")
	if ledger != null and ledger.has_signal("announcement") \
			and not ledger.announcement.is_connected(_on_roguelite_announcement):
		ledger.announcement.connect(_on_roguelite_announcement)


## A key banked, a weapon opened: the meta ledger's own line, said once on the
## world's status strip. A guest hears it for the keys the host's run paid too.
func _on_roguelite_announcement(text: String) -> void:
	if hud != null and hud.has_method("set_status") and not text.is_empty():
		hud.set_status(text, 3.5)


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
	var trail_start := Vector3(WoodScript.GATE_POINT.x, 0.0,
		WoodScript.GATE_POINT.z - WoodScript.CAMP_TO_ROAD_METRES)
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
	if start_area == "guest":
		_seat_guest()
	elif start_area == "checkpoint" and warband.has_checkpoint():
		_seat_checkpoint()
	else:
		town.seed_warband()
		bodies = controller.spawn_mercenaries(town.spawn_posts(), true)
		town.place_warband(bodies)
	_adopt_bodies()
	_sync_town_dress()
	_on_possession_changed(controller.local_peer_id, _soul_merc())


## The bookmark is a place the warband already stood: the town's own fire ring,
## or a ring of posts a few metres around the trail point it holds. Nothing is
## seeded, dressed or re-taught - the roster is what the save says it is.
func _seat_checkpoint() -> void:
	if warband.checkpoint_area() == "town":
		town.seed_warband()
		bodies = controller.spawn_mercenaries(town.spawn_posts(), true)
		town.place_warband(bodies)
		return
	var ground := _checkpoint_ground()
	var posts := _spawn_ring(ground, maxi(1, warband.roster.field_count()))
	bodies = controller.spawn_mercenaries(posts, true)
	# A party resumed on the trail walks with the soul.
	if squad != null:
		squad.following = true
		squad.engage_radius = 34.0


## A co-op guest fields exactly the bodies the host has on the field - the host's
## roster, lent - and nothing is seeded, dressed or taught: the warband is the
## host's, and so is every decision about it. They stand in a ring where the party
## is until the host's first snapshot puts each one where it really stands, as
## replicas the host drives; the host seats this soul once the world is up.
func _seat_guest() -> void:
	var field := _guest_field()
	var wanted: Array = field.get("bodies", []) if field.get("bodies", []) is Array else []
	var focus := Vector3.ZERO
	var raw: Variant = field.get("focus", [])
	if raw is Array and (raw as Array).size() == 3:
		focus = Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	if focus.is_zero_approx() or not focus.is_finite():
		focus = _checkpoint_ground() if warband.has_checkpoint() else WoodScript.GATE_POINT
	var posts := _spawn_ring(TerrainScript.grounded(focus), maxi(1, wanted.size()))
	bodies = controller.spawn_mercenaries(posts, false, wanted)


## Where a trail bookmark stands on the ground. Zero is a marker from a file that
## named no position: the lane's first stretch past the camp is the safe answer.
func _checkpoint_ground() -> Vector3:
	var point: Vector3 = warband.checkpoint_position()
	if point.is_zero_approx():
		point = Vector3(WoodScript.GATE_POINT.x, 0.0, WoodScript.GATE_POINT.z - 55.0)
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
		_adopt_body(actor)
	_squad_moved()
	_seat_loose_soul()


## One body's wiring, for the seating above and for a body that takes the field
## after it (`_sync_field`).
func _adopt_body(actor) -> void:
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
		# A guard that took a blow comes down and stays down until the button is
		# pressed again. On the soul's own body that is said out loud: a guard
		# that dropped with the button still held is otherwise indistinguishable
		# from a button that stopped working.
		actor.guard_broken.connect(_on_guard_broken.bind(actor))
	# A body that is struck names its striker, and the squad's party mode decides
	# whether the band answers it.
	if squad != null:
		actor.struck_by.connect(squad.note_struck)
	# A worn hand torch is light, and light belongs to the body carrying it.
	if merc_id > 0:
		var torch := TorchScript.new()
		actor.add_child(torch)
		torch.setup(actor, merc_id, warband)


## The squad's brain and the revive channel read the body list, so a body that
## joins has to reach both.
func _squad_moved() -> void:
	if squad != null:
		squad.squad_ids = squad_ids
	if revive != null:
		revive.set_bodies(bodies)


## The soul goes into a body before anything hunts it: a spectator's camera
## while two cultists run at nothing is not a first fight. A guest's soul is the
## host's to seat.
func _seat_loose_soul() -> void:
	if _soul_merc() <= 0 and not squad_ids.is_empty() and not _client:
		controller.direct(controller.local_peer_id, int(squad_ids[0]))


# --- the field ---------------------------------------------------------------
#
# Every name with a place on the field (`WarbandRoster.field_ids`) has a body in
# the world. A place taken after the world was seated - a hire at the recruiter,
# a soldier cut out of a cage, the reserve called up in the square - is a body
# spawned here on the next frame, wired like the rest and in the squad at once.
# A name sworn past a full field waits in the reserve with no body, and the
# reserve is only ever called up in the town. A guest spawns nothing on its own
# account: the host's books say who is on the field, and its copy follows them.

## Where a body that has just been sworn stands up, by merc id: the spot a soldier
## walked out of his cage to. A name with no entry musters at the town's fire
## while the party is in the square, and beside the party anywhere else.
var _muster_at: Dictionary = {}

func _sync_field() -> void:
	if warband == null or controller == null:
		return
	# A guest's world outlives its loan by a frame or two, and the roster under it
	# is then this machine's own: none of those names has a place on this field.
	if _client and not warband.lent:
		return
	if not _client:
		_call_up_reserve()
	var joined: Array = []
	for merc_id in warband.roster.field_ids():
		if controller.body_of(merc_id) != null:
			continue
		var posts: Array[Vector3] = [_muster_point(merc_id, joined.size())]
		var wanted: Array[int] = [merc_id]
		joined.append_array(controller.spawn_mercenaries(posts, not _client, wanted))
		_muster_at.erase(merc_id)
	if joined.is_empty():
		return
	for actor in joined:
		bodies.append(actor)
		_adopt_body(actor)
	_squad_moved()
	_seat_loose_soul()
	# A guest's map may already seat a soul in the body that just stood up here.
	if _client:
		var link := get_node_or_null("/root/GameFlow/WarbandLink")
		if link != null and link.has_method("readopt_ownership"):
			link.readopt_ownership()


## The reserve takes the field only in the town: while the party stands in the
## square and the field has a place, the name that has waited longest takes it.
func _call_up_reserve() -> void:
	if town == null or warband.field_room() <= 0:
		return
	var focus = controller.focus_body()
	if focus == null or not is_instance_valid(focus) or not town.in_square(focus):
		return
	var names: Array[String] = []
	var merc_id: int = warband.deploy_reserve()
	while merc_id > 0:
		names.append(warband.roster.name_of(merc_id))
		merc_id = warband.deploy_reserve()
	if not names.is_empty() and hud != null:
		hud.set_status("%s %s the reserve and %s the band." % [", ".join(names),
			"leaves" if names.size() == 1 else "leave",
			"joins" if names.size() == 1 else "join"], 4.0)


## A new body's ground: its own muster spot, the town's fire ring while the party
## is in the square, or a ring beside the party's body. `index` spreads the bodies
## that join on one frame.
func _muster_point(merc_id: int, index: int) -> Vector3:
	var own: Variant = _muster_at.get(merc_id)
	if own is Vector3:
		# A point that came from the world is already on the ground, and
		# `Terrain.grounded()` *adds* the y it is handed: passing that point through
		# it doubled the terrain's height, so a soldier cut out of his cage on a
		# slope stood below it (or above it) by the height of the hill he was on.
		return TerrainScript.grounded(Vector3((own as Vector3).x, 0.0, (own as Vector3).z))
	var focus = controller.focus_body()
	var party: bool = focus != null and is_instance_valid(focus)
	if town != null and (not party or town.in_square(focus)):
		var posts: Array[Vector3] = town.spawn_posts()
		var post: Vector3 = posts[(bodies.size() + index) % posts.size()]
		return TerrainScript.grounded(town.global_position + post)
	if party:
		var ring := _spawn_ring((focus as Node3D).global_position, 6)
		return ring[(bodies.size() + index) % ring.size()]
	return TerrainScript.grounded(Vector3.ZERO)


## Every body's bowstring and throwing hand. A body that is not authoritative is
## somebody's prediction: it draws and releases on screen, and only the simulation
## that owns it spawns the missile that can hurt anyone.
##
## The quiver gate is installed here too, so a body that changes its bow for a
## blade needs no second thought: `Combat.can_draw()` asks the party's one quiver
## every time the string comes up.
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
	combat.ammo_gate = _quiver_has_arrow


## The one rule behind every bow in the warband: a shaft in the quiver or nothing
## on the string.
func _quiver_has_arrow() -> bool:
	return warband == null or warband.has_arrows()


## Spend one shaft from the party quiver and mirror the spend to every peer, the
## way a kill's gold is mirrored: the quiver is one ledger, and a guest that could
## not see the spend would shoot free. Answers false when the quiver is empty, so
## the caller can refuse the missile rather than fly an arrow nobody paid for.
func spend_arrow() -> bool:
	# A run has no quiver to spend: arrows are the arena's, not the campaign's,
	# and an ability volley must not empty a purse the run never opened.
	if roguelite != null and roguelite.is_running():
		return true
	if warband == null:
		return true
	if warband.take_arrows(1) <= 0:
		return false
	var link := get_node_or_null("/root/GameFlow/WarbandLink")
	if link != null and link.has_method("report_ammo_spent"):
		link.report_ammo_spent(1)
	return true


## A bow released. The shot leaves along the camera's crosshair ray - the same ray
## the controller aimed the body down - and carries the bow's own charge damage.
func _on_body_shot(origin: Vector3, direction: Vector3, speed: float, charge: float,
		actor) -> void:
	if not _projectile_authority(actor):
		return
	# An arena run owns its own shot: the plan, the spend and the fan all go
	# through the director, which is the only thing that knows this body's mods.
	if roguelite != null and roguelite.is_running() \
			and roguelite.fire(actor, origin, direction, speed, charge):
		return
	# The shaft leaves the quiver as it leaves the string. A draw let through
	# before the count ran out - a stale prediction, a hand-fired signal - still
	# gets no free arrow.
	if not spend_arrow():
		return
	var rig = actor.rig
	var damage := float(CombatScript.damage_for(int(rig.bow_index), charge,
		rig.ranged_scale(), rig.flat_bonus("flat_ranged")))
	var arrow := ArrowScript.new()
	arrow.source_id = int(actor.slot)
	arrow.shooter = actor
	arrow.hit_mask = PROJECTILE_HIT_MASK
	arrow.authoritative_damage = true
	_arm_projectile(arrow, actor)
	add_child(arrow)
	arrow.launch(origin, direction, speed, damage, _projectile_exclude(actor),
		rig.last_arrow_visual_origin, 0)
	_keep_projectile(arrow)


## What the throwing hand let go of, as a catalog id: the main-hand copy on the
## mercenary's record. A body with no record (a test fixture, an unkitted mob)
## answers "" and its blade simply spends itself, which is what every throw did
## before a piece could stick.
func _thrown_piece(actor) -> String:
	if warband == null or controller == null or actor == null:
		return ""
	var merc: int = controller.merc_of(actor)
	if merc <= 0:
		return ""
	return str(warband.roster.equipped_of(merc).get("main", ""))


## A blade let go of mid-swing. Same authority, same layers.
func _on_body_thrown(origin: Vector3, direction: Vector3, speed: float, charge: float,
		weapon: String, weapon_index: int, actor) -> void:
	if not _projectile_authority(actor):
		return
	if roguelite != null and roguelite.is_running() \
			and roguelite.throw_weapon(actor, origin, direction, speed, charge,
				weapon, weapon_index):
		return
	var rig = actor.rig
	var damage := float(CombatScript.throw_damage(weapon, weapon_index, charge,
		rig.throw_scale()))
	var thrown := ThrownScript.new()
	thrown.weapon = weapon
	thrown.weapon_index = weapon_index
	thrown.source_id = int(actor.slot)
	thrown.shooter = actor
	thrown.hit_mask = THROWN_HIT_MASK
	thrown.authoritative_damage = true
	_arm_projectile(thrown, actor)
	if weapon == "dagger":
		thrown.blade_length = float(ArcherScript.dagger_profile(weapon_index).length)
	else:
		thrown.blade_length = float(ArcherScript.SWORD_DATA[
			clampi(weapon_index, 0, ArcherScript.SWORD_DATA.size() - 1)].length)
	add_child(thrown)
	# What the hand let go of: the worn copy's catalog id, so a blade that sticks
	# in a body can be pulled back out as the same piece (`K`).
	thrown.piece_id = _thrown_piece(actor)
	thrown.launch(origin, direction, speed, damage, _projectile_exclude(actor))
	_keep_projectile(thrown)


## A missile the host spawns for a peer's body is resolved against the bodies that
## peer saw: the shaft carries the same one-second window its owner's blade does.
## The host's own shots carry a zero window and resolve against the present.
## Guarded on the controller's callable: a scene with no `PossessionController`
## (a test, a fixture) simply has no history to rewind.
func _arm_projectile(missile, actor) -> void:
	if controller == null or not is_instance_valid(actor):
		return
	missile.lag_comp = controller.lag_history
	missile.lag_ticks = int(actor.combat.lag_ticks)


## Every hostile this world keeps a hurtbox for, as one flat list: the watcher
## camps, the wilderness wolves and the trail's own guard list.
func _lag_bodies() -> Array:
	var out: Array = []
	for guard in guards:
		if is_instance_valid(guard) and guard.get("alive") == true:
			out.append(guard)
	return out


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
		if is_instance_valid(oldest) and not bool(oldest.get("lodged")):
			oldest.queue_free()


func _wire_crawl(actor) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var crawl = CrawlScript.new()
	crawl.name = "Crawl"
	add_child(crawl)
	crawl.attach(actor)
	# Only the host drags a body: a guest's copy of a crawl is in the host's
	# snapshots, and a second crawl here would fight them.
	crawl.set_physics_process(not _client)
	_crawls.append(crawl)


## A body a soul is inside is that soul's to crawl - the host's from its keys, a
## guest's from the frames it sends - and every other downed body is the scene's.
## Re-read every frame, because souls move between bodies.
func _sync_crawl_control() -> void:
	for crawl in _crawls:
		if is_instance_valid(crawl):
			var body = crawl.actor
			crawl.manual = is_instance_valid(body) and int(body.get("peer_id")) > 0


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


## Who may act as a squadmate this frame: a body a human soul is inside is never
## a squadmate, local or remote - the AI would be writing a second intent into a
## body somebody is already walking.
func _is_free_ally(merc_id: int) -> bool:
	if merc_id <= 0:
		return false
	if warband != null and warband.souls != null and warband.souls.occupied_by(merc_id) > 0:
		return false
	# While a party is below, a body left in the town is nobody's to drive: it
	# stands where it was left until the party comes back up.
	if warband != null and warband.delve.active and not warband.delve.is_member(merc_id):
		return false
	return true


## Whether a body can walk off on its own right now. Every body this world seats
## can: the host's session seats a co-op guest in one that moves.
func is_free_body(merc_id: int) -> bool:
	return merc_id > 0


# --- the co-op role --------------------------------------------------------
#
# The world is the same place on every machine, but only the host owns it: a
# guest fields the host's bodies from the host's lent warband and follows the
# host's word on everything else.

## A guest does not work the orders and does not write the campaign: the host's
## cage state is the truth (`_build_orders` fields none on a guest), and this
## machine runs no squad AI and no local mob brains - the session marks the host's
## mobs as replicas.
func _become_client() -> void:
	_client = true
	if squad != null:
		squad.following = false
	# The corpse screen is the guest's own copy of the host's record, and every
	# take on it is the host's to book.
	if paperdoll != null:
		paperdoll.corpse_request = Callable(self, "request_corpse_take")

## What a guest's world must copy from this one to field the same mobs: whether
## the camp was built past its opening. Sent with the campaign.
func guest_layout() -> Dictionary:
	return {"start": start_area}

## The host's answer this guest's world is built on (`GameFlow.guest_field`).
func _guest_field() -> Dictionary:
	if flow == null or not flow.get("guest_field") is Dictionary:
		return {}
	return flow.guest_field

## The body this machine's own soul is inside, or null.
func _soul():
	return controller.active_body() if controller != null else null

## The mercenary this machine's own soul is inside, or -1.
func _soul_merc() -> int:
	return controller.merc_for_peer(controller.local_peer_id) if controller != null else -1

## A soul whose last body fell watches the one somebody else is still inside;
## the body panel says whose. Changes are painted once, on the frame they happen.
func _sync_watch() -> void:
	var watched = controller.watching()
	if watched == _watched_body:
		return
	_watched_body = watched
	if hud == null:
		return
	if watched == null:
		hud.set_watching("")
		return
	var merc_name: String = warband.roster.name_of(controller.merc_of(watched))
	hud.set_watching(merc_name, _soul_name(controller.watched_peer()))
	hud.set_status("No body is free. You watch %s until one is." % merc_name, 4.0)

## The player name a peer joined with, or "".
func _soul_name(peer_id: int) -> String:
	if peer_id <= 0 or flow == null or flow.session == null:
		return ""
	return str(flow.session.name_of(peer_id))

## The scene's half of the intent channel (`PossessionController.world_action`):
## run on the authority for any soul's body, a guest's included, so TAB and the
## revive hold work on the host's warband and field whoever pressed them.
func _on_world_action(actor, action: String, value) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	match action:
		"swap_set":
			return _swap_set_on(actor)
		"revive":
			return _revive_from(actor, bool(value))
		"loot":
			return _loot_from(actor, value)
		"climb_out":
			return _climb_out_for(actor)
	return false


## A soul on the rope asks the party out. The host owns the descent, so a guest's
## `G` is an intent: it is honoured only from a body standing at a rope, and it
## brings the whole party up exactly as the host's own press does. Without it a
## guest standing over the only standing body has no way out of the Hollow.
func _climb_out_for(actor) -> bool:
	if _client or delve_area == null or actor == null or not is_instance_valid(actor):
		return false
	if not delve_area.below() or delve_area.cave == null:
		return false
	if not delve_area.cave.at_exit(actor):
		return false
	var result: Dictionary = delve_area.climb_out()
	return bool(result.get("ok", false))


## A guest's take, answered on the host for the guest's body. `value` names what
## it wants: `{kind: "drop", item, at}` or `{kind: "corpse", corpse, item}`.
func _loot_from(actor, value) -> bool:
	if actor == null or not is_instance_valid(actor) or not value is Dictionary:
		return false
	var peer_id := int(actor.get("peer_id"))
	if peer_id <= 0:
		return false
	var kind := str(value.get("kind", ""))
	var item_id := str(value.get("item", ""))
	if kind == "drop":
		var at: Variant = value.get("at", Vector3.ZERO)
		if typeof(at) != TYPE_VECTOR3:
			return false
		return loot_for_peer(peer_id, "drop", 0, item_id, at)
	if kind == "corpse":
		var corpse_id := int(value.get("corpse", 0))
		return loot_for_peer(peer_id, "corpse", corpse_id, item_id, Vector3.ZERO)
	return false

## TAB on one body: its mercenary's two weapon sets trade places on the roster
## and the rig is dressed from the record.
func _swap_set_on(actor) -> bool:
	var merc_id: int = controller.merc_of(actor)
	if merc_id <= 0:
		return false
	var result: Dictionary = warband.swap_weapon_set(merc_id)
	var ok := bool(result.get("ok", false))
	if ok:
		controller.refresh_gear(merc_id)
	if hud != null and actor == _soul():
		hud.set_status(str(result.get("message", "")), 2.0)
	return ok

## The revive hold, from whichever soul's body pressed it: the channel is keyed to
## that soul's peer, exactly as the host's own is.
func _revive_from(actor, pressed: bool) -> bool:
	var peer_id := int(actor.get("peer_id"))
	if peer_id <= 0 or revive == null:
		return false
	if not pressed:
		revive.cancel(peer_id)
		return true
	var target = _revive_target_for(actor)
	return target != null and revive.begin(peer_id, target)

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


## The warband bodies a hostile may take as a quarry: every standing body on this
## field. A body left below in the Hollow, or one fighting in the ring, is not in
## this list.
func _targetable_bodies() -> Array:
	return bodies


func _wire_possession() -> void:
	controller.possession_changed.connect(_on_possession_changed)
	controller.transfer_refused.connect(_on_transfer_refused)
	controller.possession_released.connect(_on_possession_released)
	controller.draw_refused.connect(_on_draw_refused)


## The quiver is empty and the string stayed down. Said once per press, and the
## line points at the two places a shaft comes from. The peer id is the presser's,
## and only the local soul's presses reach here.
func _on_draw_refused(_peer_id: int) -> void:
	if hud == null:
		return
	hud.set_status("Out of arrows: buy a bunch from a keeper, or take them off an archer.", 2.5)


func _on_possession_changed(peer_id: int, merc_id: int) -> void:
	if peer_id == controller.local_peer_id:
		if hud != null:
			hud.set_body(_soul(), warband.roster.name_of(merc_id), merc_id)
		# The gear page is the body's own: a page showing the body the soul just
		# left follows it, so the hotbar under the cursor is always the row the
		# player's number keys fire.
		if paperdoll != null:
			paperdoll.follow_controlled(merc_id)
	_attach_brand()
	_write_prompt("")


func _on_transfer_refused(_peer_id: int, merc_id: int, reason: String) -> void:
	if hud != null:
		hud.set_status("%s: %s" % [warband.roster.name_of(merc_id), reason], 2.5)


## Only this machine's own soul is news here: a guest's body changing hands on
## the host is the guest's business, and must not blank the host's panel.
func _on_possession_released(peer_id: int, reason: String) -> void:
	if peer_id != controller.local_peer_id:
		return
	if hud != null:
		hud.set_body(null, "", -1)
		hud.set_status("The soul is loose (%s)." % reason, 4.0)
	if paperdoll != null:
		paperdoll.follow_controlled(-1)
	_attach_brand()


func _on_possess_requested(merc_id: int) -> void:
	screen.close()
	controller.direct(controller.local_peer_id, merc_id)


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
func spawn_pickup(item_id: String, at: Vector3, announced: bool = false):
	# A guest's ground carries only what the host announced: its own areas' drops
	# are the host's drops, and they arrive through the session.
	if _client and not announced:
		return null
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
## the corpse screen's, so nothing is on offer twice. A rare watcher below holds
## its steel already anointed (`delve_loot.gd`), and the drop carries that - read
## before the hand is emptied.
func drop_held_weapon(enemy) -> bool:
	var anointed: bool = is_instance_valid(enemy) and enemy.get("weapon_anointed") == true
	var dropped := false
	# The off hand first, so the blade is the last thing to hit the dirt - the same
	# order a warband body lets go in (`WarbandGearDrop.strip_hands`).
	for off in [true, false]:
		var item_id: String = GearDropScript.strip_enemy_hand(enemy, off)
		if item_id.is_empty():
			continue
		var at: Vector3 = (enemy as Node3D).global_position
		var pickup = spawn_pickup(item_id, GearDropScript.drop_point(at,
			GearDropScript.forward_of(enemy)))
		if pickup != null and anointed and not off:
			pickup.anoint()
		dropped = true
	return dropped


## One hostile dies, and the world pays for it once. The wilderness band reports
## here and nowhere else - the camp's watchers and the trail's cultists have their
## own areas' handlers for the lesson's bookkeeping, but the purse belongs to the
## world, so the reward cannot be booked twice. The same kill arms one warband
## body: a party's kit is won off what it puts down, never issued.
func _on_enemy_defeated(enemy, reward: int) -> void:
	if not is_instance_valid(enemy):
		return
	# A guest is shown the host's kill: the host pays the shared purse, drops the
	# steel, books the corpse and the orders, and every piece of that reaches this
	# machine through the session. Here the dead hand only lets go of its blade.
	if _client:
		for off in [true, false]:
			GearDropScript.strip_enemy_hand(enemy, off)
		if screen != null:
			screen.refresh()
		return
	if not bool(enemy.get("replica")):
		_pay_kill(reward)
		# The same kill is the band's armorer: one piece off the pool onto one
		# body, so the kit a campaign fights with is won rather than issued.
		_arm_from_kill()
	# The steel comes out of its hand and lands in the dirt; what it still wears is
	# the corpse screen's, so nothing is on offer twice. The body stays on the one
	# hostile list, exactly as the trail's and the warren's fallen do.
	drop_held_weapon(enemy)
	if loot != null and loot.has_method("register_corpse"):
		# The vacuum's own `corpse_registered` is what fills a guest's screen;
		# every area that books a kill this way is copied without a second call.
		loot.register_corpse(enemy)
	if screen != null:
		screen.refresh()


## Everything the map sheet marks beyond its own geography: every soldier still
## shut in a cage, and every warcamp in the wood. The sheet asks and this answers;
## nothing here draws.
func map_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if soldier_cages != null and soldier_cages.has_method("marker_points"):
		for point in soldier_cages.marker_points():
			out.append({"position": point, "label": "CAGED SOLDIER", "kind": "rescue"})
	if watcher_warren != null and watcher_warren.has_method("camp_points"):
		for point in watcher_warren.camp_points():
			out.append({"position": point, "label": "WATCHER CAMP", "kind": "hunt"})
	return out


## A soldier comes out of a cage and swears to the band: one roster record, the
## best spare kit the shared stash holds, one line on the HUD. The area that cut the latch calls this and nothing else. `at` is where he
## stands: with a place on the field he takes it there, and past a full field he
## waits in the reserve and his figure fades with nobody in its place.
func note_soldier_freed(merc_name: String, at: Vector3 = Vector3.INF) -> int:
	if warband == null:
		return -1
	var merc_id: int = warband.add_mercenary(merc_name)
	if merc_id <= 0:
		return -1
	warband.dress_recruit(merc_id)
	var waiting: bool = warband.roster.is_reserve(merc_id)
	if not waiting and at.is_finite():
		_muster_at[merc_id] = at
	if hud != null:
		var line := "%s joins the warband." % merc_name
		var seconds := 3.5
		if waiting:
			line += " The field is full: he waits in the town's reserve."
			seconds += 1.0
		hud.set_status(line, seconds)
	return merc_id

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


## Whether one body still has a slot to fill: empty, or the naked set it was born
## in. The same reading `Warband.arm_one_piece` makes of a slot, taken before the
## call so a dressed body is passed over for one that can still take a piece.
func _has_bare_slot(merc_id: int) -> bool:
	if warband == null:
		return false
	var gear: Dictionary = warband.roster.equipped_of(merc_id)
	for slot_id in EquipmentRules.SLOTS:
		var item_id := str(gear.get(str(slot_id), ""))
		if item_id.is_empty() or EquipmentRules.bare_garment(item_id):
			return true
	return false


## A kill arms a body, one piece at a time: this is the only thing that puts kit
## on the band a campaign starts with. The party body the soul is not inside takes
## the piece first, when it still has a slot to fill - so the second body a run
## wins is not the one that ends up carrying it all - and the soul's own body is
## the fallback. Only the field bodies of this world are read, so a body left
## below in the Hollow or in the ring is not dressed by a kill on the road; only a
## hostile this world killed and the party's own warband arm anything, and a lent
## one answers "" inside `arm_one_piece`. One piece and no more: the body that has
## nothing to take leaves this kill silent, and the next one too.
func _arm_from_kill() -> void:
	if warband == null or controller == null or _client:
		return
	var soul := _soul_merc()
	var chosen := -1
	for actor in bodies:
		if not is_instance_valid(actor) or not bool(actor.get("alive")) \
				or bool(actor.get("downed")):
			continue
		var merc_id: int = controller.merc_of(actor)
		if merc_id <= 0 or merc_id == soul or not _has_bare_slot(merc_id):
			continue
		chosen = merc_id
		break
	if chosen <= 0:
		chosen = soul
	if chosen <= 0:
		return
	var item_id: String = warband.arm_one_piece(chosen)
	if item_id.is_empty():
		return
	controller.refresh_gear(chosen)
	if hud != null:
		hud.set_status("%s takes up a %s." % [warband.roster.name_of(chosen),
			str(State.ITEMS.get(item_id, {}).get("name", item_id))], 2.5)


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
	# Name the striker before the blow lands, as every blade and shaft does: the
	# squad's party mode reads it (`WarbandBody.struck_by`).
	if victim.has_method("note_attacker"):
		victim.note_attacker(attacker)
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
	# The host strips the hands and announces the drop; a guest's roster hears it
	# in the host's next warband copy.
	if _client or warband == null or merc_id <= 0 or not is_instance_valid(actor):
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
	# An arena run holds a downed body: its hands are the run's, and emptying the
	# campaign's roster slots because a wave dropped it would take a body's kit
	# away for a fight that is not the campaign's.
	if roguelite != null and roguelite.is_running():
		return
	drop_merc_gear(actor, merc_id)
	# The player's own body is a different lesson from a squadmate's: the revive
	# tip is about somebody else, this one is about what the soul can still do.
	if controller != null and actor != null and is_instance_valid(actor) \
			and actor == _soul():
		_downed_tip_pending = true
		_push_downed_tip()
	_push_revive_tip(actor)


## A bare guard that stopped a blow comes down and stays down until the button is
## pressed again (a shield block never comes down, so it never lands here). Only
## the soul's own guard is called out: the band's bodies break and re-raise theirs
## without an eye on them.
func _on_guard_broken(_slot: int, actor) -> void:
	if hud == null or controller == null or actor == null or not is_instance_valid(actor):
		return
	if actor != _soul():
		return
	hud.set_status("GUARD BROKEN  -  CLICK RMB AGAIN", 1.6)


## The first squadmate to go down near the player teaches the channel: a body on
## its chest is not dead, and `G` held for five seconds brings it back. One tip,
## offered once, on the frame the fact is first true.
func _push_revive_tip(actor) -> void:
	if tips == null or controller == null or revive == null:
		return
	if actor == null or not is_instance_valid(actor):
		return
	if not bool(actor.get("downed")) or not bool(actor.get("alive")):
		return
	var soul = _soul()
	if soul == null or not is_instance_valid(soul) or soul == actor:
		return
	if not bool(soul.get("alive")) or bool(soul.get("downed")):
		return
	if soul.global_position.distance_to(actor.global_position) > REVIVE_LESSON_RADIUS:
		return
	tips.tip(REVIVE_LESSON_STEP, str(REVIVE_LESSON["keys"]), str(REVIVE_LESSON["text"]))


## The soul's own body went down: that is the player's own lesson, not a
## squadmate's, and it names both ways out - a hand, or another body - because a
## player who does not know they can leave will lie there waiting.
func _push_downed_tip() -> void:
	if tips == null or not _downed_tip_pending:
		return
	if _panel_open() or controller == null:
		return
	var soul = _soul()
	if soul == null or not is_instance_valid(soul):
		return
	if not bool(soul.get("downed")) or not bool(soul.get("alive")):
		# Somebody stood the body up before the tip could be offered: what it would
		# say is no longer true.
		_downed_tip_pending = false
		return
	_downed_tip_pending = false
	tips.tip(DOWNED_LESSON_STEP, str(DOWNED_LESSON["keys"]), str(DOWNED_LESSON["text"]))


## The bandage lesson: the first time the soul's body is at or below 60% of its
## pool with no hostile close enough to punish the channel, the world says `6` out
## loud. A body that learned it in a fight would learn it face down.
func _update_bandage_tip() -> void:
	if tips == null or controller == null:
		return
	if _panel_open():
		return
	var soul = _soul()
	if soul == null or not is_instance_valid(soul):
		return
	if not bool(soul.get("alive")) or bool(soul.get("downed")):
		return
	var pool := maxf(1.0, float(soul.get("max_health")))
	if float(soul.get("health")) / pool > BANDAGE_LESSON_HEALTH:
		return
	if _hostile_near((soul as Node3D).global_position, BANDAGE_LESSON_RADIUS):
		return
	tips.tip(BANDAGE_LESSON_STEP, str(BANDAGE_LESSON["keys"]), str(BANDAGE_LESSON["text"]))


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


func _on_body_killed(_slot: int, _source: int, actor, merc_id: int) -> void:
	if roguelite != null and roguelite.is_running():
		return
	if not _leave_remains(actor, merc_id):
		drop_merc_gear(actor, merc_id)


## A member of the party below who dies keeps what he still wore - both weapon
## sets, armour, trinkets - on his own body (`WarbandLoot.register_remains`): it is
## never booked for him, the squad leaves it alone, and the party only gets it back
## by looting the corpse. What nobody takes back stays below with him. False for
## any other death, which lets go of its hands as ever.
func _leave_remains(actor, merc_id: int) -> bool:
	if _client or warband == null or merc_id <= 0 or not warband.delve.is_member(merc_id):
		return false
	var kit: Array[String] = []
	for entry in warband.roster.worn_entries(merc_id):
		var item_id: String = warband.roster.take_worn(merc_id, str(entry.get("slot", "")),
			int(entry.get("set", -1)))
		if not item_id.is_empty():
			kit.append(item_id)
	if loot == null or not is_instance_valid(actor) or kit.is_empty():
		return true
	loot.register_remains(actor, kit, warband.roster.name_of(merc_id))
	if hud != null:
		hud.set_status("%s is dead. What he wore is on his body: loot it to take it back." %
			warband.roster.name_of(merc_id), 4.0)
	return true


func _on_pickup_taken(_pickup) -> void:
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
	# A guest's world outlives its loan by a frame or two; past it the roster is
	# this machine's own again, and these bodies are not its mercenaries.
	if _client and not warband.lent:
		return
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
		if _client:
			# The host's books are the ones that reap. A guest mirrors what it can
			# see - health, the downed flag - but never books a death here: that
			# fires `died`, reaps this copy of the books and unregisters a body the
			# host still names, and the next mirror cannot put the router back.
			warband.roster.set_health(merc_id, float(actor.get("health")))
			if bool(actor.get("downed")):
				warband.roster.set_state(merc_id, Contracts.HealthState.DOWNED)
			elif bool(actor.get("alive")):
				warband.roster.set_state(merc_id, Contracts.HealthState.ALIVE)
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
	# The host decides a wipe and reloads its checkpoint; a guest's world follows
	# it there when the host's campaign arrives again.
	if _wiped or _client:
		return
	# An arena run decides its own loss (`RogueliteDirector._tick_down_check`):
	# a wipe on the island would reload a campaign checkpoint under the fight.
	if roguelite != null and roguelite.is_running():
		_wipe_beat = -1.0
		return
	# A party below falls by its own rule (`delve_area.gd`): the bodies left in the
	# town are still standing, and the Hollow - not the checkpoint - decides what a
	# fall costs.
	if warband != null and warband.delve.active:
		_wipe_beat = -1.0
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


# --- the town's silence ----------------------------------------------------
#
# The soundtrack is the wood's: it starts on the first bar of the campaign and
# rides the cages, the trail and every fight on it. The town is where a run ends,
# so the score stops at the square and stays stopped - the keepers, the fire ring
# and the warband talking are the town's own sound.

## Hold the mix to what the place is. Idempotent and asked every frame rather than
## driven from an edge: the manager answers a scene change with its own track, so
## the only way this frame's answer cannot be undone by the next one is to ask
## what the manager wants and correct it.
func _sync_town_music() -> void:
	if audio == null or town == null or controller == null:
		return
	var soul = controller.focus_body()
	if soul == null or not is_instance_valid(soul):
		return
	var track := str(audio.music_track)
	if town.in_square(soul):
		if not track.is_empty():
			audio.stop_music(TOWN_FADE_SECONDS)
		return
	# The band between the square and the wood belongs to neither answer: a body
	# standing on the line keeps the score it already has rather than flickering
	# the whole soundtrack on and off.
	if town.in_square(soul, TOWN_QUIET_MARGIN):
		return
	# Back out of the gate: the trail is still the wood, and it still has a chase
	# in it.
	if track != "warband":
		audio.play_music("warband")


# --- checkpoints (autosave) ------------------------------------------------
#
# Two moments in the campaign begin a new stretch, and each one writes the
# warband's own save with a bookmark: the camp's six watchers down and the squad
# on the road (the tutorial is over, the run starts), and the town square first
# entered. The bookmark only ever moves forward through `CHECKPOINT_ORDER`, so
# walking back and forth does not hammer the disk - and a session that played
# the opening, whose camp still reads as cleared, cannot pull the town bookmark
# back to the trail on the next frame and then forward again on the one after.
# A wipe loads it, and the title's campaign list opens on it.

## The bookmarks in the order the campaign reaches them.
const CHECKPOINT_ORDER := ["trail_start", "town"]

func _check_checkpoints() -> void:
	if warband == null or controller == null or _wiped:
		return
	# A bookmark taken on an island would name a place the campaign's heightfield
	# has never stood on. The run does not write the campaign's line.
	if roguelite != null and roguelite.is_running():
		return
	# A guest does not own the campaign: writing its own bookmark would move the
	# line every machine reloads from to wherever one guest happened to stand.
	if _client:
		return
	# The party's ground: a host watching the last body still checkpoints it.
	var actor = controller.focus_body()
	if actor == null or not is_instance_valid(actor) or not bool(actor.get("alive")):
		return
	# Out on the road: the party has left the square, so the bookmark follows the
	# soul's own feet. A reload puts the squad back where it stood rather than at
	# Hearthstead, and it never drops it inside the wood's own fight.
	if town != null and not town.in_square(actor) and _checkpoint_ahead("trail_start"):
		_save_checkpoint("trail_start", "trail",
			TerrainScript.grounded(actor.global_position), "ON THE ROAD")
		return
	if town != null and town.in_square(actor) and _checkpoint_ahead("town"):
		_save_checkpoint("town", "town", actor.global_position, "HEARTHSTEAD")


## Whether writing `id` moves the bookmark forward. An id the order does not
## know (a hand-edited or older file) is behind every stretch.
func _checkpoint_ahead(id: String) -> bool:
	return CHECKPOINT_ORDER.find(id) > CHECKPOINT_ORDER.find(warband.checkpoint_id())


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

## The square's own dress. A body inside the walls holds the rack's ranged piece;
## a body that walks back out is re-dressed from the roster, so the campaign's
## kit is exactly what it was before the player stepped inside. While a run is
## live the island owns the hands and this does nothing.
func _sync_town_dress() -> void:
	if roguelite == null or controller == null or town == null:
		return
	var running := bool(roguelite.is_running())
	if _roguelite_was_running and not running:
		# The run let the bodies go back to the roster; the square may dress them
		# again on this same frame.
		_town_dressed.clear()
	_roguelite_was_running = running
	if running:
		return
	for body in bodies:
		if not is_instance_valid(body):
			continue
		var inside: bool = bool(town.in_square(body))
		if inside and not _town_dressed.has(body):
			roguelite.dress_body_ranged(body)
			_town_dressed[body] = true
		elif not inside and _town_dressed.has(body):
			_town_dressed.erase(body)
			var merc: int = int(controller.merc_of(body))
			if merc > 0:
				controller.refresh_gear(merc)


## The rack changed the pair: put every body in the square back into the new
## ranged piece on this very frame, rather than waiting for one to walk out and in.
func refresh_town_dress() -> void:
	_town_dressed.clear()
	_sync_town_dress()


## The one `G`: a cage latch in the camp, a counter in the town, a corpse at your
## feet, or a piece of steel lying loose. The camp is asked first, because its
## latches stand in the ground a body walks on - and a camp that refused the press
## (nothing in reach) hands it on rather than eating it.
func _try_interact() -> void:
	var actor = _soul()
	if actor == null or not is_instance_valid(actor):
		if hud != null:
			hud.set_status("The soul is loose. There is nobody to act with.", 2.5)
		return
	# The island's own furniture outranks the wood's counters: a chest, a draft,
	# a portal. A guest's press is a request the host answers.
	if roguelite != null and roguelite.is_running() and roguelite.interact(actor):
		return
	if _client:
		# Latches, counters and the Hollow's mouth are the host's to work: they
		# change its world and its warband. A body at this soul's feet is still
		# the soul's to search, though, and a drop is still a drop - those two
		# travel as intents like a swing and land on the host's ground.
		if loot != null and loot.has_method("corpse_at"):
			var corpse_id: int = loot.corpse_at(actor.global_position, LOOT_REACH)
			if corpse_id != 0 and paperdoll.open_corpse(loot, corpse_id):
				return
		if _nearest_pickup() != null:
			_try_loot()
			return
		if hud != null:
			hud.set_status(GUEST_HANDS_TEXT, 3.0)
		return
	# The wood's own cages stand in the ground the body walks on: one in reach
	# takes the press, and one out of reach hands it on to whatever else is
	# standing here.
	if soldier_cages != null and soldier_cages.interact(actor):
		return
	# The Hollow's mouth in the square, and the rope out of it below.
	if arena != null and arena.try_leave():
		return
	if delve_area != null and delve_area.interact(actor):
		return
	if town != null and not town.interact_at(controller.local_peer_id, actor.global_position).is_empty():
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
	_interaction_status()


## A right click on lootable ground is the loot, not the guard - and it is the
## take itself, at once, with no window and no channel (`WarbandLootHand.take_now`):
## a corpse gives its whole list, a drop gives itself and the pile it fell in, and
## a weapon lying on the dirt is picked up. Nothing is dressed onto the body that
## searched; `K` is the key that puts a piece into a hand.
##
## The world sees the press before the soul controller does (`_input` runs ahead of
## `_unhandled_input`, and consuming the event stops it reaching the guard), so a
## right click with a body or a drop under the crosshair and in the body's reach
## takes it and never raises a guard. Below, in the delve, the same gesture empties
## the container into the delve inventory. A right click with nothing lootable
## there is left alone and raises the guard exactly as before.
##
## "Under the crosshair" is the ray's own answer, not a radius around it: a fighter
## the player is looking at is what the press was for, so the ray's living target
## is handed to the hand and it refuses the loot. A corpse is the exception on
## purpose - it answers `alive` false, so the body you just put down is still a
## click away from being searched.
func _loot_click(event: InputEvent) -> bool:
	if loot_hand == null or controller == null:
		return false
	if not (event is InputEventMouseButton):
		return false
	var mouse := event as InputEventMouseButton
	if not mouse.pressed:
		return false
	if _panel_open() or _reviving or _wiped:
		return false
	var actor = _soul()
	if actor == null or not is_instance_valid(actor):
		return false
	if mouse.button_index == MOUSE_BUTTON_LEFT:
		# The left button is the blade's. Empty hands cannot swing, and a click
		# that does nothing at all is the one report this game keeps getting, so
		# name the missing piece.
		if str(actor.rig.weapon) in ["", "none"] and hud != null:
			hud.set_status("Your hands are empty. Right-click a body to loot one, or equip one on P.", 2.5)
		return false
	if mouse.button_index != MOUSE_BUTTON_RIGHT:
		return false
	var sample: Dictionary = controller.aim_sample()
	var target: Dictionary = loot_hand.target_at(actor, sample.get("point", Vector3.ZERO),
		sample.get("target", null))
	if target.is_empty():
		return false
	if _client:
		# A guest's ground and pool are the host's: the take is one intent here.
		# The host books it for this soul's body and the answer comes back down the
		# session.
		_request_take(target)
		get_viewport().set_input_as_handled()
		return true
	# The take is instant, above and below: a corpse gives its whole list and a
	# drop gives itself and its pile, with nothing dressed onto the body that
	# searched it. `K` is the verb that puts a piece in a hand.
	if loot_hand.take_now(actor, target).is_empty():
		return false
	get_viewport().set_input_as_handled()
	return true


## Send one take to the host for this soul's body. `target` is the hand's own
## resolution (`{kind, corpse_id, pickup}`), so every guest press names the same
## container the local one would have taken. A body is emptied whole; a drop is
## always its own piece (and the host sweeps the pile beside it).
func _request_take(target: Dictionary) -> void:
	var kind := str(target.get("kind", ""))
	if kind == "corpse":
		controller.act("loot", {"kind": "corpse", "corpse": int(target.get("corpse_id", 0)),
			"item": ""})
	elif kind == "drop":
		var pickup = target.get("pickup")
		if pickup == null or not is_instance_valid(pickup):
			return
		controller.act("loot", {"kind": "drop", "item": str(pickup.item_id),
			"at": (pickup as Node3D).global_position})


## The loot window and the hand ask this for a take the guest resolved itself:
## the corpse it lists and the drop under its crosshair are the host's rows.
func request_loot_take(corpse_id: int, item_id: String, at: Vector3,
		all: bool = false) -> void:
	if not _client or controller == null:
		return
	if corpse_id > 0:
		controller.act("loot", {"kind": "corpse", "corpse": corpse_id,
			"item": "" if all else item_id})
	elif not item_id.is_empty():
		controller.act("loot", {"kind": "drop", "item": item_id, "at": at})


## The corpse screen's request hook (`WarbandPaperdoll.corpse_request`), which
## names the take `(corpse_id, item_id, all)`.
func request_corpse_take(corpse_id: int, item_id: String, all: bool) -> void:
	request_loot_take(corpse_id, item_id, Vector3.ZERO, all)


## What `G` says when it found nothing to use.
func _interaction_status() -> void:
	if hud == null:
		return
	hud.set_status("Nothing within reach.", 3.0)


func _nearest_pickup():
	var actor = _soul()
	if actor == null or not is_instance_valid(actor):
		return null
	var best = null
	var best_distance := LOOT_REACH
	for pickup in pickups:
		if not is_instance_valid(pickup) or bool(pickup.collected):
			continue
		var distance: float = actor.global_position.distance_to(pickup.global_position)
		if distance <= best_distance and not pickup.blocked_for(controller.local_peer_id):
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
	if roguelite != null and roguelite.is_running():
		var run_actor = _soul()
		if run_actor != null and is_instance_valid(run_actor):
			roguelite.swap_hands(run_actor)
		return
	if _soul_merc() <= 0:
		if hud != null:
			hud.set_status("The soul is loose. There is nobody to swap for.", 2.5)
		return
	# The swap rides the same channel as a swing: done here on the host, sent to
	# the host by a guest - whose new hands come back with the host's warband.
	controller.act("swap_set")


## `K` still works for a human; the squad loots itself and nothing announces it.
## A guest's press is an intent: the piece is on the host's ground and the pool
## is the host's, so the host takes it for this soul's body and tells everyone.
func _try_loot() -> void:
	var pickup = _nearest_pickup()
	if pickup == null:
		# A blade thrown into a body is a take too: K pulls the nearest one back
		# out of whoever is wearing it, and the piece returns to the shared stash.
		if controller != null and bool(controller.act("loot_stuck")):
			if hud != null:
				hud.set_status("Pulled a blade back out.", 2.0)
			return
		if hud != null:
			hud.set_status("Nothing within reach.", 1.5)
		return
	if _client:
		controller.act("loot", {"kind": "drop", "item": str(pickup.item_id),
			"at": pickup.global_position})
		if hud != null:
			hud.set_status("Taking %s..." % str(pickup.label_text()), 1.5)
		return
	var result: Dictionary = loot.quick_loot(pickup, controller.local_peer_id)
	if bool(result.get("ok", false)):
		controller.refresh_gear(_soul_merc())
	if hud != null:
		hud.set_status(str(result.get("message", "")), 2.5)


## One take the wire asked a body to make. `peer_id` is the ENet sender the
## session read, never a value the guest chose; the body is looked up from the
## router, and the target must be inside that body's reach. Both the drop and the
## corpse paths book through the same vacuum and the same shared pool the host's
## own presses use, so co-op loot can never cost the warband two pieces.
func loot_for_peer(peer_id: int, kind: String, corpse_id: int, item_id: String,
		at: Vector3) -> bool:
	if _client or controller == null or loot == null or peer_id <= 0:
		return false
	var actor = controller.body_for_peer(peer_id)
	if actor == null or not is_instance_valid(actor) \
			or not bool(actor.get("alive")) or bool(actor.get("downed")):
		return false
	if kind == "drop":
		var pickup = _drop_near(at, item_id, LOOT_REACH + 0.75)
		if pickup == null:
			return false
		# `at` travels from the guest and is only a hint: the piece has to be in
		# *this body's* reach, exactly as the corpse branch demands. Without this a
		# guest names any drop's position and takes the host's ground from across
		# the map.
		if (actor as Node3D).global_position.distance_to(
				(pickup as Node3D).global_position) > LOOT_REACH + 0.75:
			return false
		# A take is a take: the piece goes into the pool (the delve's below, the
		# town's above) and nothing is dressed onto the body that searched it. `K`
		# is the armorer's verb, on the press that names a piece.
		var taken: Dictionary = loot.quick_loot(pickup, peer_id, false)
		return bool(taken.get("ok", false))
	if kind != "corpse" or corpse_id <= 0 or not loot.has_corpse(corpse_id):
		return false
	if (actor as Node3D).global_position.distance_to(loot.corpse_position(corpse_id)) \
			> LOOT_REACH + 0.75:
		return false
	# Nothing is dressed onto the taker either way: the pool takes the piece, and
	# `K` is the verb that wears one.
	var result: Dictionary
	if item_id.is_empty():
		result = loot.take_all_from_corpse(corpse_id, peer_id, false)
	elif loot.corpse_items(corpse_id).has(item_id):
		result = loot.take_from_corpse(corpse_id, item_id, peer_id)
	else:
		return false
	return bool(result.get("ok", false))


## The open drop `item_id` names nearest `at`, or null. A guest names a point and
## a piece, never a node: the host's own node is the one that is taken.
func _drop_near(at: Vector3, item_id: String, radius: float):
	if loot == null or not loot.has_method("pickups"):
		return null
	var best = null
	var best_distance := maxf(radius, 0.0)
	for pickup in loot.pickups():
		if not is_instance_valid(pickup) or bool(pickup.get("collected")):
			continue
		if not item_id.is_empty() and str(pickup.get("item_id")) != item_id:
			continue
		var distance: float = (pickup as Node3D).global_position.distance_to(at)
		if distance <= best_distance:
			best_distance = distance
			best = pickup
	return best


# --- revive ----------------------------------------------------------------

func _revive_target():
	return _revive_target_for(_soul())


## The nearest downed squadmate within reach of one body, or null.
func _revive_target_for(actor):
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
	var merc_name: String = warband.roster.name_of(int(controller.merc_of(target)))
	if _client:
		# The host opens the channel on this soul's body; the five seconds are
		# counted here only for the prompt.
		controller.act("revive", true)
		_reviving = true
		_guest_revive = 0.0
		if hud != null:
			hud.set_status("Reviving %s..." % merc_name, Contracts.REVIVE_CHANNEL_SECONDS)
		return
	if revive.begin(controller.local_peer_id, target):
		_reviving = true
		if hud != null:
			hud.set_status("Reviving %s..." % merc_name, Contracts.REVIVE_CHANNEL_SECONDS)
	elif hud != null:
		hud.set_status("That one cannot be brought back.", 2.0)


func _cancel_revive() -> void:
	_reviving = false
	if _client:
		controller.act("revive", false)
	elif revive != null:
		revive.cancel(controller.local_peer_id)


func _tick_revive(delta: float) -> void:
	if revive == null:
		return
	revive.tick(delta)
	if not _reviving:
		return
	if _client:
		_guest_revive += delta
		var share := clampf(_guest_revive / Contracts.REVIVE_CHANNEL_SECONDS, 0.0, 1.0)
		if hud != null:
			hud.set_prompt("REVIVING  %d%%" % int(round(share * 100.0)))
		if share >= 1.0 or _revive_target() == null:
			_reviving = false
		return
	var progress: float = float(revive.progress(controller.local_peer_id))
	if hud != null and progress > 0.0:
		hud.set_prompt("REVIVING  %d%%" % int(round(progress * 100.0)))
	if not revive.channeling(controller.local_peer_id):
		_reviving = false


# --- the branded sigil -----------------------------------------------------

## The sigil belongs to the weapon, not the body: every time the soul changes
## hands, the runner is re-bound to whatever blade that mercenary holds.
func _attach_brand() -> void:
	if branded == null:
		return
	var actor = _soul()
	var merc_id: int = _soul_merc()
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

## The prompt: the counter under the body's nose, then the camp's lesson. It is the
## only standing line the world writes, and it is empty where no place has
## something to say; the key legend that used to sit under it is gone - the lesson
## cards and the tips teach the controls, and nothing on this HUD repeats them
## over a fight.
func _update_prompt() -> void:
	if hud == null or controller == null:
		return
	if _panel_open() or _reviving:
		return
	var actor = _soul()
	var text := ""
	# A body on the floor outranks everything else on screen: the one thing a
	# soul can do for a squadmate is stand over it and hold the key.
	var fallen = _revive_target()
	if fallen != null:
		_write_prompt("HOLD G  ·  PICK UP %s" % warband.roster.name_of(
			int(controller.merc_of(fallen))).to_upper())
		return
	if roguelite != null and roguelite.is_running():
		var line := str(roguelite.prompt_line(actor))
		if line.is_empty():
			var run_state: Dictionary = roguelite.state()
			line = "%s  ·  WAVE %d / %d  ·  %d HOSTILES  ·  TAB swaps hands" % [
				str(run_state.get("biome_name", "")),
				int(run_state.get("wave", 0)), int(run_state.get("waves", 3)),
				int(run_state.get("living", 0))]
		_write_prompt(line)
		return
	# A cage in reach outranks every other line: it is the one thing standing at
	# the body's feet wherever in the wood it is.
	if soldier_cages != null and actor != null and is_instance_valid(actor) \
			and soldier_cages.latch_target(actor) >= 0:
		_write_prompt("G  -  CUT THE LATCH   ·   %d CAGE%s LEFT" % [soldier_cages.remaining(),
			"" if soldier_cages.remaining() == 1 else "S"])
	# The Hollow first: below, its objective is the only line that means anything,
	# and at the mouth it names the way down.
	if delve_area != null:
		text = delve_area.prompt_line(actor)
	# The ring is not on the map: its own fight is the only line worth reading
	# there.
	if arena != null and arena.is_open():
		text = "THE ARENA  ·  %s" % arena.difficulty.to_upper()
	if text.is_empty() and town != null and town.in_square(actor):
		text = town.prompt_line(actor)
	_write_prompt(text)


## The one line under the crosshair. Only the prompt is written: it is the world
## saying an action is available, not a key legend.
func _write_prompt(prompt: String) -> void:
	if hud == null:
		return
	if prompt != _prompt_text:
		_prompt_text = prompt
		hud.set_prompt(prompt)


func prompt_text() -> String:
	return _prompt_text


func _hide_panels() -> void:
	if screen != null and screen.is_open():
		screen.close()
	if paperdoll != null and paperdoll.is_open():
		paperdoll.close()
	if delve_area != null:
		delve_area.close_panels()
	if roguelite_hud != null:
		roguelite_hud.close_all()
	if town != null:
		town.close_panels()


func _panel_open() -> bool:
	# The menu is a panel for the pointer's purposes - it takes the cursor - but
	# Escape closes it through its own branch rather than through `_hide_panels`.
	if menu != null and menu.is_open():
		return true
	if (screen != null and screen.is_open()) or (paperdoll != null and paperdoll.is_open()):
		return true
	if delve_area != null and delve_area.panels_open():
		return true
	if roguelite_hud != null and roguelite_hud.open_panels():
		return true
	return town != null and town.panels_open()


## Escape opens the warband menu. The body keeps standing where it stood, but it
## stops taking commands while the ledger is up: a click on the ledger must never
## swing a weapon. `resumed` restores the body on every way the menu closes.
func _open_menu() -> void:
	if menu == null:
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
	if _client:
		if hud != null:
			hud.set_status("Only the host can load this campaign.", 2.5)
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
	# Nothing in this scene pauses the tree, but a title must never open behind a
	# paused one either way.
	tree.paused = false
	# The flow owns every scene change: this is the title door, and going round it
	# would leave `active` set and a possession pointing at a dead body.
	if flow != null:
		flow.goto(flow.TITLE_SCENE)
	else:
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
# answered from here: the altar, the counters and the stash are the town area's
# own objects, forwarded rather than duplicated.

var altar:
	get:
		return town.altar if town != null else null
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
		"cages_left": soldier_cages.remaining() if soldier_cages != null else 0,
		"cages_freed": soldier_cages.freed() if soldier_cages != null else 0,
		"warcamps": (watcher_warren.camps() as Array).size() if watcher_warren != null else 0,
		"watchers_living": watcher_warren.living() if watcher_warren != null else 0,
		"start": start_area,
		"clearing": wood.clearing.get("clear", Vector2.ZERO) if wood != null else Vector2.ZERO,
		"clearing_trees": int(wood.clearing.get("trees", 0)) if wood != null else 0,
		"clearing_bushes": int(wood.clearing.get("bushes", 0)) if wood != null else 0,
		"clearing_huts": int(wood.clearing.get("huts", 0)) if wood != null else 0,
		"camp_to_road": WoodScript.CAMP_TO_ROAD_METRES,
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


## The deep wood's pocket: a ragged hole in the trees, not a walled yard.
func clearing_size() -> Vector2:
	return wood.clearing.get("clear", Vector2.ZERO) if wood != null else Vector2.ZERO


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


# --- startup ---------------------------------------------------------------

## Where the campaign puts this body down: Hearthstead for a fresh run, a saved
## checkpoint for a resumed one, or the host's field for a guest.
func _wanted_start() -> String:
	if flow == null:
		return "town"
	var wanted := str(flow.world_start)
	if wanted == "guest" and _client:
		return "guest"
	if wanted == "checkpoint":
		return "checkpoint" if warband != null and warband.has_checkpoint() else "town"
	return "town" if wanted == "town" else "town"


## Say what the world was built from, once, in one line: the start it opened on,
## the bodies and hostiles it fields, the lane it grew and the ground under it. A
## harness reads this line back to prove the world it asked for is the one built.
func _announce() -> void:
	var readout: Dictionary = stats()
	print("WARBAND_WORLD_READY start=%s bodies=%d guards=%d lane=%.1f road=%.0fm torches=%d trees=%d nodes=%d draws=%d shapes=%d ground=%.1f..%.1fm/%d tris"
		% [start_area, bodies.size(), guards.size(), float(readout["lane_length"]),
			float(readout["camp_to_road"]), int(readout["torches"]),
			int(readout["clearing_trees"]) + int(readout["town_wood"]),
			int(readout["nodes"]), int(readout["draws"]), int(readout["shapes"]),
			float(readout["height_min"]), float(readout["height_max"]),
			int(readout["terrain_tris"])])
