extends Node3D
## The persistent town hub: a dusk square where the warband musters between
## expeditions.
##
## It is the loop's home end. The five sworn mercenaries stand around the fire as
## real `ArenaActor` bodies under the real `PossessionController`, the local soul
## starts inside the first of them, and every service the loop needs is a node
## you can walk up to: the shared stash chest (the paperdoll over the collective
## pool), the `SacrificialAltar`, the Gold recruiter's desk (the warband screen's
## recruiter board) and the `ExpeditionGate` that marks a battle line and asks
## the flow owner for the arena. The same objects are used by the admin arena, so
## nothing here re-implements a service; this scene only places them and resolves
## which one a standing body is next to (`interact_at`).
##
## There is no combat and no second damage multiplier: unpossessed bodies are
## fixtures (`set_bot(false)`), so the square never brawls on its own.

const ControllerScript = preload("res://scripts/warband/possession_controller.gd")
const ClearingScript = preload("res://scripts/warband/camp_clearing.gd")
const RunForestScript = preload("res://scripts/warband/run_forest.gd")
const VillageKit = preload("res://scripts/world/village_kit.gd")
const GateScript = preload("res://scripts/warband/expedition_gate.gd")
const QuartermasterScript = preload("res://scripts/warband/quartermaster_menu.gd")
const HudScript = preload("res://scripts/warband/warband_hud.gd")
const ScreenScript = preload("res://scripts/warband/warband_screen.gd")
const PaperdollScript = preload("res://scripts/warband/warband_paperdoll.gd")
const AltarScript = preload("res://scripts/warband/sacrificial_altar.gd")
const Geo = preload("res://scripts/geo.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const State = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const WarbandState = preload("res://scripts/warband/warband_state.gd")

## How close a body must stand to the chest, the desk and the altar. The gate
## keeps its own (larger) `open_radius`.
const SERVICE_REACH := 3.0
const WALL_RADIUS := 18.0
## The gap in the north wall the trail comes in through.
const NORTH_GATE_HALF := 5.0
## How far a body may stray from the fire in the standalone square.
const BODY_BOUNDS := 16.0
## How deep the wood the settlement is cut into runs outside its walls.
const WOOD_DEPTH := 20.0
const TOWN_WOOD_SEED := 7717

## The four services, arranged so no two rings overlap: walking the square always
## names exactly one thing.
const STASH_POINT := Vector3(-8.0, 0.0, 4.0)
const ALTAR_POINT := Vector3(8.0, 0.0, 4.0)
const RECRUITER_POINT := Vector3(-8.0, 0.0, -6.0)
const QUARTERMASTER_POINT := Vector3(0.0, 0.0, -12.0)
const GATE_POINT := Vector3(8.0, 0.0, -6.0)
const SIGN_POINT := Vector3(2.0, 0.0, 9.0)

## Muster ring around the fire: one post per body the round can field.
const SPAWN_POSTS := [
	Vector3(-3.0, 0.0, 3.0), Vector3(-1.2, 0.0, 4.2), Vector3(0.8, 0.0, 4.4),
	Vector3(2.6, 0.0, 3.2), Vector3(3.4, 0.0, 1.0), Vector3(-4.4, 0.0, 1.2),
	Vector3(4.2, 0.0, -1.2), Vector3(-3.6, 0.0, -1.6),
]

## The first-run warband: the same identical bodies the arena fields, in plain
## dusk gear, so the town is playable before a single battle. An existing
## warband is left exactly as it is.
const TOWN_LINEUP := [
	{"name": "Aldous", "main": "sword_short", "off": "shield_buckler", "armor": "leather"},
	{"name": "Brine", "main": "dagger_iron", "off": "shield_kite", "armor": "mail"},
	{"name": "Cael", "main": "bow_short", "off": "", "armor": "cloth"},
	{"name": "Dorn", "main": "sword_great", "off": "", "armor": "plate"},
	{"name": "Edda", "main": "sword_arming", "off": "shield_tower", "armor": "mail"},
]

## Spares the collective stash starts with, so the paperdoll and the altar have
## something to move before the first battle is fought.
const TOWN_SPARES := [
	"sword_arming", "shield_buckler", "bow_short", "focus_skull", "focus_tome",
	"armor_leather_head", "armor_leather_chest", "ring_copper", "ring_health",
	"dagger_ironwood", "club_makeshift", "branch_heavy", "shield_wood",
]

## The town's one door: the expedition gate asks to be replaced and the scene
## forwards it, so the game-flow owner binds a single signal per scene.
signal scene_requested(path: String)

## The world scene that embeds this town, or null when the town stands alone.
## Set before the node enters the tree.
##
## Embedded, the town is the far end of one continuous world: the world owns the
## bodies, the camera, the HUD and the night, the town's north wall is the gate
## the trail comes in through, and the square is cut into the same wood the
## clearing stands in. Alone, this is the square as its own scene - the preview
## the art and quartermaster regressions load.
var host: Node3D = null

var warband: WarbandState
var camera: Camera3D
var controller
var hud: WarbandHud
var screen: WarbandScreen
var paperdoll: WarbandPaperdoll
var altar: SacrificialAltar
var gate: GateScript
var stash_chest: Node3D
var recruiter_desk: Node3D
var quartermaster_desk: Node3D
var quartermaster
var signpost: Node3D
## The treeline around the square: `{trees, bushes, wall}` from the wood planner.
var wood: Dictionary = {}
var fire_light: OmniLight3D
var flame: MeshInstance3D
var bodies: Array = []

var _stone: StandardMaterial3D
var _wood: StandardMaterial3D
var _earth: StandardMaterial3D
var _ash: StandardMaterial3D
var _ember: StandardMaterial3D

func _ready() -> void:
	warband = get_node_or_null("/root/Warband") as WarbandState
	if warband == null:
		push_error("TownHub needs the Warband autoload")
		return
	_build_materials()
	if host == null:
		seed_warband()
		_build_environment()
	_build_square()
	if host == null:
		_build_body_layer()
	_build_services()
	_build_wood()
	if host == null:
		_build_ui()
		controller.possession_changed.connect(_on_possession_changed)
		controller.transfer_refused.connect(_on_transfer_refused)
		controller.possession_released.connect(_on_possession_released)
		_enter_first_body()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var flow := get_node_or_null("/root/GameFlow")
		if flow != null:
			flow.bind(self)
		print("TOWN_HUB_READY bodies=%d gold=%d" % [bodies.size(), warband.gold()])


## Adopt the pieces the world owns. The world calls this once, after the town is
## in the tree and before the warband is placed here.
func embed(world: Node3D) -> void:
	host = world
	warband = world.warband
	controller = world.controller
	hud = world.hud
	screen = world.screen
	paperdoll = world.paperdoll
	if gate != null:
		gate.setup(warband, controller)


## Where the warband stands when the campaign starts in the town.
func spawn_posts() -> Array[Vector3]:
	return _spawn_points()


## Seat the bodies the world spawned around the fire. The square shows the whole
## living warband, so a battle line left behind by a previous expedition is
## cleared here and written again at the gate.
func place_warband(bodies_in: Array) -> void:
	warband.roster.clear_deployment()
	bodies = bodies_in
	for actor in bodies:
		if not is_instance_valid(actor):
			continue
		var merc_id := int(controller.merc_of(actor))
		var index := bodies.find(actor)
		var post: Vector3 = SPAWN_POSTS[index % SPAWN_POSTS.size()]
		actor.global_position = global_position + post
		actor.spawn_point = global_position + post
		# The square is not a battle: an unpossessed bot would pick the nearest
		# mercenary as a target and brawl around the fire.
		controller.set_bot(merc_id, false)


## Embedded, the world steps the bodies and writes the one HUD: the square only
## answers questions about what stands where.
func _physics_process(delta: float) -> void:
	if controller == null or host != null:
		return
	controller.physics_step(delta)
	_update_prompt()
	_update_hint()

func _process(_delta: float) -> void:
	if host != null:
		return
	var wanted := Input.MOUSE_MODE_VISIBLE if _panel_open() else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != wanted:
		Input.mouse_mode = wanted

func _unhandled_input(event: InputEvent) -> void:
	if host != null:
		return
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
		KEY_G:
			_try_interact()
			get_viewport().set_input_as_handled()

# --- the square ------------------------------------------------------------

func _build_materials() -> void:
	_stone = Geo.material(Color(0.25, 0.235, 0.22), 0.0, 0.92)
	_wood = Geo.material(Color(0.20, 0.14, 0.09), 0.0, 0.85)
	_earth = Geo.material(Color(0.12, 0.105, 0.09), 0.0, 0.97)
	_ash = Geo.material(Color(0.09, 0.08, 0.075), 0.0, 1.0)
	_ember = StandardMaterial3D.new()
	_ember.albedo_color = Color(0.98, 0.62, 0.22)
	_ember.emission_enabled = true
	_ember.emission = Color(1.0, 0.52, 0.14)
	_ember.emission_energy_multiplier = 2.6

## Dusk: a dark, vignetted square lit by the fire and the gate lamps, with enough
## fog to turn the far wall into a silhouette instead of a texture.
func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.075, 0.115)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.42, 0.40, 0.47)
	environment.ambient_light_energy = 0.45
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.16, 0.15, 0.21)
	environment.fog_light_energy = 0.85
	environment.fog_density = 0.035
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.name = "DuskSky"
	world_env.environment = environment
	add_child(world_env)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.56, 0.63, 0.86)
	moon.light_energy = 0.38
	moon.rotation_degrees = Vector3(-46.0, 32.0, 0.0)
	add_child(moon)

func _build_square() -> void:
	_build_ground()
	_build_walls()
	_build_campfire()

func _build_ground() -> void:
	# The world scene owns one floor for the whole map; a second slab under the
	# square would only z-fight with it.
	if host == null:
		var ground := StaticBody3D.new()
		ground.name = "Ground"
		add_child(ground)
		var slab := BoxShape3D.new()
		slab.size = Vector3(WALL_RADIUS * 2.4, 0.6, WALL_RADIUS * 2.4)
		var shape := CollisionShape3D.new()
		shape.shape = slab
		shape.position = Vector3(0.0, -0.3, 0.0)
		ground.add_child(shape)
		Geo.box(ground, slab.size, Vector3(0.0, -0.3, 0.0), _earth)
	# Worn flagstones: the middle of the square is paved, the ring stays dirt.
	Geo.box(self, Vector3(23.0, 0.08, 19.0), Vector3(0.0, 0.02, 0.0), _stone)

## The square's edge. Three sides are the settlement's wall; the fourth - the
## north side, the one the trail comes in through - is two stubs and the gate
## frame a body walks between. That is the whole difference between the town as a
## room and the town as the far end of the wood.
func _build_walls() -> void:
	var span := WALL_RADIUS * 2.0 + 1.4
	_wall(Vector3(0.0, 0.0, -WALL_RADIUS), span, 0.0)
	_wall(Vector3(-WALL_RADIUS, 0.0, 0.0), span, PI * 0.5)
	_wall(Vector3(WALL_RADIUS, 0.0, 0.0), span, PI * 0.5)
	var stub := (WALL_RADIUS + 0.7 - NORTH_GATE_HALF)
	_wall(Vector3(-(NORTH_GATE_HALF + stub * 0.5), 0.0, WALL_RADIUS), stub, 0.0)
	_wall(Vector3(NORTH_GATE_HALF + stub * 0.5, 0.0, WALL_RADIUS), stub, 0.0)
	_build_north_gate()

func _wall(at: Vector3, span: float, yaw: float) -> void:
	var side := Node3D.new()
	side.name = "Wall%d" % get_child_count()
	side.position = at
	side.rotation.y = yaw
	add_child(side)
	var z := 0.0
	Geo.box(side, Vector3(span, 1.8, 0.7), Vector3(0.0, 0.9, z), _stone)
	Geo.box(side, Vector3(span, 0.22, 1.0), Vector3(0.0, 1.9, z), _wood)
	for step in int(span / 6.0) + 1:
		var x := -span * 0.5 + 6.0 * float(step)
		if absf(x) > span * 0.5:
			continue
		Geo.cylinder(side, 0.22, 0.18, 3.4, Vector3(x, 1.7, z), _wood, 8)
	var body := StaticBody3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(span, 3.4, 0.7)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(0.0, 1.7, z)
	body.add_child(shape)
	side.add_child(body)

## The gate the trail comes in through: the village kit's own frame, so the town
## reads as a settlement cut into the same world as the clearing it began in.
func _build_north_gate() -> void:
	var gate := Node3D.new()
	gate.name = "NorthGate"
	gate.position = Vector3(0.0, 0.0, WALL_RADIUS)
	add_child(gate)
	var body := StaticBody3D.new()
	body.name = "GateCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	gate.add_child(body)
	VillageKit.gate(gate, VillageKit.materials(), body, NORTH_GATE_HALF, 4.6, 19)
	var label := Label3D.new()
	label.name = "GateSign"
	label.text = "THE WOOD ROAD"
	label.font_size = 56
	label.pixel_size = 0.006
	label.modulate = Color(0.96, 0.82, 0.56)
	label.position = Vector3(0.0, 4.9, 0.2)
	gate.add_child(label)

## The wood the settlement is cut into: the same treeline the clearing has, with
## one gap where the road comes in.
func _build_wood() -> void:
	var solids := StaticBody3D.new()
	solids.name = "TownWoodCollision"
	solids.collision_layer = 1
	solids.collision_mask = 0
	add_child(solids)
	var mouth := Rect2(-NORTH_GATE_HALF - 1.5, WALL_RADIUS - 2.0,
		(NORTH_GATE_HALF + 1.5) * 2.0, WOOD_DEPTH + 12.0)
	wood = ClearingScript.plant_wood(self, RunForestScript.night_style(),
		Rect2(-WALL_RADIUS, -WALL_RADIUS, WALL_RADIUS * 2.0, WALL_RADIUS * 2.0),
		WOOD_DEPTH, [mouth], [], TOWN_WOOD_SEED, solids, "TownWood")

func _build_campfire() -> void:
	var fire := Node3D.new()
	fire.name = "Campfire"
	add_child(fire)
	Geo.cylinder(fire, 1.15, 1.05, 0.16, Vector3(0.0, 0.08, 0.0), _ash, 16)
	for index in 8:
		var angle := TAU * float(index) / 8.0
		Geo.sphere(fire, 0.16, Vector3(cos(angle) * 1.05, 0.16, sin(angle) * 1.05),
			_stone, Vector3(1.0, 0.8, 1.0))
	for index in 3:
		var angle := TAU * float(index) / 3.0
		Geo.beam(fire, Vector3(cos(angle) * 0.5, 0.22, sin(angle) * 0.5),
			Vector3(0.0, 0.35, 0.0), 0.07, _wood, 6)
	flame = Geo.cylinder(fire, 0.34, 0.0, 1.05, Vector3(0.0, 0.62, 0.0), _ember, 10)
	var core := StandardMaterial3D.new()
	core.albedo_color = Color(1.0, 0.86, 0.55)
	core.emission_enabled = true
	core.emission = Color(1.0, 0.82, 0.5)
	core.emission_energy_multiplier = 3.4
	Geo.cylinder(fire, 0.16, 0.0, 0.62, Vector3(0.0, 0.5, 0.0), core, 8)
	fire_light = OmniLight3D.new()
	fire_light.name = "FireLight"
	fire_light.light_color = Color(1.0, 0.62, 0.28)
	fire_light.light_energy = 2.4
	fire_light.omni_range = 12.0
	fire_light.omni_attenuation = 1.4
	fire_light.position = Vector3(0.0, 1.1, 0.0)
	add_child(fire_light)

# --- bodies ----------------------------------------------------------------

func _build_body_layer() -> void:
	camera = Camera3D.new()
	camera.name = "TownCamera"
	camera.current = true
	camera.fov = 59.0
	camera.near = 0.08
	camera.far = 140.0
	camera.position = Vector3(0.0, 4.5, 13.0)
	add_child(camera)
	controller = ControllerScript.new()
	controller.name = "Soul"
	controller.auto_simulate = false
	add_child(controller)
	controller.setup(warband, camera, self)
	# The square is the muster ground: it shows the whole living warband, so a
	# battle line a previous expedition left behind is cleared here and written
	# again at the gate.
	warband.roster.clear_deployment()
	bodies = controller.spawn_mercenaries(_spawn_points(), true)
	for actor in bodies:
		if not is_instance_valid(actor):
			continue
		actor.global_position = actor.spawn_point + Vector3(0.0, 0.1, 0.0)
		actor.bounds = BODY_BOUNDS
		# Town bodies are fixtures, not bots: an unpossessed bot would pick the
		# nearest mercenary as a target and brawl around the fire.
		controller.set_bot(int(controller.merc_of(actor)), false)

func _spawn_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for post in SPAWN_POSTS:
		points.append(post)
	return points

func _enter_first_body() -> void:
	var ids: Array[int] = controller.living_merc_ids()
	if ids.is_empty():
		return
	controller.direct(1, ids[0])
	_refresh_hud()

func _on_possession_changed(peer_id: int, merc_id: int) -> void:
	if peer_id == 1:
		_refresh_hud()
		hud.set_status("%s takes the soul." % warband.roster.name_of(merc_id), 2.0)

func _on_transfer_refused(_peer_id: int, merc_id: int, reason: String) -> void:
	hud.set_status("%s: %s" % [warband.roster.name_of(merc_id), reason], 3.0)

func _on_possession_released(_peer_id: int, reason: String) -> void:
	hud.set_body(null, "", -1)
	hud.set_status("The soul is loose (%s)." % reason, 4.0)

func _on_possess_requested(merc_id: int) -> void:
	screen.close()
	controller.direct(1, merc_id)
	_refresh_hud()

func _refresh_hud() -> void:
	var merc_id := int(controller.merc_for_peer(1))
	hud.set_body(controller.active_body(1), warband.roster.name_of(merc_id), merc_id)

# --- services --------------------------------------------------------------

func _build_services() -> void:
	altar = AltarScript.new()
	altar.name = "SacrificialAltar"
	altar.position = ALTAR_POINT
	add_child(altar)

	stash_chest = _build_stash_chest()
	recruiter_desk = _build_recruiter_desk()
	quartermaster_desk = _build_quartermaster_desk()
	signpost = _build_signpost()

	gate = GateScript.new()
	gate.name = "ExpeditionGate"
	gate.position = GATE_POINT
	add_child(gate)
	gate.setup(warband, controller)
	# The square has exactly one door, whatever asks to leave by it.
	gate.scene_requested.connect(func(path: String): scene_requested.emit(path))
	# The keeper's counter is a service, not scenery of the HUD: the world embeds
	# the square without building the town's own panels.
	quartermaster = QuartermasterScript.new()
	quartermaster.name = "Quartermaster"
	add_child(quartermaster)
	quartermaster.configure(warband)
	preload("res://scripts/warband/town_dressing.gd").build(self)

func _build_stash_chest() -> Node3D:
	var chest := Node3D.new()
	chest.name = "StashChest"
	chest.position = STASH_POINT
	add_child(chest)
	var iron := Geo.material(Color(0.30, 0.29, 0.28), 0.6, 0.55)
	Geo.box(chest, Vector3(1.5, 0.8, 0.95), Vector3(0.0, 0.4, 0.0), _wood)
	Geo.box(chest, Vector3(1.62, 0.24, 1.02), Vector3(0.0, 0.9, 0.0), _wood)
	for x in [-0.6, 0.6]:
		Geo.box(chest, Vector3(0.12, 0.86, 1.04), Vector3(x, 0.45, 0.0), iron)
	Geo.box(chest, Vector3(0.22, 0.24, 0.1), Vector3(0.0, 0.62, 0.52), iron)
	chest.add_child(_label("STASH", Vector3(0.0, 1.45, 0.0), Color(0.95, 0.78, 0.48)))
	return chest

func _build_recruiter_desk() -> Node3D:
	var desk := Node3D.new()
	desk.name = "RecruiterDesk"
	desk.position = RECRUITER_POINT
	add_child(desk)
	var iron := Geo.material(Color(0.28, 0.27, 0.26), 0.55, 0.6)
	Geo.box(desk, Vector3(2.0, 0.12, 0.9), Vector3(0.0, 0.92, 0.0), _wood)
	for x in [-0.82, 0.82]:
		Geo.box(desk, Vector3(0.14, 0.86, 0.8), Vector3(x, 0.43, 0.0), _wood)
	# The ledger and the purse: this is a place where names and gold are traded.
	Geo.box(desk, Vector3(0.46, 0.06, 0.34), Vector3(-0.45, 1.01, 0.0),
		Geo.material(Color(0.55, 0.52, 0.44), 0.0, 0.95))
	Geo.box(desk, Vector3(0.2, 0.1, 0.2), Vector3(0.55, 1.03, 0.0), iron)
	var lamp := OmniLight3D.new()
	lamp.name = "DeskLamp"
	lamp.light_color = Color(1.0, 0.72, 0.42)
	lamp.light_energy = 1.1
	lamp.omni_range = 5.0
	lamp.position = Vector3(0.0, 1.5, 0.0)
	desk.add_child(lamp)
	desk.add_child(_label("RECRUITER", Vector3(0.0, 1.7, 0.0), Color(0.96, 0.74, 0.42)))
	return desk

## The keeper's counter: plain steel into the collective stash for gold. The
## desk is the recruiter's twin, so the square reads as one market.
func _build_quartermaster_desk() -> Node3D:
	var desk := Node3D.new()
	desk.name = "QuartermasterDesk"
	desk.position = QUARTERMASTER_POINT
	add_child(desk)
	Geo.box(desk, Vector3(2.0, 0.12, 0.9), Vector3(0.0, 0.92, 0.0), _wood)
	for x in [-0.82, 0.82]:
		Geo.box(desk, Vector3(0.14, 0.86, 0.8), Vector3(x, 0.43, 0.0), _wood)
	Geo.box(desk, Vector3(0.5, 0.08, 0.24), Vector3(-0.35, 1.02, 0.0),
		Geo.material(Color(0.42, 0.44, 0.46), 0.7, 0.35))
	Geo.box(desk, Vector3(0.24, 0.24, 0.3), Vector3(0.5, 1.06, 0.0),
		Geo.material(Color(0.55, 0.44, 0.28), 0.3, 0.7))
	var lamp := OmniLight3D.new()
	lamp.name = "DeskLamp"
	lamp.light_color = Color(0.78, 0.84, 1.0)
	lamp.light_energy = 0.95
	lamp.omni_range = 5.0
	lamp.position = Vector3(0.0, 1.5, 0.0)
	desk.add_child(lamp)
	desk.add_child(_label("QUARTERMASTER", Vector3(0.0, 1.7, 0.0), Color(0.78, 0.86, 0.96)))
	return desk

func _build_signpost() -> Node3D:
	var post := Node3D.new()
	post.name = "Signpost"
	post.position = SIGN_POINT
	add_child(post)
	Geo.cylinder(post, 0.13, 0.11, 3.0, Vector3(0.0, 1.5, 0.0), _wood, 8)
	var board := Geo.material(Color(0.24, 0.17, 0.11), 0.0, 0.9)
	Geo.box(post, Vector3(2.4, 1.1, 0.1), Vector3(0.0, 2.35, 0.0), board)
	var text := _label("THE SQUARE\nSTASH   ALTAR\nRECRUITER   GATE",
		Vector3(0.0, 2.35, 0.08), Color(0.94, 0.88, 0.76))
	text.font_size = 48
	text.pixel_size = 0.0045
	post.add_child(text)
	return post

func _label(text: String, at: Vector3, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.006
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.position = at
	return label

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

# --- interaction -----------------------------------------------------------

## The one `G` handler: which service the standing body is next to.
func _try_interact() -> void:
	var actor = controller.active_body(1)
	if actor == null or not is_instance_valid(actor):
		hud.set_status("No body to act with.", 2.0)
		return
	if interact_at(1, actor.global_position).is_empty():
		hud.set_status("Nothing to use here.", 1.5)

## Resolve and use whichever service `point` is next to. Returns `"stash"`,
## `"altar"`, `"recruiter"`, `"gate"` or `""`, which is what a single `G` handler
## and the regression both drive instead of guessing at positions.
func interact_at(peer_id: int, point: Vector3) -> String:
	var service := service_at(point)
	match service:
		"stash":
			_hide_panels()
			paperdoll.open(controller.merc_for_peer(peer_id))
			hud.set_status("The shared stash is open: click a free piece to wear it.", 4.0)
		"altar":
			_hide_panels()
			altar.interact(peer_id)
			hud.set_status("The altar drinks.", 2.5)
		"recruiter":
			_hide_panels()
			screen.open()
			var hint := "Hire from the recruiter board: HIRE swears a new body for gold."
			screen.set_status(hint)
			hud.set_status(hint, 5.0)
		"quartermaster":
			_hide_panels()
			quartermaster.open()
			hud.set_status("The quartermaster sells plain steel into the shared stash.", 4.0)
		"gate":
			var gate_state: Dictionary = gate.prompt(peer_id)
			hud.set_status(str(gate_state.get("message", "")), 5.0)
	return service

## Whether a body is standing on the square's ground at all (the walls plus a
## stride): what decides whether the town's key line or the trail's is the one
## worth showing.
func in_square(actor) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var local: Vector3 = actor.global_position - global_position
	return absf(local.x) <= WALL_RADIUS + 2.0 and absf(local.z) <= WALL_RADIUS + 2.0


## Whether one of the square's panels is open (the world owns the input, the
## square owns the panels it opens).
func panels_open() -> bool:
	return _panel_open()


## Close whatever the square opened, for the world's one `ESC` and `TAB`.
func close_panels() -> void:
	_hide_panels()


## The nearest service whose ring holds `point`, or `""`.
func service_at(point: Vector3) -> String:
	var entries: Array[Dictionary] = [
		{"id": "stash", "point": stash_chest.global_position, "reach": SERVICE_REACH},
		{"id": "altar", "point": altar.global_position, "reach": altar.interact_range},
		{"id": "recruiter", "point": recruiter_desk.global_position, "reach": SERVICE_REACH},
		{"id": "quartermaster", "point": quartermaster_desk.global_position, "reach": SERVICE_REACH},
		{"id": "gate", "point": gate.global_position, "reach": gate.open_radius},
	]
	var best := ""
	var best_distance := INF
	for entry in entries:
		var target: Vector3 = entry["point"]
		var distance := point.distance_to(target)
		if distance <= float(entry["reach"]) and distance < best_distance:
			best_distance = distance
			best = str(entry["id"])
	return best

## Where a service stands, so a caller can walk to it without reading the scene.
func service_point(service: String) -> Vector3:
	match service:
		"stash":
			return stash_chest.global_position
		"altar":
			return altar.global_position
		"recruiter":
			return recruiter_desk.global_position
		"quartermaster":
			return quartermaster_desk.global_position
		"gate":
			return gate.global_position
	return Vector3.ZERO

## A paperdoll change has to reach the body standing in the square, or the
## mercenary keeps the old kit in the only place the player can see it.
func _on_paperdoll_changed() -> void:
	if paperdoll == null or paperdoll.selected_merc <= 0:
		return
	controller.refresh_gear(paperdoll.selected_merc)

## The key line for the square. The town is where a player learns the two screens,
## so it always names them, plus whatever counter the body is standing at.
var _hint_text := ""

## The key line for the square, or "" when the body is nowhere near a counter.
## The world writes it to the one HUD; a town standing alone writes it itself.
func hint_line(actor) -> String:
	var service := ""
	if actor != null and is_instance_valid(actor):
		service = service_at(actor.global_position)
	var text := "TAB - warband   ·   P - stash and gear   ·   G - use what you stand at"
	match service:
		"stash":
			text = "G - shared stash and paperdoll   ·   TAB - warband"
		"altar":
			text = "G - the Sacrificial Altar (unbind / distil / brand)"
		"recruiter":
			text = "G - hire a new body for gold (up to the cap)"
		"quartermaster":
			text = "G - buy plain steel into the shared stash"
		"gate":
			text = "G - launch an expedition with the line you deployed"
	return text


## The crosshair prompt for the counter the body stands at, or "".
func prompt_line(actor) -> String:
	if actor == null or not is_instance_valid(actor):
		return ""
	match service_at(actor.global_position):
		"stash":
			return "G - shared stash"
		"altar":
			return "G - Sacrificial Altar"
		"recruiter":
			return "G - Gold recruiter"
		"quartermaster":
			return "G - quartermaster"
		"gate":
			return "G - expedition gate"
	return ""


func _update_hint() -> void:
	if hud == null or controller == null:
		return
	var text := hint_line(controller.active_body(1))
	if text != _hint_text:
		_hint_text = text
		hud.set_hint(text)

func _update_prompt() -> void:
	if hud == null:
		return
	if _panel_open():
		hud.set_prompt("")
		return
	hud.set_prompt(prompt_line(controller.active_body(1)))

func _hide_panels() -> void:
	if screen != null and screen.is_open():
		screen.close()
	if paperdoll != null and paperdoll.is_open():
		paperdoll.close()
	if altar != null and altar.is_open():
		altar.close()
	if quartermaster != null and quartermaster.is_open():
		quartermaster.close()

func _panel_open() -> bool:
	return (screen != null and screen.is_open()) \
		or (paperdoll != null and paperdoll.is_open()) \
		or (altar != null and altar.is_open()) \
		or (quartermaster != null and quartermaster.is_open())

# --- seeding ---------------------------------------------------------------

## A first-run warband, so the square is playable before an expedition. An
## existing warband (from a save or the camp) is never touched. The world calls
## this only when the campaign starts in the town; a camp start has already
## dressed its prisoners.
func seed_warband() -> void:
	if not warband.roster.is_empty():
		return
	for entry in TOWN_LINEUP:
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
	for item_id in TOWN_SPARES:
		if State.ITEMS.has(str(item_id)):
			warband.stash.add(str(item_id), 1)
	warband.cruor.add(Contracts.CruorTier.T1_RITUAL_TALLOW, 25)
	warband.cruor.add(Contracts.CruorTier.T2_BLACK_BILE, 10)
	warband.cruor.add(Contracts.CruorTier.T3_COAGULATED_CRUOR, 5)
