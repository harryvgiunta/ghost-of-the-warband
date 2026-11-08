extends Node3D
## The campaign's first town: a stockade settlement on the north road.
##
## It is the loop's home end. A leaning stake ring stands on the field with one
## gap cut for the road, an antler gate in the gap, and the settlement behind it:
## stick longhouses with their backs to the stakes, round wattle dwellings, an
## open stall, the wardens' offering ground, and a fire in the middle of it all.
## The five sworn mercenaries stand around that fire as real `WarbandBody` bodies
## under the real `PossessionController`, the local soul starts inside the first
## of them, and every service the loop needs is a node you can walk up to: the
## shared stash chest, the `SacrificialAltar` (where a warden's ichor wakes a
## weapon into its skill), the Gold recruiter's booth, the quartermaster's shop,
## and the three keepers' counters (Orla, Brann, Vey).
##
## Behind every counter stands a keeper - an armoured humanoid, one of the five
## who run this place - and every one of them is a `G` away: there is no board of
## orders and no arrow over a head, because the town sells, buys and forges and
## has nothing to ask of anybody. Three archers of the watch hold the gate and
## shoot what comes up the road at it.
##
## There is no combat in the square itself: nothing hostile is fielded inside the
## stakes. The watch is the one armed thing here, and it only ever aims outward,
## at the world's own hostiles.
##
## Nothing here re-implements a service; this scene only places them and resolves
## which one a standing body is next to (`interact_at`).

const ControllerScript = preload("res://scripts/warband/possession_controller.gd")
const ClearingScript = preload("res://scripts/warband/camp_clearing.gd")
const RunForestScript = preload("res://scripts/warband/run_forest.gd")
const VillageKit = preload("res://scripts/world/village_kit.gd")
const SignKit = preload("res://scripts/world/sign_kit.gd")
const TerrainScript = preload("res://scripts/warband/terrain.gd")
const QuartermasterScript = preload("res://scripts/warband/quartermaster_menu.gd")
const VendorMenuScript = preload("res://scripts/warband/vendor_menu.gd")
const HudScript = preload("res://scripts/warband/warband_hud.gd")
const ScreenScript = preload("res://scripts/warband/warband_screen.gd")
const PaperdollScript = preload("res://scripts/warband/warband_paperdoll.gd")
const AltarScript = preload("res://scripts/warband/sacrificial_altar.gd")
const ArenaMenuScript = preload("res://scripts/warband/arena_menu.gd")
const Geo = preload("res://scripts/geo.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const State = preload("res://scripts/player_state.gd")
const WarbandState = preload("res://scripts/warband/warband_state.gd")
const VoiceScript = preload("res://scripts/audio/voice.gd")
const FireFx = preload("res://scripts/world/fire_fx.gd")
const FolkScript = preload("res://scripts/warband/town_folk.gd")
const GuardScript = preload("res://scripts/warband/town_guard.gd")
const DressingScript = preload("res://scripts/warband/town_dressing.gd")
const Perf = preload("res://scripts/perf_probe.gd")
const ForgePanelScript = preload("res://scripts/roguelite/town_forge_panel.gd")

## How close a body must stand to the chest and the desks. The altar keeps its own
## `interact_range`.
const SERVICE_REACH := 3.0
## The town is a ring now, not a room: this is the stake wall a body stands
## inside, and the dressing mirrors it so the two can never drift apart.
const WALL_RADIUS := 22.0
## The gap in the north wall the trail comes in through.
const NORTH_GATE_HALF := 5.0
## The stakes' lean, the gate's height and the seed the ring is rebuilt from.
const GATE_HEIGHT := 4.6
## Where the gate's name board hangs: east of the hide banner in the middle of the
## span, inside the posts.
const SIGN_BOARD_X := 2.7
const GATE_SEED := 19
const WALL_SEED := 7719
## The angles the stake ring is cut at: the road in on the +Z axis, and two
## shoulders either side of it so the whole gate frame stands in the clear rather
## than among the last stakes.
const GATE_GAPS := [-0.05, 0.0, 0.05]
## How far a body may stray from the fire in the standalone square.
const BODY_BOUNDS := 20.0
## How deep the wood the settlement is cut into runs outside its walls.
const WOOD_DEPTH := 20.0
const TOWN_WOOD_SEED := 7717
## How often the gold arrow re-reads who has business. The ledger moves without a
## signal when the world counts a kill, so a slow clock is the only honest way to
## ask again.
## Where the arrow hangs: over the name, high enough to clear the tallest rig.

## The square's standing services, arranged so no two 3 m rings overlap: walking
## the square always names exactly one thing.
const STASH_POINT := Vector3(-8.0, 0.0, 4.0)
const ALTAR_POINT := Vector3(8.0, 0.0, 4.0)
const RECRUITER_POINT := Vector3(-8.0, 0.0, -6.0)
const QUARTERMASTER_POINT := Vector3(0.0, 0.0, -12.0)
const SIGN_POINT := Vector3(2.0, 0.0, 9.0)
## The arena's gate: a stone arch out on the east lane, clear of every counter.
const ARENA_POINT := Vector3(17.0, 0.0, -4.0)
## The arena loop's three fixtures, in the muster ring's line so a fresh body
## walks out of the fire and straight into them.
const TOTEM_POINT := Vector3(-5.5, 0.0, -1.5)
const RACK_POINT := Vector3(5.5, 0.0, -1.5)
const RUN_PORTAL_POINT := Vector3(0.0, 0.0, -8.0)

## The paved middle of the square: its size, the size of one laid stone, and how
## far the outer stones wander in and out of the course.
const PAVING_SIZE := Vector2(30.0, 26.0)
const PAVING_CELL := 0.92
const PAVING_RAGGED := 0.09
const PAVING_SEED := 4217
## The three keepers' counters, out on the market ring. Each keeps its own 3 m
## ring clear of every other service (the closest pair is Orla and the stash at
## 6.3 m), and all three stand inside the square's walkable bound so a body can
## always reach the stall it wants: Orla's bow rack west, Brann's anvil east,
## Vey's armour table at the back of the square.
const VENDOR_ORLA_POINT := Vector3(-14.0, 0.0, 2.0)
const VENDOR_BRANN_POINT := Vector3(14.0, 0.0, 0.0)
const VENDOR_VEY_POINT := Vector3(7.0, 0.0, -14.0)
## The three stalls in the order `State.VENDORS` and the counters below keep them.
const VENDOR_SERVICES := ["vendor_orla", "vendor_brann", "vendor_vey"]
## The keeper behind each counter, by the service `interact_at` resolves. This is
## the town's side of the dialogue: `VoiceLibrary.VOICES` holds what they say and
## `greet`/`done` are the two moments the square gives them - being walked up to,
## and taking your coin. A keeper with no recordings says nothing.
const KEEPER_VOICES := {
	"vendor_orla": "orla",
	"vendor_brann": "brann",
	"vendor_vey": "vey",
	"quartermaster": "quartermaster",
}

## The settlement inside the stakes: five timber halls, two round dwellings and
## an open stall, every one of them with its doorway to the fire and its back to
## the wall. The positions are solved against the service rings, the muster posts
## and the gate lane - the regression holds them to it - and the seeds pick a
## side-clutter variant that stays inside each hall's own plot.
const BUILDINGS := [
	{"name": "OrlaStore", "kind": "keeper", "at": Vector3(-13.60, 0.0, 11.01),
		"seed": 1301},
	{"name": "BrannSmithy", "kind": "keeper", "at": Vector3(14.66, 0.0, 8.81),
		"seed": 1307},
	{"name": "VeyArmoury", "kind": "keeper", "at": Vector3(13.67, 0.0, -9.93),
		"seed": 1313},
	{"name": "RecruiterHall", "kind": "keeper", "at": Vector3(-15.37, 0.0, -6.53),
		"seed": 1319},
	{"name": "QuartermasterHall", "kind": "keeper", "at": Vector3(-8.65, 0.0, -14.98),
		"seed": 1331},
	{"name": "NorthDwelling", "kind": "wattle", "at": Vector3(-8.60, 0.0, 16.20),
		"seed": 1901},
	{"name": "SouthDwelling", "kind": "wattle", "at": Vector3(0.64, 0.0, -18.29),
		"seed": 1907},
	{"name": "MarketStall", "kind": "frame", "at": Vector3(8.10, 0.0, 15.20),
		"seed": 1913},
]

## The wardens' own furniture, in the plots the halls left free: two totems
## framing the road in, the town's woodpile and drying rack behind the halls, a
## bound effigy on the wall's far side, and the offering ground in the north-west
## pocket between the stash and the gate lane.
const VILLAGE_PROPS := [
	{"name": "GateTotemWest", "kind": "totem", "at": Vector3(-5.0, 0.0, 18.75),
		"seed": 4301, "height": 4.4},
	{"name": "GateTotemEast", "kind": "totem", "at": Vector3(5.25, 0.0, 18.5),
		"seed": 4303, "height": 4.0},
	{"name": "Woodpile", "kind": "woodpile", "at": Vector3(-14.75, 0.0, -13.0),
		"seed": 4307},
	{"name": "DryingRack", "kind": "rack", "at": Vector3(-17.0, 0.0, 6.0),
		"seed": 4311},
	{"name": "BoundEffigy", "kind": "effigy", "at": Vector3(11.0, 0.0, -14.75),
		"seed": 4313},
	{"name": "OfferingGround", "kind": "offering", "at": Vector3(-5.5, 0.0, 9.75),
		"seed": 4317, "yaw": 30.0},
]

## The watch's posts: two archers at the shoulders of the gate - clear of the
## lane a body walks - and a third standing back inside the west post. All three
## have the gap in the stakes in front of them, because that is what a post at
## the gate is for. The gate is the only place a hostile can reach the wall, so
## it is the only post.
const GUARD_POSTS := [
	{"at": Vector3(-4.6, 0.0, 20.6), "yaw": PI},
	{"at": Vector3(4.6, 0.0, 20.6), "yaw": PI},
	{"at": Vector3(-4.2, 0.0, 16.2), "yaw": PI},
]

## Muster ring around the fire: one post per body the round can field.
const SPAWN_POSTS := [
	Vector3(-3.0, 0.0, 3.0), Vector3(-1.2, 0.0, 4.2), Vector3(0.8, 0.0, 4.4),
	Vector3(2.6, 0.0, 3.2), Vector3(3.4, 0.0, 1.0), Vector3(-4.4, 0.0, 1.2),
	Vector3(4.2, 0.0, -1.2), Vector3(-3.6, 0.0, -1.6),
]

## Spares the collective stash starts with, so the paperdoll and the altar have
## something to move from the first minute.
const TOWN_SPARES := [
	"sword_arming", "shield_buckler", "bow_short", "focus_skull", "focus_tome",
	"armor_leather_head", "armor_leather_chest", "ring_copper", "ring_health",
	"dagger_ironwood", "club_makeshift", "branch_heavy", "shield_wood",
]

## The world scene that embeds this town, or null when the town stands alone.
## Set before the node enters the tree.
##
## Embedded, the town is the far end of one continuous world: the world owns the
## bodies, the camera, the HUD, the night and the hostiles, the town's north wall
## is the gate the trail comes in through, and the square is cut into the same
## wood the clearing stands in. Alone, this is the square as its own scene - the
## preview the art and quartermaster regressions load.
var host: Node3D = null

var warband: WarbandState
var camera: Camera3D
var controller
var hud: WarbandHud
var screen: WarbandScreen
var paperdoll: WarbandPaperdoll
var altar: SacrificialAltar
var stash_chest: Node3D
var recruiter_desk: Node3D
var quartermaster_desk: Node3D
var quartermaster
var vendor_orla: Node3D
var vendor_brann: Node3D
var vendor_vey: Node3D
var vendor_menu
var signpost: Node3D
## The arena's gate and its board.
var arena_gate: Node3D
var arena_menu
var unlock_totem: Node3D
var weapon_rack: Node3D
var run_portal: Node3D
var forge_panel
## The keeper `interact_at` resolves by service id (`town_folk.gd`).
var keepers: Dictionary = {}
## The watch at the gate (`town_guard.gd`).
var guards: Array = []
## The stake count the ring came out at, for the settlement's own readout.
var palisade_stakes := 0
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
var _iron: StandardMaterial3D
## Every wall, floor and hall collider in the town, on one body: the village kit
## registers each shape against the caller's own solid, so collision keeps one
## owner per scene.
var _solids: StaticBody3D

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
		print("TOWN_HUB_READY bodies=%d gold=%d stakes=%d buildings=%d keepers=%d guards=%d"
			% [bodies.size(), warband.gold(), palisade_stakes, BUILDINGS.size(),
				keepers.size(), guards.size()])


## Adopt the pieces the world owns. The world calls this once, after the town is
## in the tree and before the warband is placed here.
func embed(world: Node3D) -> void:
	host = world
	warband = world.warband
	controller = world.controller
	hud = world.hud
	screen = world.screen
	paperdoll = world.paperdoll


## Where the warband stands when the campaign starts in the town.
func spawn_posts() -> Array[Vector3]:
	return _spawn_points()


## Seat the bodies the world spawned around the fire: the square shows the whole
## living warband.
func place_warband(bodies_in: Array) -> void:
	bodies = bodies_in
	for actor in bodies:
		if not is_instance_valid(actor):
			continue
		var index := bodies.find(actor)
		var post: Vector3 = SPAWN_POSTS[index % SPAWN_POSTS.size()]
		actor.global_position = global_position + post
		actor.spawn_point = global_position + post


## Embedded, the world steps the bodies and writes the one HUD: the square only
## answers questions about what stands where.
func _physics_process(delta: float) -> void:
	Perf.begin("town.physics")
	_step_world(delta)
	Perf.end()


func _step_world(delta: float) -> void:
	if controller == null or host != null:
		return
	controller.physics_step(delta)
	_update_prompt()

func _process(delta: float) -> void:
	Perf.begin("town.process")
	if host == null:
		var wanted := Input.MOUSE_MODE_VISIBLE if _panel_open() else Input.MOUSE_MODE_CAPTURED
		if Input.mouse_mode != wanted:
			Input.mouse_mode = wanted
	Perf.end()

func _unhandled_input(event: InputEvent) -> void:
	if host != null:
		return
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
	_iron = Geo.material(Color(0.28, 0.27, 0.26), 0.62, 0.5)
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
	_build_solids()
	_build_wall()
	_build_buildings()
	_build_village_props()
	_build_campfire()
	_build_guards()

## The square's worn ground, for the world's terrain (baked before the town is
## built), with the square's centre at `at`: the ring inside the stockade is
## trodden dirt round the paved middle, and the road comes in through the north
## gate on a worn line of its own.
static func trodden_ground(at: Vector3) -> Array:
	var road := PackedVector3Array([at + Vector3(0.0, 0.0, WALL_RADIUS + 9.0),
		at + Vector3(0.0, 0.0, WALL_RADIUS), at + Vector3(0.0, 0.0, 6.0)])
	return [
		{"point": at, "radius": WALL_RADIUS - 2.0, "strength": 0.8},
		{"points": road, "half_width": NORTH_GATE_HALF * 0.6, "strength": 0.9},
	]

func _build_ground() -> void:
	# The world scene owns one ground for the whole map - a heightfield with this
	# square padded flat into it - so the square's own props keep standing at y = 0
	# and a second slab would only z-fight with the field.
	if host == null:
		var ground := StaticBody3D.new()
		ground.name = "Ground"
		add_child(ground)
		# A town standing alone also owns the road outside its own gate: the
		# watch needs ground to shoot at, and the wood is planted out to the same
		# depth the world's treeline runs.
		var span := (WALL_RADIUS + WOOD_DEPTH) * 2.0
		var slab := BoxShape3D.new()
		slab.size = Vector3(span, 0.6, span)
		var shape := CollisionShape3D.new()
		shape.shape = slab
		shape.position = Vector3(0.0, -0.3, 0.0)
		ground.add_child(shape)
		Geo.box(ground, slab.size, Vector3(0.0, -0.3, 0.0), _earth)
	_build_paving()


## Worn flagstones: the middle of the square is paved, the ring stays dirt. Laid
## as a seeded grid of single stones whose outer courses are dropped and jittered,
## so the paving ends the way a laid square ends - in a ragged line of half-sunk
## stones the trodden ring swallows - instead of as a pale rectangular slab.
func _build_paving() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = PAVING_SEED
	var library = preload("res://scripts/world/texture_library.gd")
	var material: Material = library.paving_material(Color(0.52, 0.50, 0.47))
	var merged := preload("res://scripts/world/camp_kit.gd").Merged.new()
	var half := PAVING_SIZE * 0.5
	var columns := ceili(PAVING_SIZE.x / PAVING_CELL)
	var rows := ceili(PAVING_SIZE.y / PAVING_CELL)
	for row in rows:
		for column in columns:
			var at := Vector2(-half.x + (float(column) + 0.5) * PAVING_CELL,
				-half.y + (float(row) + 0.5) * PAVING_CELL)
			# The square is an ellipse of laid stones: how far into it a cell sits
			# decides the odds one was laid there, so the edge comes out ragged.
			var reach := Vector2(at.x / half.x, at.y / half.y).length()
			if reach + rng.randf_range(-PAVING_RAGGED, PAVING_RAGGED) > 1.0:
				continue
			var span := PAVING_CELL - 0.06
			var stone := BoxMesh.new()
			stone.size = Vector3(span * rng.randf_range(0.86, 1.06), 0.08,
				span * rng.randf_range(0.86, 1.06))
			merged.add(stone, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.06, 0.06)),
				Vector3(at.x, 0.01, at.y)), material)
	merged.commit(self, "Paving", false)


## The one solid body every wall, hall and prop in the town registers its shapes
## against. Built before anything that stands on it.
func _build_solids() -> void:
	_solids = StaticBody3D.new()
	_solids.name = "TownSolids"
	_solids.collision_layer = 1
	_solids.collision_mask = 0
	add_child(_solids)

## The town is a stockade: a full ring of leaning stakes with one gap cut where
## the road comes in, and the gate hung in it. It is the whole difference between
## a square and a settlement, and it keeps the world's own field under it rather
## than a second flat floor.
func _build_wall() -> void:
	var ring := Node3D.new()
	ring.name = "Palisade"
	add_child(ring)
	palisade_stakes = VillageKit.palisade(ring, VillageKit.materials(), _solids, Vector2.ZERO,
		WALL_RADIUS, GATE_GAPS, _ground_at, WALL_SEED)
	_build_north_gate()


## The field under a town-local point. The world pads this square flat, but the
## wall stands on its own ground, so the ring follows a slope instead of floating
## over one; a town standing alone has nothing but y = 0.
func _ground_at(x: float, z: float) -> Vector3:
	if host == null:
		return Vector3(x, 0.0, z)
	return TerrainScript.grounded(global_position + Vector3(x, 0.0, z)) - global_position


## The gate the trail comes in through: the village kit's own frame, so the town
## reads as a settlement cut into the same world as the clearing it began in. Two
## braziers hang on its posts - the one warm light in a gate that has to be found
## from the road.
func _build_north_gate() -> void:
	var gate := Node3D.new()
	gate.name = "NorthGate"
	gate.position = Vector3(0.0, 0.0, WALL_RADIUS)
	add_child(gate)
	VillageKit.gate(gate, VillageKit.materials(), _solids, NORTH_GATE_HALF, GATE_HEIGHT, GATE_SEED)
	# The road's name, painted on a board hung under the gate's tie beam: east of
	# the hide banner that holds the middle of the span, high enough to walk under.
	var sign_at := Vector3(SIGN_BOARD_X, GATE_HEIGHT - 0.90, 0.14)
	SignKit.plank_board(gate, "wood_road", sign_at, 0.0, "GateSign")
	var top := sign_at.y + SignKit.size_of("wood_road").y * 0.5 + 0.10
	SignKit.hangers(gate, "wood_road", GATE_HEIGHT - 0.33, top, [0.62, -0.62], 0.14)
	for side in [-1.0, 1.0]:
		# An iron bowl lashed to the post, with the fire of the gate in it.
		Geo.cylinder(gate, 0.24, 0.15, 0.20,
			Vector3(side * (NORTH_GATE_HALF + 0.02), 3.42, 0.0), _iron, 10)
		Geo.cylinder(gate, 0.17, 0.17, 0.05,
			Vector3(side * (NORTH_GATE_HALF + 0.02), 3.53, 0.0), _ember, 10)
		var light := _lamp(gate, Vector3(side * (NORTH_GATE_HALF + 0.02), 3.86, 0.0),
			Color(1.0, 0.66, 0.32), 2.4, 10.0)
		light.name = "GateBrazier%d" % (1 if side < 0.0 else 2)


## The settlement behind the stakes: the halls, the round dwellings and the one
## open stall, each with its doorway to the fire.
func _build_buildings() -> void:
	var mats: Dictionary = VillageKit.materials()
	for row in BUILDINGS:
		var at: Vector3 = row["at"]
		var node := Node3D.new()
		node.name = str(row["name"])
		node.position = at
		# A longhouse's door is on its local -Z and a round hut's on its local
		# +Z, so each one is turned to put that face on the fire and its back on
		# the stakes.
		node.rotation.y = atan2(-at.x, -at.z) if str(row["kind"]) == "wattle" \
			else atan2(at.x, at.z)
		add_child(node)
		match str(row["kind"]):
			"keeper":
				VillageKit.keeper_hut(node, mats, _solids, {
					"seed": int(row["seed"]),
					"name": "%sShell" % str(row["name"]),
					"pitch": 0.52,
				})
			"wattle":
				VillageKit.wattle_hut(node, mats, _solids, 2.2, 2.35, int(row["seed"]))
			"frame":
				VillageKit.trader_frame(node, mats, _solids, int(row["seed"]))


## The wardens' own furniture, and the small litter of a place people live in.
## The litter is presentation only - one merged mesh, no collider - so it may lie
## under a counter's ring without standing in it.
func _build_village_props() -> void:
	var mats: Dictionary = VillageKit.materials()
	for row in VILLAGE_PROPS:
		var at: Vector3 = row["at"]
		var node := Node3D.new()
		node.name = str(row["name"])
		node.position = at
		# Every prop faces the fire unless its row names an angle of its own.
		node.rotation.y = deg_to_rad(float(row["yaw"])) if row.has("yaw") \
			else atan2(at.x, at.z)
		add_child(node)
		match str(row["kind"]):
			"totem":
				VillageKit.totem(node, mats, _solids, float(row.get("height", 4.4)),
					int(row["seed"]))
			"woodpile":
				VillageKit.woodpile(node, mats, _solids, int(row["seed"]))
			"rack":
				VillageKit.drying_rack(node, mats, _solids, int(row["seed"]))
			"effigy":
				VillageKit.effigy(node, mats, _solids, int(row["seed"]))
			"offering":
				VillageKit.sacrifice_ground(node, mats, _solids, int(row["seed"]))
	_build_litter()

func _build_litter() -> void:
	var mats: Dictionary = VillageKit.materials()
	var m := VillageKit.Merged.new()
	VillageKit.chopping_block(m, mats, Vector3(-13.15, 0.0, -12.2), 0.6)
	VillageKit.pot_stack(m, mats, Vector3(-11.4, 0.0, 8.2), 1.2, 4409)
	VillageKit.pot_stack(m, mats, Vector3(12.4, 0.0, 6.4), 2.6, 4421)
	VillageKit.bone_heap(m, mats, Vector3(-3.3, 0.0, 8.5), 0.9, 4423)
	m.commit(self, "TownLitter")

## The wood the settlement is cut into: the same treeline the clearing has, with
## one gap where the road comes in. The ring is a circle inscribed in the plot,
## so the planner can never plant a trunk inside the stakes.
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
	# The flames are the world's own: `FireFx.flame_cards` on the shared flame
	# shader, the same cards the wood burns and the camp's fires use. A cone with an
	# emissive material reads as a plastic party hat at the middle of a town square.
	var mats: Dictionary = VillageKit.materials()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1217
	var merged := VillageKit.Merged.new()
	FireFx.flame_cards(merged, mats["flame"], rng, 1.30, 0.16)
	flame = merged.commit(fire, "FireTongues")
	FireFx.embers(fire, 0.22, 0.55, 26)
	fire_light = OmniLight3D.new()
	fire_light.name = "FireLight"
	fire_light.light_color = Color(1.0, 0.62, 0.28)
	# A town square's fire carries further than a camp's: the halls around it are
	# thirty metres apart and the light is the only thing between them and the dark.
	fire_light.light_energy = 3.2
	fire_light.omni_range = 16.0
	fire_light.omni_attenuation = 1.4
	fire_light.position = Vector3(0.0, 1.1, 0.0)
	add_child(fire_light)


## A lamp the square adds: never a shadow caster, never over the town's budget.
## The night is the world's to light; these only mark the doors.
func _lamp(parent: Node3D, at: Vector3, colour: Color, energy: float, reach: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = colour
	light.light_energy = minf(energy, 3.2)
	light.omni_range = reach
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	light.position = at
	parent.add_child(light)
	return light


## The watch. Three static archers at the gate, all of them on the ground where a
## post can see down the road. Everything they are lives in `town_guard.gd`.
func _build_guards() -> void:
	guards.clear()
	for index in GUARD_POSTS.size():
		var row: Dictionary = GUARD_POSTS[index]
		var guard := GuardScript.new()
		guard.name = "Watch%d" % (index + 1)
		add_child(guard)
		guard.setup(host, row["at"], float(row["yaw"]))
		guards.append(guard)

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
	bodies = controller.spawn_mercenaries(_spawn_points(), true)
	for actor in bodies:
		if not is_instance_valid(actor):
			continue
		actor.global_position = actor.spawn_point + Vector3(0.0, 0.1, 0.0)
		actor.bounds = BODY_BOUNDS

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
		# The gear page and its hotbar belong to the body the soul is in.
		if paperdoll != null:
			paperdoll.follow_controlled(merc_id)
		hud.set_status("%s takes the soul." % warband.roster.name_of(merc_id), 2.0)

func _on_transfer_refused(_peer_id: int, merc_id: int, reason: String) -> void:
	hud.set_status("%s: %s" % [warband.roster.name_of(merc_id), reason], 3.0)

func _on_possession_released(_peer_id: int, reason: String) -> void:
	hud.set_body(null, "", -1)
	if paperdoll != null:
		paperdoll.follow_controlled(-1)
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
	vendor_orla = _build_vendor_counter("VendorOrla", VENDOR_ORLA_POINT,
		Color(0.94, 0.80, 0.52), 0)
	vendor_brann = _build_vendor_counter("VendorBrann", VENDOR_BRANN_POINT,
		Color(0.86, 0.62, 0.42), 1)
	vendor_vey = _build_vendor_counter("VendorVey", VENDOR_VEY_POINT,
		Color(0.72, 0.82, 0.96), 2)
	signpost = _build_signpost()
	arena_gate = _build_arena_gate()
	unlock_totem = _build_unlock_totem()
	weapon_rack = _build_weapon_rack()
	run_portal = _build_run_portal()

	# Behind every counter, a keeper: a face and a kit, not a service.
	keepers = FolkScript.build(self, {
		"vendor_orla": vendor_orla, "vendor_brann": vendor_brann,
		"vendor_vey": vendor_vey, "recruiter": recruiter_desk,
		"quartermaster": quartermaster_desk,
	})

	# The keeper's counter is a service, not scenery of the HUD: the world embeds
	# the square without building the town's own panels.
	quartermaster = QuartermasterScript.new()
	quartermaster.name = "Quartermaster"
	add_child(quartermaster)
	quartermaster.configure(warband)
	# One panel walks from keeper to keeper; the town owns the layer above the HUD
	# so a stall opened by a standing body draws over both the square and the keys.
	var vendor_layer := CanvasLayer.new()
	vendor_layer.name = "VendorLayer"
	vendor_layer.layer = 9
	add_child(vendor_layer)
	vendor_menu = VendorMenuScript.new()
	vendor_menu.name = "VendorMenu"
	vendor_layer.add_child(vendor_menu)
	vendor_menu.configure(warband, 0)
	# A trade is the one thing the keeper answers besides being walked up to. The
	# panel is the same node for all three stalls, so the keeper is read off it at
	# the moment the coin lands rather than bound when the board was built.
	vendor_menu.purchased.connect(func(_item_id: String): _on_stall_traded())
	quartermaster.purchased.connect(func(_item_id: String): _speak_keeper("quartermaster", "done"))
	# The arena board. It lives on its own layer above the HUD, like the stalls.
	var forge_layer := CanvasLayer.new()
	forge_layer.name = "ForgeLayer"
	forge_layer.layer = 9
	add_child(forge_layer)
	forge_panel = ForgePanelScript.new()
	forge_panel.name = "ForgePanel"
	forge_layer.add_child(forge_panel)
	forge_panel.configure(self)
	DressingScript.build(self)


## The arena's gate: four stone posts and two lintels, standing in the dirt east
## of the fire. Placeholder stone, like the ring it opens - the press is the thing.
func _build_arena_gate() -> Node3D:
	var gate := Node3D.new()
	gate.name = "ArenaGate"
	gate.position = ARENA_POINT
	add_child(gate)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.36, 0.35, 0.33)
	stone.roughness = 0.95
	for side in [-1.0, 1.0]:
		Geo.box(gate, Vector3(0.9, 3.6, 0.9), Vector3(float(side) * 2.2, 1.8, 0.0), stone)
	Geo.box(gate, Vector3(5.6, 0.7, 1.1), Vector3(0.0, 3.9, 0.0), stone)
	# The name of the press, cut into a stone plate set on the lintel's face.
	SignKit.plaque(gate, "arena", Vector3(0.0, 3.9, 0.605), 0.0, "ArenaNameplate")
	return gate


## The Unlock Totem: a bone pillar with a bowl of keys and fire on top. Its press
## spends keys on a random locked weapon (`Roguelite.roll_unlock`).
func _build_unlock_totem() -> Node3D:
	var totem := Node3D.new()
	totem.name = "UnlockTotem"
	totem.position = TOTEM_POINT
	add_child(totem)
	var bone := StandardMaterial3D.new()
	bone.albedo_color = Color(0.76, 0.70, 0.56)
	bone.roughness = 0.72
	var ember := StandardMaterial3D.new()
	ember.albedo_color = Color(0.95, 0.62, 0.24)
	ember.emission_enabled = true
	ember.emission = Color(0.95, 0.54, 0.18)
	ember.emission_energy_multiplier = 1.4
	Geo.cylinder(totem, 0.24, 0.32, 2.4, Vector3(0.0, 1.2, 0.0), bone, 8)
	Geo.cylinder(totem, 0.52, 0.44, 0.36, Vector3(0.0, 2.52, 0.0), _iron, 8)
	Geo.sphere(totem, 0.34, Vector3(0.0, 2.78, 0.0), ember, Vector3(1.0, 0.7, 1.0))
	for index in 4:
		var angle := TAU * float(index) / 4.0
		var horn := Geo.cylinder(totem, 0.07, 0.02, 0.52,
			Vector3(cos(angle) * 0.3, 2.2, sin(angle) * 0.3), bone, 5)
		horn.rotation.z = cos(angle) * 0.45
		horn.rotation.x = sin(angle) * 0.45
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.68, 0.30)
	light.light_energy = 1.4
	light.omni_range = 6.0
	light.position = Vector3(0.0, 2.8, 0.0)
	totem.add_child(light)
	totem.add_child(_label("UNLOCK TOTEM", Vector3(0.0, 3.5, 0.0),
		Color(0.95, 0.78, 0.42)))
	return totem


## The Weapon Rack: three hafts and a bound rack, where an unlocked piece is taken
## up before the portal.
func _build_weapon_rack() -> Node3D:
	var rack := Node3D.new()
	rack.name = "WeaponRack"
	rack.position = RACK_POINT
	add_child(rack)
	for side in [-1.0, 1.0]:
		Geo.box(rack, Vector3(0.18, 2.0, 0.18), Vector3(float(side) * 1.25, 1.0, 0.0), _wood)
	Geo.box(rack, Vector3(2.9, 0.18, 0.24), Vector3(0.0, 1.85, 0.0), _wood)
	Geo.box(rack, Vector3(2.9, 0.14, 0.24), Vector3(0.0, 0.9, 0.0), _wood)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.70, 0.74, 0.75)
	steel.metallic = 0.7
	steel.roughness = 0.3
	for index in 3:
		var x := (float(index) - 1.0) * 0.78
		Geo.cylinder(rack, 0.035, 0.035, 1.45, Vector3(x, 1.4, 0.12), _wood, 6)
		var blade := Geo.box(rack, Vector3(0.11, 0.5, 0.03),
			Vector3(x, 2.18, 0.12), steel if index != 1 else _iron)
		blade.rotation.z = 0.12 if index == 0 else (-0.1 if index == 2 else 0.0)
	rack.add_child(_label("WEAPON RACK", Vector3(0.0, 2.95, 0.0),
		Color(0.92, 0.86, 0.68)))
	return rack


## The Start Run Portal: a stone arch with a sheet of the next run's own light.
## Its press opens the board that begins the run.
func _build_run_portal() -> Node3D:
	var portal := Node3D.new()
	portal.name = "RunPortal"
	portal.position = RUN_PORTAL_POINT
	add_child(portal)
	for side in [-1.0, 1.0]:
		Geo.box(portal, Vector3(0.7, 4.4, 0.8), Vector3(float(side) * 2.1, 2.2, 0.0), _stone)
	Geo.box(portal, Vector3(4.9, 0.7, 0.9), Vector3(0.0, 4.6, 0.0), _stone)
	var veil := StandardMaterial3D.new()
	veil.albedo_color = Color(0.30, 0.52, 0.72, 0.20)
	veil.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	veil.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	veil.emission_enabled = true
	veil.emission = Color(0.34, 0.58, 0.80)
	veil.emission_energy_multiplier = 0.35
	veil.cull_mode = BaseMaterial3D.CULL_DISABLED
	Geo.box(portal, Vector3(3.5, 4.0, 0.08), Vector3(0.0, 2.2, 0.0), veil)
	var light := OmniLight3D.new()
	light.light_color = Color(0.58, 0.82, 0.95)
	light.light_energy = 2.0
	light.omni_range = 12.0
	light.position = Vector3(0.0, 2.2, 1.2)
	portal.add_child(light)
	portal.add_child(_label("START RUN", Vector3(0.0, 5.4, 0.0),
		Color(0.72, 0.90, 0.96)))
	return portal


## Open the arena board on one of its three pages. The panel is the one thing in
## the square that is not a counter: it is where a loadout is decided.
func _open_forge(mode: String) -> void:
	_hide_panels()
	if forge_panel != null:
		forge_panel.open(mode)


func _meta_keys() -> int:
	var meta := get_node_or_null("/root/Roguelite")
	return int(meta.keys) if meta != null else 0


func _build_stash_chest() -> Node3D:
	var chest := Node3D.new()
	chest.name = "StashChest"
	chest.position = STASH_POINT
	add_child(chest)
	Geo.box(chest, Vector3(1.5, 0.8, 0.95), Vector3(0.0, 0.4, 0.0), _wood)
	Geo.box(chest, Vector3(1.62, 0.24, 1.02), Vector3(0.0, 0.9, 0.0), _wood)
	for x in [-0.6, 0.6]:
		Geo.box(chest, Vector3(0.12, 0.86, 1.04), Vector3(x, 0.45, 0.0), _iron)
	Geo.box(chest, Vector3(0.22, 0.24, 0.1), Vector3(0.0, 0.62, 0.52), _iron)
	chest.add_child(_label("STASH", Vector3(0.0, 1.45, 0.0), Color(0.95, 0.78, 0.48)))
	return chest

func _build_recruiter_desk() -> Node3D:
	var desk := Node3D.new()
	desk.name = "RecruiterDesk"
	desk.position = RECRUITER_POINT
	add_child(desk)
	Geo.box(desk, Vector3(2.0, 0.12, 0.9), Vector3(0.0, 0.92, 0.0), _wood)
	for x in [-0.82, 0.82]:
		Geo.box(desk, Vector3(0.14, 0.86, 0.8), Vector3(x, 0.43, 0.0), _wood)
	# The ledger and the purse: this is a place where names and gold are traded.
	Geo.box(desk, Vector3(0.46, 0.06, 0.34), Vector3(-0.45, 1.01, 0.0),
		Geo.material(Color(0.55, 0.52, 0.44), 0.0, 0.95))
	Geo.box(desk, Vector3(0.2, 0.1, 0.2), Vector3(0.55, 1.03, 0.0), _iron)
	var lamp := _lamp(desk, Vector3(0.0, 1.5, 0.0), Color(1.0, 0.72, 0.42), 1.1, 5.0)
	lamp.name = "DeskLamp"
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
	var lamp := _lamp(desk, Vector3(0.0, 1.5, 0.0), Color(0.78, 0.84, 1.0), 0.95, 5.0)
	lamp.name = "DeskLamp"
	return desk

## One of the three market stalls: the same trestle as the recruiter's and the
## keeper's, dressed with the goods that stall actually trades in - Orla's rack
## of bows and staves, Brann's anvil and laid-out blades, Vey's folded plates.
## The keeper's name is over the *keeper* (`town_folk.gd`), not over the boards:
## a market is people, not labels. `seat` is the `PlayerState.VENDORS` index the
## counter opens.
func _build_vendor_counter(node_name: String, at: Vector3, accent: Color,
		seat: int) -> Node3D:
	var counter := Node3D.new()
	counter.name = node_name
	counter.position = at
	add_child(counter)
	var iron := Geo.material(Color(0.30, 0.29, 0.28), 0.6, 0.55)
	var steel := Geo.material(Color(0.46, 0.47, 0.49), 0.75, 0.35)
	Geo.box(counter, Vector3(2.0, 0.12, 0.9), Vector3(0.0, 0.92, 0.0), _wood)
	for x in [-0.82, 0.82]:
		Geo.box(counter, Vector3(0.14, 0.86, 0.8), Vector3(x, 0.43, 0.0), _wood)
	match seat:
		0:
			# Orla: bows and staves leaning on the back bar, a tally board in front.
			for index in 4:
				var slot_x := -0.76 + float(index) * 0.5
				Geo.beam(counter, Vector3(slot_x, 1.0, -0.24),
					Vector3(slot_x + 0.08, 2.05, -0.34), 0.028, _wood, 6)
			Geo.box(counter, Vector3(0.5, 0.05, 0.26), Vector3(-0.4, 0.99, 0.22),
				Geo.material(Color(0.55, 0.52, 0.44), 0.0, 0.95))
		1:
			# Brann: the anvil, three blades laid out, and the hammer beside them.
			Geo.box(counter, Vector3(0.44, 0.2, 0.24), Vector3(0.5, 1.08, 0.0), iron)
			for index in 3:
				Geo.box(counter, Vector3(0.68, 0.03, 0.055),
					Vector3(-0.38, 0.995, -0.2 + float(index) * 0.2), steel)
			Geo.beam(counter, Vector3(-0.86, 0.98, 0.14),
				Vector3(-0.6, 1.3, 0.14), 0.022, _wood, 6)
		2:
			# Vey: folded armour plates and a helm waiting to be fitted.
			for index in 4:
				Geo.box(counter, Vector3(0.62, 0.05, 0.5),
					Vector3(-0.3, 0.99 + float(index) * 0.055, 0.0), iron)
			Geo.sphere(counter, 0.16, Vector3(0.52, 1.06, 0.0), steel,
				Vector3(1.0, 0.9, 1.1))
	var lamp := _lamp(counter, Vector3(0.0, 1.5, 0.0), accent, 0.85, 4.5)
	lamp.name = "StallLamp"
	return counter

func _build_signpost() -> Node3D:
	var post := Node3D.new()
	post.name = "Signpost"
	post.position = SIGN_POINT
	add_child(post)
	Geo.cylinder(post, 0.13, 0.11, 3.0, Vector3(0.0, 1.5, 0.0), _wood, 8)
	# What the square offers, painted on a board nailed to the post's face and
	# turned to the fire - the one direction a body in this square comes from.
	# The extra half-turn is the board's painted side: `plank_board` cuts its
	# face on local -Z, so the board stands proud on +Z and looks back at the fire.
	var to_fire := atan2(-SIGN_POINT.x, -SIGN_POINT.z) + PI
	SignKit.plank_board(post, "square",
		Vector3(0.0, 2.30, 0.0) + Vector3(sin(to_fire), 0.0, cos(to_fire)) * 0.15,
		to_fire, "SquareBoard", false)
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
	arena_menu = ArenaMenuScript.new()
	arena_menu.name = "ArenaMenu"
	arena_menu.visible = false
	layer.add_child(arena_menu)
	arena_menu.fight_requested.connect(_on_arena_fight_requested)
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

# --- the keepers' business -------------------------------------------------

## Every counter a `G` opens is a panel here; nothing in the town is a board of
## orders, so there is no mouth to build and no arrow to hang. The keepers are
## nodes (`town_folk.gd`) and `interact_at` resolves which one is in reach.

# --- interaction -----------------------------------------------------------

## `TAB` quick-swaps the standing body's weapon set, exactly as the frontier does.
## A town standing alone (its own preview scene) gets the same key the campaign
## world binds, so the swap is never a world-only feature.
func _swap_weapon_set() -> void:
	if warband == null or controller == null:
		return
	var merc_id: int = controller.merc_for_peer(1)
	if merc_id <= 0:
		hud.set_status("No body to swap for.", 2.0)
		return
	var result: Dictionary = warband.swap_weapon_set(merc_id)
	if bool(result.get("ok", false)):
		controller.refresh_gear(merc_id)
	hud.set_status(str(result.get("message", "")), 2.0)


## The one `G` handler: which service the standing body is next to.
func _try_interact() -> void:
	var actor = controller.active_body(1)
	if actor == null or not is_instance_valid(actor):
		hud.set_status("No body to act with.", 2.0)
		return
	if interact_at(1, actor.global_position).is_empty():
		hud.set_status("Nothing to use here.", 1.5)

## Resolve and use whichever service `point` is next to. Returns `"stash"`,
## `"altar"`, `"recruiter"`, `"quartermaster"`, `"vendor_orla"`, `"vendor_brann"`,
## `"vendor_vey"` or `""`, which is what a single `G` handler and the
## regression both drive instead of guessing at positions.
func interact_at(peer_id: int, point: Vector3) -> String:
	var service := service_at(point)
	# A counter being used is the one moment a keeper has a body's attention, so
	# that is when they speak. It goes before the panel opens: the line is the
	# greeting, the board is the service.
	_speak_keeper(service, "greet")
	match service:
		"stash":
			_hide_panels()
			paperdoll.open(controller.merc_for_peer(peer_id))
			hud.set_status("The shared stash is open: click a free piece to wear it.", 4.0)
		"altar":
			_hide_panels()
			altar.interact(peer_id)
			hud.set_status("The altar: lay a warden's ichor on a weapon and it wakes into its skill.", 4.0)
		"recruiter":
			_hide_panels()
			screen.open()
			var hiring := "Hire from the recruiter board: every oath under the cap costs" \
				+ " nothing, and every body arms itself out of the shared stash."
			screen.set_status(hiring)
			hud.set_status(hiring, 5.0)
		"quartermaster":
			_hide_panels()
			quartermaster.open()
			hud.set_status("The quartermaster sells plain steel and arrows into the shared stash.", 4.0)
		"vendor_orla":
			_open_vendor(0)
		"vendor_brann":
			_open_vendor(1)
		"vendor_vey":
			_open_vendor(2)
		"arena":
			_hide_panels()
			if arena_menu != null:
				arena_menu.open()
			hud.set_status("THE ARENA: pick how hard the ring is, then step in.", 4.0)
		"roguelite_totem":
			_open_forge("totem")
			hud.set_status("THE UNLOCK TOTEM: keys open the armory.", 4.0)
		"roguelite_rack":
			_open_forge("rack")
			hud.set_status("THE WEAPON RACK: bind the two pieces the run carries.", 4.0)
		"roguelite_portal":
			_open_forge("portal")
			hud.set_status("THE START RUN PORTAL: six islands, then the run is won.", 4.0)

	return service

## One keeper line, at the counter they are standing behind. Two cues exist
## today - `greet` and `done` - and both are rows in `VoiceLibrary`, so a keeper
## answering a question the player asked is a third row and one call here. The
## panel's own text is unchanged: the voice is on top of it, not instead of it.
func _speak_keeper(service: String, cue: String) -> void:
	if not KEEPER_VOICES.has(service):
		return
	VoiceScript.say(str(KEEPER_VOICES[service]), cue, service_point(service))


## A stall sale: whichever keeper the walking panel is pointed at answers it.
func _on_stall_traded() -> void:
	var index := clampi(vendor_menu.vendor_index(), 0, VENDOR_SERVICES.size() - 1)
	_speak_keeper(str(VENDOR_SERVICES[index]), "done")


## Open one keeper's stall. One panel serves all three, so opening a stall closes
## whatever was up and re-points the same board at that keeper's stock.
func _open_vendor(index: int) -> void:
	_hide_panels()
	vendor_menu.configure(warband, index)
	vendor_menu.open()
	hud.set_status("%s  ·  %s" % [vendor_menu.keeper_name(), vendor_menu.keeper_line()], 5.0)

## Whether a body is standing on the settlement's ground at all (the ring plus a
## stride): what decides whether the town's own prompt or the trail's is the one
## worth showing. `margin` widens the ring, which is what a rule that needs two
## answers - "is it a town body" now, and "has it left for good" - asks with, so a
## body on the line cannot flicker between them.
func in_square(actor, margin: float = 0.0) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var local: Vector3 = actor.global_position - global_position
	return Vector2(local.x, local.z).length() <= _square_reach(margin)

## Flat metres from a point to the edge of `in_square`'s ring: what the trail's
## objective counts down, so it reaches zero where the town's own lines begin.
func metres_to_square(point: Vector3) -> float:
	var local: Vector3 = point - global_position
	return maxf(Vector2(local.x, local.z).length() - _square_reach(), 0.0)

## The square's ring: the wall plus a stride, widened by `margin`.
func _square_reach(margin: float = 0.0) -> float:
	return WALL_RADIUS + 2.0 + maxf(margin, 0.0)


## Whether one of the square's panels is open (the world owns the input, the
## square owns the panels it opens).
func panels_open() -> bool:
	return _panel_open()


## Close whatever the square opened, for the world's one `ESC` and `O`.
func close_panels() -> void:
	_hide_panels()


## The nearest service whose ring holds `point`, or `""`.
func service_at(point: Vector3) -> String:
	var entries: Array[Dictionary] = [
		{"id": "stash", "point": stash_chest.global_position, "reach": SERVICE_REACH},
		{"id": "altar", "point": altar.global_position, "reach": altar.interact_range},
		{"id": "recruiter", "point": recruiter_desk.global_position, "reach": SERVICE_REACH},
		{"id": "quartermaster", "point": quartermaster_desk.global_position, "reach": SERVICE_REACH},
		{"id": "vendor_orla", "point": vendor_orla.global_position, "reach": SERVICE_REACH},
		{"id": "vendor_brann", "point": vendor_brann.global_position, "reach": SERVICE_REACH},
		{"id": "vendor_vey", "point": vendor_vey.global_position, "reach": SERVICE_REACH},
		{"id": "arena", "point": arena_gate.global_position, "reach": SERVICE_REACH + 1.0},
		{"id": "roguelite_totem", "point": unlock_totem.global_position, "reach": SERVICE_REACH},
		{"id": "roguelite_rack", "point": weapon_rack.global_position, "reach": SERVICE_REACH},
		{"id": "roguelite_portal", "point": run_portal.global_position, "reach": SERVICE_REACH + 1.0},
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
		"vendor_orla":
			return vendor_orla.global_position
		"vendor_brann":
			return vendor_brann.global_position
		"vendor_vey":
			return vendor_vey.global_position
		"arena":
			return arena_gate.global_position if arena_gate != null else Vector3.ZERO
		"roguelite_totem":
			return unlock_totem.global_position if unlock_totem != null else Vector3.ZERO
		"roguelite_rack":
			return weapon_rack.global_position if weapon_rack != null else Vector3.ZERO
		"roguelite_portal":
			return run_portal.global_position if run_portal != null else Vector3.ZERO
	return Vector3.ZERO

## The board's press: the tier is the ring's own, and the ring is the world's.
## A town standing alone (its own preview scene) has no campaign around it, so it
## says so rather than pretending.
func _on_arena_fight_requested(tier: String) -> void:
	if host == null or host.get("arena") == null:
		hud.set_status("The ring needs the campaign around it.", 3.0)
		return
	var result: Dictionary = host.arena.enter(tier)
	if bool(result.get("ok", false)):
		if arena_menu != null:
			arena_menu.close()
		_hide_panels()
	else:
		hud.set_status(str(result.get("message", "")), 3.0)


## A paperdoll change has to reach the body standing in the square, or the
## mercenary keeps the old kit in the only place the player can see it.
func _on_paperdoll_changed() -> void:
	if paperdoll == null or paperdoll.selected_merc <= 0:
		return
	controller.refresh_gear(paperdoll.selected_merc)

## The key line for the square: what the body is standing at, as the one prompt
## under the crosshair. The town is where a player learns the two screens, so the
## counter under his nose names the one he is at; the screens themselves are
## taught by the keeper who tells him about them.
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
		"vendor_orla":
			return "G - Storekeeper Orla"
		"vendor_brann":
			return "G - Smith Brann"
		"vendor_vey":
			return "G - Quartermaster Vey"
		"roguelite_totem":
			return "G - UNLOCK TOTEM  ·  %d keys" % _meta_keys()
		"roguelite_rack":
			return "G - WEAPON RACK"
		"roguelite_portal":
			return "G - START RUN PORTAL"
	return ""


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
	if vendor_menu != null and vendor_menu.is_open():
		vendor_menu.close()
	if arena_menu != null and arena_menu.is_open():
		arena_menu.close()
	if forge_panel != null and forge_panel.is_open():
		forge_panel.close_panel()

func _panel_open() -> bool:
	return (screen != null and screen.is_open()) \
		or (paperdoll != null and paperdoll.is_open()) \
		or (altar != null and altar.is_open()) \
		or (quartermaster != null and quartermaster.is_open()) \
		or (vendor_menu != null and vendor_menu.is_open()) \
		or (arena_menu != null and arena_menu.is_open()) \
		or (forge_panel != null and forge_panel.is_open())

# --- seeding ---------------------------------------------------------------

## A first-run warband, so the square is playable from its first minute. An
## existing warband (from a save or the camp) is never touched. The world calls
## this only when the campaign starts in the town; a camp start has already stood
## its prisoners up. The body comes out of `seed_starting_band` with the one club
## the campaign issues and nothing else, and is never dressed here: the square only
## stocks the shared stash and the quiver, so the rest of the kit is won off the
## kills it makes.
func seed_warband() -> void:
	if not warband.roster.is_empty():
		return
	warband.seed_starting_band()
	for item_id in TOWN_SPARES:
		if State.ITEMS.has(str(item_id)):
			warband.stash.add(str(item_id), 1)
	# A bow with nothing to shoot is a stick: the band opens with one bunch of
	# shafts in the shared quiver, and every keeper sells more.
	warband.seed_quiver()
	warband.cruor.add(Contracts.CruorTier.T1_RITUAL_TALLOW, 25)
	warband.cruor.add(Contracts.CruorTier.T2_BLACK_BILE, 10)
	warband.cruor.add(Contracts.CruorTier.T3_COAGULATED_CRUOR, 5)
