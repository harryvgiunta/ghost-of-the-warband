extends Node3D
## Admin Level / Play Arena for Ghost of the Warband.
##
## The verification surface for the whole overhaul, and a playable sandbox: the
## eight mercenaries of the warband stand in the old duel field, two of them
## waiting for human souls and the other six split into two three-body brawls
## forty metres apart. That is the shape the bubble rule exists for: the brawl a
## player stands in is real, the one across the field is a convincing 10%
## background fight until somebody walks over to it.
##
## Everything here is assembled from the merged pieces rather than reimplemented:
## `PossessionController` owns the bodies, `WarbandBubbleManager` decides 100% or
## 10%, `PassiveDuelBrain` plays the far fight, `ReviveChannel` holds the five
## second channel, `WarbandLoot` sweeps the field and the altar/stash/screens are
## the same objects the town hub will use.

const WorldScript = preload("res://scripts/arena_world.gd")
const ControllerScript = preload("res://scripts/warband/possession_controller.gd")
const BubbleScript = preload("res://scripts/warband/combat_bubble.gd")
const BrainScript = preload("res://scripts/warband/passive_duel_brain.gd")
const HudScript = preload("res://scripts/warband/warband_hud.gd")
const ScreenScript = preload("res://scripts/warband/warband_screen.gd")
const PaperdollScript = preload("res://scripts/warband/warband_paperdoll.gd")
const LootScript = preload("res://scripts/warband/loot_vacuum.gd")
const AltarScript = preload("res://scripts/warband/sacrificial_altar.gd")
const CrawlScript = preload("res://scripts/warband/crawl_to_safety.gd")
const ReviveScript = preload("res://scripts/warband/revive_channel.gd")
const BrandedScript = preload("res://scripts/warband/branded_runner.gd")
const WavesScript = preload("res://scripts/warband/enemy_waves.gd")
const SessionScript = preload("res://scripts/warband/warband_session.gd")
const LootRunScript = preload("res://scripts/warband/soldier_loot_run.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Damage = preload("res://scripts/warband/damage_scaler.gd")
const State = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")

## The two sparring posts. Forty two metres apart: outside the 34 m bubble exit
## radius, so neither group starts hot, and both are inside the 33 m field.
const SQUAD_A := Vector3(-24.0, 0.0, -10.0)
const SQUAD_B := Vector3(24.0, 0.0, -10.0)
const PLAYER_POSTS := [Vector3(0.0, 0.0, 20.0), Vector3(2.5, 0.0, 20.0)]
const SQUAD_SIZE := 3
const STASH_POINT := Vector3(4.0, 0.0, 18.0)
const ALTAR_POINT := Vector3(-4.0, 0.0, 18.0)
const LOOT_REACH := 2.6
const INTERACT_REACH := 3.0
const TOWN_SCENE := "res://scenes/town_hub.tscn"
## Three waves and a breathing gap: enough to read as an expedition, short enough
## that the loop can be walked in a few minutes.
const MAX_WAVES := 3
const WAVE_GAP := 2.5
## What a dead cultist leaves behind, in rotation.
const GUARD_LOOT := ["sword_arming", "shield_kite", "armor_mail_chest", "ring_blood", "bow_recurve"]

## The scene asks to be replaced (town after an expedition, the arena after a
## deployment). The game-flow owner connects this; the scene never loads itself.
signal scene_requested(path: String)

## The eight trial mercenaries: identical bodies, different gear. Two of them
## carry a legal off hand for the human souls, the rest are line troops.
const LINEUP := [
	{"name": "Aldous", "main": "sword_short", "off": "shield_buckler", "armor": "leather"},
	{"name": "Brine", "main": "dagger_iron", "off": "shield_kite", "armor": "mail"},
	{"name": "Cael", "main": "bow_short", "off": "", "armor": "cloth"},
	{"name": "Dorn", "main": "sword_great", "off": "", "armor": "plate"},
	{"name": "Edda", "main": "sword_arming", "off": "shield_tower", "armor": "mail"},
	{"name": "Fenwick", "main": "sword_short", "off": "dagger_iron", "armor": "leather"},
	{"name": "Grist", "main": "sword_short", "off": "shield_buckler", "armor": "makeshift"},
	{"name": "Hale", "main": "sword_short", "off": "focus_tome", "armor": "leather"},
]

## Spares the collective stash starts with, so the paperdoll and the altar have
## something to do before the first battle is fought.
const SPARES := [
	"sword_arming", "shield_buckler", "bow_short", "focus_skull", "focus_tome",
	"staff_fire", "armor_leather_head", "armor_leather_chest", "ring_copper",
	"ring_health", "dagger_makeshift", "sword_makeshift",
]

var warband
var world
var camera: Camera3D
var controller
var bubble
var hud
var screen
var paperdoll
var altar
var loot
var revive
var branded
var stash_crate: Node3D
var bodies: Array = []
var brains: Array = []
var duel_pairs: Array = []   # [[body, opponent], ...] the brains are playing
var crawls: Array = []
var groups: Array = []
var _reviving := false
var _battle_over := false
var _check_elapsed := 0.0
var _loot_spawned := false
## True while the line troops fight each other. Turning it off parks their own AI
## (the passive brains still guard and trade the occasional swing), which is how
## a test - or an admin - makes the field deterministic.
var sparring := true
var bot_mercs: Array[int] = []
## A real battle (deployed line, cultist waves) instead of the sandbox brawls.
var expedition := false
var waves
var loot_run
var session
var _next_wave_elapsed := -1.0
var _guard_loot_cursor := 0
## Set while the end-of-battle loot run is walking the field.
var _loot_running := false
var _roster_sync_elapsed := 0.0

func _ready() -> void:
	warband = get_node_or_null("/root/Warband")
	if warband == null:
		push_error("AdminArena needs the Warband autoload")
		return
	_seed_warband()
	# A deployment line in the warband means this is an expedition; an empty one
	# means the sandbox. The town's gate is what writes the line.
	expedition = not warband.deployed_merc_ids().is_empty()
	world = WorldScript.new()
	world.name = "Arena"
	add_child(world)
	camera = Camera3D.new()
	camera.name = "AdminCamera"
	camera.current = true
	camera.fov = 59
	camera.near = 0.08
	camera.far = 180.0
	camera.position = Vector3(0, 14, 30)
	add_child(camera)
	camera.look_at(Vector3(0, 1, 0))
	controller = ControllerScript.new()
	controller.name = "Soul"
	controller.auto_simulate = false
	add_child(controller)
	controller.setup(warband, camera, self)
	if expedition:
		bodies = controller.spawn_mercenaries(_muster_points(), true)
		_layout_muster()
	else:
		bodies = controller.spawn_mercenaries(_spawn_points(), true)
		_layout_groups()
	_wire_bubble()
	_wire_brains()
	_wire_crawl()
	revive = ReviveScript.new()
	revive.name = "Revive"
	add_child(revive)
	revive.set_bodies(bodies)
	loot = LootScript.new()
	loot.name = "Loot"
	add_child(loot)
	loot.setup(warband, self)
	_spawn_battlefield_loot()
	_build_services()
	_build_ui()
	branded = BrandedScript.new()
	branded.name = "Branded"
	add_child(branded)
	controller.possession_changed.connect(_on_possession_changed)
	controller.transfer_refused.connect(_on_transfer_refused)
	controller.possession_released.connect(_on_possession_released)
	var first := _player_mercenary(0)
	if first > 0:
		controller.direct(1, first)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.bind(self)
	_boot_session()
	print("ADMIN_ARENA_READY bodies=%d groups=%d bubble=%.0f" % [bodies.size(), groups.size(),
		bubble.bubble_radius if bubble != null else 0.0])

## Two friends on one field. A warband battle is launched with
## `--warband-host <port>` on the host and `--warband-join <address> <port>` on the
## guest; both machines must load the same warband save, exactly as the arena's
## seats already require a shared roster. The session owns the wire, this scene
## keeps owning the field.
func _boot_session() -> void:
	var args := OS.get_cmdline_user_args()
	var host_port := _arg_after(args, "--warband-host")
	var join_at := args.find("--warband-join")
	if host_port <= 0 and join_at < 0:
		return
	session = SessionScript.new()
	session.name = "WarbandSession"
	add_child(session)
	session.setup(controller, warband)
	session.peer_joined.connect(func(peer_id: int):
		print("ADMIN_ARENA_PEER joined=%d" % peer_id)
		_update_humans())
	session.peer_left.connect(func(peer_id: int):
		print("ADMIN_ARENA_PEER left=%d" % peer_id)
		_update_humans())
	session.ownership_changed.connect(func(_map: Dictionary): _update_humans())
	if host_port > 0:
		session.host(host_port, "Host")
		if hud != null:
			hud.set_status("Hosting a warband battle on UDP %d" % host_port, 6.0)
		print("ADMIN_ARENA_SESSION host port=%d" % host_port)
		return
	var address := str(args[join_at + 1]) if join_at + 1 < args.size() else "127.0.0.1"
	var port := int(args[join_at + 2]) if join_at + 2 < args.size() else 7779
	session.join(address, port, "Guest")
	if hud != null:
		hud.set_status("Joining %s:%d" % [address, port], 6.0)
	print("ADMIN_ARENA_SESSION join address=%s port=%d" % [address, port])

func _arg_after(args: PackedStringArray, flag: String) -> int:
	var index := args.find(flag)
	if index < 0 or index + 1 >= args.size():
		return 0
	return int(args[index + 1])

func _exit_tree() -> void:
	if session != null:
		session.leave()
	if warband != null:
		warband.save_state()

func _physics_process(delta: float) -> void:
	if controller == null:
		return
	# The brains own a fighter's intents for this frame, so they must write them
	# before the controller integrates the body.
	# A passive fighter's brain chooses stance and swings, but the body still has
	# to look at its opponent for those swings to matter: the scene owns the aim
	# because only it knows the pairing.
	for pair in duel_pairs:
		var body = pair[0]
		var foe = pair[1]
		if is_instance_valid(body) and is_instance_valid(foe) and Damage.is_passive(body):
			body.combat.set_aim(foe.get_aim_position())
	if expedition:
		if waves != null:
			waves.step(delta, bodies)
		if _next_wave_elapsed > 0.0:
			_next_wave_elapsed -= delta
			if _next_wave_elapsed <= 0.0:
				_next_wave_elapsed = -1.0
				_start_wave(int(waves.wave()) + 1)
	for brain in brains:
		if is_instance_valid(brain):
			brain.step(delta)
	controller.physics_step(delta)
	_sync_roster(delta)
	_update_humans()
	_tick_revive(delta)
	_update_prompt()
	_check_battle_end(delta)

## Mirror the live bodies into the roster, so the warband screen shows real
## health and downed state during the battle and the next scene loads the truth.
func _sync_roster(delta: float) -> void:
	_roster_sync_elapsed += delta
	if _roster_sync_elapsed < 0.4:
		return
	_roster_sync_elapsed = 0.0
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

func _process(_delta: float) -> void:
	var panel_open: bool = _panel_open()
	var wanted := Input.MOUSE_MODE_VISIBLE if panel_open else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != wanted:
		Input.mouse_mode = wanted

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
			_try_quick_loot()
			get_viewport().set_input_as_handled()
		KEY_G:
			_try_interact()
			get_viewport().set_input_as_handled()
		KEY_B:
			_end_battle("You call the field.")
			get_viewport().set_input_as_handled()
		KEY_R:
			_activate_brand()
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			_request_return()
			get_viewport().set_input_as_handled()

## The revive key needs to win over the arena's quick-step binding, so the key
## event is consumed here before any body-level command sees it.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.echo or event.keycode != KEY_E:
		return
	if event.pressed:
		if _reviving or _revive_target() != null:
			_begin_revive()
			get_viewport().set_input_as_handled()
	else:
		if _reviving:
			_cancel_revive()
			get_viewport().set_input_as_handled()

# --- setup -----------------------------------------------------------------

func _spawn_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for index in SQUAD_SIZE:
		points.append(SQUAD_A + Vector3(-2.2 + 1.1 * index, 0.0, -2.6 + 2.6 * index))
	for index in SQUAD_SIZE:
		points.append(SQUAD_B + Vector3(-2.2 + 1.1 * index, 0.0, -2.6 + 2.6 * index))
	for post in PLAYER_POSTS:
		points.append(post)
	return points

## Put the roster's order on the field: the first three hold one post, the next
## three the other, and the last two are the human souls' bodies.
func _layout_groups() -> void:
	groups = [[], []]
	var spots: Array[Vector3] = _spawn_points()
	for index in bodies.size():
		var actor = bodies[index]
		if not is_instance_valid(actor):
			continue
		var spot: Vector3 = spots[index % spots.size()]
		actor.global_position = spot + Vector3(0, 0.1, 0)
		actor.spawn_point = spot
		actor.bounds = 31.0
		if index < SQUAD_SIZE:
			groups[0].append(actor)
		elif index < SQUAD_SIZE * 2:
			groups[1].append(actor)
	for index in bodies.size():
		var merc_id: int = controller.merc_of(bodies[index])
		if merc_id <= 0:
			continue
		if index < SQUAD_SIZE * 2:
			bot_mercs.append(merc_id)
		controller.set_bot(merc_id, index < SQUAD_SIZE * 2)

## Park or release the line troops' own AI. The passive brains keep playing their
## guard-and-circle choreography either way; this only stops them attacking.
func set_sparring(enabled: bool) -> void:
	sparring = enabled
	_apply_bot_flags()
	if not enabled:
		for actor in bodies:
			if is_instance_valid(actor):
				actor.combat.stop()
				actor.move_direction = Vector2.ZERO

func _apply_bot_flags() -> void:
	for merc_id in bot_mercs:
		controller.set_bot(int(merc_id), sparring)

## Where a deployed line musters: a short rank in front of the altar, so the
## whole warband stands inside one bubble at the start of the battle.
func _muster_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for index in maxi(1, warband.deployed_merc_ids().size()):
		points.append(Vector3(-5.0 + 2.4 * index, 0.0, 16.0))
	return points

func _layout_muster() -> void:
	var spots := _muster_points()
	for index in bodies.size():
		var actor = bodies[index]
		if not is_instance_valid(actor):
			continue
		var spot: Vector3 = spots[index % spots.size()]
		actor.global_position = spot + Vector3(0, 0.1, 0)
		actor.spawn_point = spot
		actor.bounds = 31.0
		var merc_id: int = controller.merc_of(actor)
		if merc_id > 0:
			controller.set_bot(merc_id, false)

## The cult half of the field: guards walk in from the far treeline.
func _wave_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for index in 8:
		var x := -21.0 + float(index % 4) * 14.0
		var z := -18.0 - float(index / 4) * 4.0
		points.append(Vector3(x, 0.0, z))
	return points

func _wire_waves() -> void:
	waves = WavesScript.new()
	waves.name = "Waves"
	add_child(waves)
	waves.setup(controller, self, _wave_points(), Callable(self, "warband_bodies"))
	waves.wave_started.connect(_on_wave_started)
	waves.wave_cleared.connect(_on_wave_cleared)
	_start_wave(0)

## The warband as the cult sees it (EnemyWaves asks for this when stepped empty).
func warband_bodies() -> Array:
	var out: Array = []
	for actor in bodies:
		if is_instance_valid(actor) and bool(actor.get("alive")):
			out.append(actor)
	return out

func _start_wave(index: int) -> void:
	if waves == null:
		return
	var spawned: Array = waves.start_wave(index)
	for guard in spawned:
		if is_instance_valid(guard):
			guard.killed.connect(_on_guard_killed.bind(guard))

func _on_wave_started(index: int, count: int) -> void:
	if hud != null:
		hud.set_status("Wave %d of %d - %d cultists" % [index + 1, MAX_WAVES, count], 3.0)

func _on_wave_cleared(index: int) -> void:
	if index + 1 >= MAX_WAVES:
		_end_battle("The expedition is cleared.")
		return
	_next_wave_elapsed = WAVE_GAP
	if hud != null:
		hud.set_status("Wave %d broken. They are coming again." % (index + 1), WAVE_GAP)

## A dead cultist leaves its kit on the ground for the survivors to walk to.
func _on_guard_killed(_slot: int, _source: int, guard) -> void:
	if not is_instance_valid(guard):
		return
	var item_id := str(GUARD_LOOT[_guard_loot_cursor % GUARD_LOOT.size()])
	_guard_loot_cursor += 1
	loot.spawn(item_id, guard.global_position + Vector3(0.35, 0.0, 0.35))

func _player_mercenary(index: int) -> int:
	var ids: Array = controller.living_merc_ids()
	var slot := SQUAD_SIZE * 2 + index
	if slot < ids.size():
		return int(ids[slot])
	return int(ids[ids.size() - 1]) if not ids.is_empty() else -1

func _wire_bubble() -> void:
	bubble = BubbleScript.new()
	bubble.name = "Bubble"
	add_child(bubble)
	bubble.setup()
	for actor in bodies:
		bubble.track(actor)
	if expedition:
		_wire_waves()
	_update_humans()

func _update_humans() -> void:
	if bubble == null:
		return
	var humans: Array = []
	var local_body = controller.active_body(1) if controller != null else null
	if local_body != null:
		humans.append(local_body)
	var remote_body = controller.body_for_peer(2) if controller != null else null
	if remote_body != null and remote_body != local_body:
		humans.append(remote_body)
	bubble.set_humans(humans)

## One brain per duellist, paired inside its own brawl. The brain decides stance
## and exchange cadence; the bubble decides whether that stance is passive at all.
func _wire_brains() -> void:
	for group in groups:
		for index in group.size():
			var actor = group[index]
			var opponent = group[(index + 1) % group.size()]
			if actor == opponent:
				continue
			var brain = BrainScript.new()
			brain.name = "DuelBrain"
			add_child(brain)
			brain.attach(actor, opponent)
			brains.append(brain)
			duel_pairs.append([actor, opponent])

## Let the brains play their guard-and-circle stance, or hand the bodies back
## their own behaviour. A test turns them off to make the field deterministic.
func set_choreography(enabled: bool) -> void:
	for brain in brains:
		if is_instance_valid(brain):
			brain.set_active(not enabled)
	# Releasing a brain hands the body back to its own AI, so the arena's own
	# sparing flag has to win again or a parked field starts fighting.
	if not enabled:
		_apply_bot_flags()

func _wire_crawl() -> void:
	for actor in bodies:
		var crawl = CrawlScript.new()
		crawl.name = "Crawl"
		add_child(crawl)
		crawl.attach(actor)
		crawls.append(crawl)
	for group in groups:
		var friends: Array = []
		for actor in group:
			friends.append(actor)
		for actor in group:
			for crawl in crawls:
				if crawl.actor == actor:
					crawl.set_friends(friends)

func _spawn_battlefield_loot() -> void:
	if _loot_spawned:
		return
	_loot_spawned = true
	var drops := [
		["sword_arming", SQUAD_A + Vector3(4.0, 0.0, 4.0)],
		["shield_kite", SQUAD_B + Vector3(-4.0, 0.0, 4.0)],
		["bow_short", Vector3(0.0, 0.0, 4.0)],
		["armor_mail_chest", Vector3(3.0, 0.0, 10.0)],
		["ring_blood", Vector3(-3.0, 0.0, 10.0)],
	]
	for drop in drops:
		loot.spawn(str(drop[0]), drop[1])

func _build_services() -> void:
	altar = AltarScript.new()
	altar.name = "SacrificialAltar"
	altar.position = ALTAR_POINT
	add_child(altar)
	stash_crate = Node3D.new()
	stash_crate.name = "StashChest"
	stash_crate.position = STASH_POINT
	add_child(stash_crate)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.4, 0.9, 0.9)
	mesh.mesh = box
	mesh.position.y = 0.45
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.28, 0.20, 0.12)
	mesh.material_override = material
	stash_crate.add_child(mesh)
	var label := Label3D.new()
	label.text = "STASH"
	label.position = Vector3(0.0, 1.25, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	stash_crate.add_child(label)

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

# --- possession ------------------------------------------------------------

func _on_possession_changed(peer_id: int, merc_id: int) -> void:
	if hud != null and peer_id == 1:
		var actor = controller.active_body(1)
		hud.set_body(actor, warband.roster.name_of(merc_id), merc_id)
	_attach_brand()
	_update_humans()
	_refresh_marker()

## The sigil belongs to the item, not the body: every time the soul changes
## hands, the runner is re-bound to whatever weapon that mercenary actually holds.
func _attach_brand() -> void:
	if branded == null:
		return
	var actor = controller.active_body(1)
	var merc_id: int = controller.merc_for_peer(1)
	if actor == null or merc_id <= 0:
		branded.attach(null, {})
		return
	var main_id: String = str(warband.roster.equipped_of(merc_id).get("main", ""))
	branded.attach(actor, warband.cruor.brand_of(main_id))

func _activate_brand() -> void:
	if branded == null:
		return
	var status: Dictionary = branded.can_activate()
	if not bool(status.get("ok", false)):
		if hud != null:
			hud.set_status(str(status.get("reason", "No brand.")), 2.0)
		return
	if branded.activate():
		var payload: Dictionary = branded.brand()
		if hud != null:
			hud.set_status(str(payload.get("ability", "")), 1.5)

func _on_transfer_refused(_peer_id: int, merc_id: int, reason: String) -> void:
	if hud != null:
		hud.set_status("%s: %s" % [warband.roster.name_of(merc_id), reason])

func _on_possession_released(_peer_id: int, reason: String) -> void:
	if hud != null:
		hud.set_body(null, "", -1)
		hud.set_status("The warband is down (%s)" % reason, 4.0)
	_update_humans()

func _on_possess_requested(merc_id: int) -> void:
	screen.close()
	controller.direct(1, merc_id)
	_refresh_marker()

func _hide_panels() -> void:
	if screen != null and screen.is_open():
		screen.close()
	if paperdoll != null and paperdoll.is_open():
		paperdoll.close()
	if altar != null and altar.is_open():
		altar.close()

func _panel_open() -> bool:
	return (screen != null and screen.is_open()) \
		or (paperdoll != null and paperdoll.is_open()) \
		or (altar != null and altar.is_open())

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
		var name: String = warband.roster.name_of(int(controller.merc_of(target)))
		hud.set_status("Reviving %s..." % name, Contracts.REVIVE_CHANNEL_SECONDS)
	else:
		hud.set_status("That one cannot be brought back.", 2.0)

func _cancel_revive() -> void:
	_reviving = false
	if revive != null:
		revive.cancel(1)

func _tick_revive(delta: float) -> void:
	if revive == null:
		return
	var status: Dictionary = revive.tick(delta)
	if _reviving:
		var progress := float((status.get("progress", {}) as Dictionary).get(1, 0.0))
		if hud != null and progress > 0.0:
			hud.set_prompt("REVIVING  %d%%" % int(round(progress * 100.0)))
		if not revive.channeling(1):
			_reviving = false

# --- interaction -----------------------------------------------------------

func _try_quick_loot() -> void:
	var actor = controller.active_body(1)
	if actor == null:
		return
	var nearest = null
	var best := LOOT_REACH
	for pickup in loot.pickups():
		if not is_instance_valid(pickup) or bool(pickup.collected):
			continue
		var distance: float = actor.global_position.distance_to(pickup.global_position)
		if distance <= best and not pickup.blocked_for(1):
			best = distance
			nearest = pickup
	if nearest == null:
		hud.set_status("Nothing within reach.", 1.5)
		return
	var result: Dictionary = loot.quick_loot(nearest, 1)
	hud.set_status(str(result.get("message", "")), 2.0)

func _try_interact() -> void:
	var actor = controller.active_body(1)
	if actor == null:
		return
	if altar != null and altar.in_reach(actor.global_position):
		altar.interact(1)
		return
	if stash_crate != null and actor.global_position.distance_to(stash_crate.global_position) <= INTERACT_REACH:
		paperdoll.open(controller.merc_for_peer(1))
		return
	hud.set_status("Nothing to use here.", 1.5)

func _update_prompt() -> void:
	if hud == null:
		return
	if _reviving:
		return
	var target = _revive_target()
	if target != null:
		hud.set_prompt("Hold E - revive %s" % warband.roster.name_of(int(controller.merc_of(target))))
		return
	var actor = controller.active_body(1)
	if actor != null:
		for pickup in loot.pickups():
			if is_instance_valid(pickup) and not bool(pickup.collected) \
					and actor.global_position.distance_to(pickup.global_position) <= LOOT_REACH:
				hud.set_prompt("K - loot %s" % str(pickup.label_text()))
				return
		if altar != null and altar.in_reach(actor.global_position):
			hud.set_prompt("G - Sacrificial Altar")
			return
		if stash_crate != null and actor.global_position.distance_to(stash_crate.global_position) <= INTERACT_REACH:
			hud.set_prompt("G - shared stash")
			return
	if branded != null:
		var ready: Dictionary = branded.can_activate()
		if bool(ready.get("ok", false)):
			hud.set_prompt("R - %s" % str(branded.brand().get("ability", "")))
			return
	hud.set_prompt("")

# --- battle ----------------------------------------------------------------

## The battle is over when no brawler is left standing. The survivors walk the
## field and the vacuum takes everything into the shared stash.
func _check_battle_end(delta: float) -> void:
	if _battle_over or expedition or groups.is_empty():
		return
	_check_elapsed += delta
	if _check_elapsed < 0.5:
		return
	_check_elapsed = 0.0
	var standing := 0
	for group in groups:
		standing += _standing_count(group)
	if standing > 0:
		return
	_end_battle("The field is quiet.")

func _standing_count(group: Array) -> int:
	var count := 0
	for actor in group:
		if is_instance_valid(actor) and bool(actor.get("alive")) and not bool(actor.get("downed")):
			count += 1
	return count

func _end_battle(reason: String) -> void:
	if _battle_over:
		return
	_battle_over = true
	var survivors: Array = []
	for body in bodies:
		if is_instance_valid(body) and bool(body.get("alive")) and not bool(body.get("downed")):
			survivors.append(body)
	# A real expedition ends with the survivors physically walking the field
	# before the vacuum books what they pick up; the sandbox books it at once.
	if expedition and not _loot_running and not loot.pickups().is_empty():
		_loot_running = true
		loot_run = LootRunScript.new()
		loot_run.name = "LootRun"
		add_child(loot_run)
		loot_run.setup(warband, loot, survivors)
		loot_run.finished.connect(_on_loot_run_finished.bind(survivors))
		loot_run.run(loot.pickups())
		if hud != null:
			hud.set_status("%s  The survivors are looting the field." % reason, 6.0)
		return
	var sweep: Dictionary = loot.sweep(survivors)
	if hud != null:
		hud.set_status("%s  %d items gathered." % [reason, int(sweep.get("collected", 0))], 6.0)
	if screen != null:
		screen.refresh()

func _on_loot_run_finished(collected: int, survivors: Array) -> void:
	_loot_running = false
	var sweep: Dictionary = loot.sweep(survivors)
	if hud != null:
		hud.set_status("%d items gathered, %d left on the field." % [
			collected + int(sweep.get("collected", 0)), loot.pickups().size()], 6.0)
	if screen != null:
		screen.refresh()

## Leave the field: the town after a battle, a refusal before it.
func _request_return() -> void:
	if not _battle_over:
		if hud != null:
			hud.set_status("Finish the field first.", 2.0)
		return
	scene_requested.emit(TOWN_SCENE)

func _refresh_marker() -> void:
	if hud != null:
		var merc_id: int = controller.merc_for_peer(1)
		hud.set_body(controller.active_body(1), warband.roster.name_of(merc_id), merc_id)

# --- seeding ---------------------------------------------------------------

## A first-run warband: eight bodies with distinct kits, a handful of spares and
## enough essence to try every altar verb. An existing warband is left alone.
func _seed_warband() -> void:
	if not warband.roster.is_empty():
		return
	for entry in LINEUP:
		var merc_id: int = warband.add_mercenary(str(entry["name"]))
		var main_id := str(entry["main"])
		var off_id := str(entry["off"])
		warband.roster.equip(merc_id, "main", main_id)
		if not Contracts.two_handed_item(State.ITEMS.get(main_id, {})) and not off_id.is_empty():
			warband.roster.equip(merc_id, "off", off_id)
		var set_id := str(entry["armor"])
		for slot in ArmorData.SLOTS:
			var armor_id := "armor_%s_%s" % [set_id, slot]
			if State.ITEMS.has(armor_id):
				warband.roster.equip(merc_id, slot, armor_id)
	for item_id in SPARES:
		warband.stash.add(str(item_id), 1)
	warband.cruor.add(Contracts.CruorTier.T1_RITUAL_TALLOW, 25)
	warband.cruor.add(Contracts.CruorTier.T2_BLACK_BILE, 10)
	warband.cruor.add(Contracts.CruorTier.T3_COAGULATED_CRUOR, 5)
	# One brand on the line, so the new verb is discoverable on the first body a
	# player is handed and the altar has something to reroll.
	warband.cruor.brand("sword_short", Contracts.CruorTier.T3_COAGULATED_CRUOR)
