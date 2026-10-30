extends Node3D
## The campaign's first town: a stockade settlement on the north road.
##
## It is the loop's home end. A leaning stake ring stands on the field with one
## gap cut for the road, an antler gate in the gap, and the settlement behind it:
## stick longhouses with their backs to the stakes, round wattle dwellings, an
## open stall, the wardens' offering ground, and a fire in the middle of it all.
## The five sworn mercenaries stand around that fire as real `ArenaActor` bodies
## under the real `PossessionController`, the local soul starts inside the first
## of them, and every service the loop needs is a node you can walk up to: the
## shared stash chest, the `SacrificialAltar` (where a warden's ichor wakes a
## weapon into its skill), the Gold recruiter's booth, the quartermaster's shop,
## the three keepers' counters (Orla, Brann, Vey) and the `ExpeditionGate` that
## marks a battle line and asks the flow owner for the arena.
##
## Behind every counter stands a keeper - an armoured humanoid, one of the five
## who run this place - and over the head of whichever of them has something to
## say hangs a gold "TALK TO HIM" arrow (`QuestGiver.marker_service()` decides,
## this scene only moves the arrow). Three archers of the watch hold the gate and
## shoot what comes up the road at it.
##
## There is no combat in the square itself: unpossessed bodies are fixtures
## (`set_bot(false)`), so it never brawls on its own. The watch is the one armed
## thing here, and it only ever aims outward, at the world's own hostiles.
##
## The same objects are used by the admin arena, so nothing here re-implements a
## service; this scene only places them and resolves which one a standing body is
## next to (`interact_at`).

const ControllerScript = preload("res://scripts/warband/possession_controller.gd")
const ClearingScript = preload("res://scripts/warband/camp_clearing.gd")
const RunForestScript = preload("res://scripts/warband/run_forest.gd")
const VillageKit = preload("res://scripts/world/village_kit.gd")
const TerrainScript = preload("res://scripts/warband/terrain.gd")
const GateScript = preload("res://scripts/warband/expedition_gate.gd")
const QuartermasterScript = preload("res://scripts/warband/quartermaster_menu.gd")
const VendorMenuScript = preload("res://scripts/warband/vendor_menu.gd")
const HudScript = preload("res://scripts/warband/warband_hud.gd")
const ScreenScript = preload("res://scripts/warband/warband_screen.gd")
const PaperdollScript = preload("res://scripts/warband/warband_paperdoll.gd")
const AltarScript = preload("res://scripts/warband/sacrificial_altar.gd")
const Geo = preload("res://scripts/geo.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const State = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const WarbandState = preload("res://scripts/warband/warband_state.gd")
const VoiceScript = preload("res://scripts/audio/voice.gd")
const FireFx = preload("res://scripts/world/fire_fx.gd")
const QuestGiverScript = preload("res://scripts/warband/quest_giver.gd")
const MarkerScript = preload("res://scripts/warband/quest_marker.gd")
const FolkScript = preload("res://scripts/warband/town_folk.gd")
const GuardScript = preload("res://scripts/warband/town_guard.gd")
const DressingScript = preload("res://scripts/warband/town_dressing.gd")

## How close a body must stand to the chest and the desks. The altar keeps its own
## `interact_range` and the gate its own (larger) `open_radius`.
const SERVICE_REACH := 3.0
## The town is a ring now, not a room: this is the stake wall a body stands
## inside, and the dressing mirrors it so the two can never drift apart.
const WALL_RADIUS := 22.0
## The gap in the north wall the trail comes in through.
const NORTH_GATE_HALF := 5.0
## The stakes' lean, the gate's height and the seed the ring is rebuilt from.
const GATE_HEIGHT := 4.6
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
const MARKER_POLL := 0.35
## Where the arrow hangs: over the name, high enough to clear the tallest rig.
const TALK_ARROW_HEIGHT := 2.42
## The campaign's ichor order, by the id the ledger knows it by.
const ICHOR_ORDER := "bind_the_ichor"

## The square's standing services, arranged so no two 3 m rings overlap: walking
## the square always names exactly one thing.
const STASH_POINT := Vector3(-8.0, 0.0, 4.0)
const ALTAR_POINT := Vector3(8.0, 0.0, 4.0)
const RECRUITER_POINT := Vector3(-8.0, 0.0, -6.0)
const QUARTERMASTER_POINT := Vector3(0.0, 0.0, -12.0)
const GATE_POINT := Vector3(8.0, 0.0, -6.0)
const SIGN_POINT := Vector3(2.0, 0.0, 9.0)

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
## Vey's armour table on the gate's side.
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
var gate: GateScript
var stash_chest: Node3D
var recruiter_desk: Node3D
var quartermaster_desk: Node3D
var quartermaster
var vendor_orla: Node3D
var vendor_brann: Node3D
var vendor_vey: Node3D
var vendor_menu
var signpost: Node3D
## The keeper `interact_at` resolves by service id (`town_folk.gd`).
var keepers: Dictionary = {}
## The keepers' mouths: the hire lesson, the campaign's orders and the choice of
## which keeper wears the gold arrow.
var quest_giver
## The one gold arrow in the town, riding whichever keeper has business.
var quest_marker
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
var _marker_clock := 0.0

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
		_build_quest_layer(null)
		controller.possession_changed.connect(_on_possession_changed)
		controller.transfer_refused.connect(_on_transfer_refused)
		controller.possession_released.connect(_on_possession_released)
		_enter_first_body()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var flow := get_node_or_null("/root/GameFlow")
		if flow != null:
			flow.bind(self)
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
	_build_quest_layer(world.get("tips"))
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

func _process(delta: float) -> void:
	if host == null:
		var wanted := Input.MOUSE_MODE_VISIBLE if _panel_open() else Input.MOUSE_MODE_CAPTURED
		if Input.mouse_mode != wanted:
			Input.mouse_mode = wanted
	# The arrow is asked again on a slow clock as well as on every talk and every
	# ledger change: the world counts its kills without telling anyone.
	_marker_clock += delta
	if _marker_clock >= MARKER_POLL:
		_marker_clock = 0.0
		_refresh_marker()

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
	var label := Label3D.new()
	label.name = "GateSign"
	label.text = "THE WOOD ROAD"
	label.font_size = 56
	label.pixel_size = 0.006
	label.modulate = Color(0.96, 0.82, 0.56)
	label.position = Vector3(0.0, GATE_HEIGHT + 0.3, 0.2)
	gate.add_child(label)
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
	vendor_orla = _build_vendor_counter("VendorOrla", VENDOR_ORLA_POINT,
		Color(0.94, 0.80, 0.52), 0)
	vendor_brann = _build_vendor_counter("VendorBrann", VENDOR_BRANN_POINT,
		Color(0.86, 0.62, 0.42), 1)
	vendor_vey = _build_vendor_counter("VendorVey", VENDOR_VEY_POINT,
		Color(0.72, 0.82, 0.96), 2)
	signpost = _build_signpost()

	# Behind every counter, a keeper: a face and a kit, not a service.
	keepers = FolkScript.build(self, {
		"vendor_orla": vendor_orla, "vendor_brann": vendor_brann,
		"vendor_vey": vendor_vey, "recruiter": recruiter_desk,
		"quartermaster": quartermaster_desk,
	})

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
	# The one gold arrow over the town. It rides its own keeper and this scene
	# only decides when it is shown (`_refresh_marker`).
	quest_marker = MarkerScript.new()
	quest_marker.name = "TalkArrow"
	add_child(quest_marker)
	quest_marker.set_label("TALK TO HIM")
	quest_marker.visible = false
	DressingScript.build(self)


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

# --- the keepers' business -------------------------------------------------

## The one mouth of the town. Built after the UI, because it writes the HUD and
## reads the tip channel; re-configured from `embed()` with the world's own tips,
## so the hire line and the campaign's orders come from the same channel the rest
## of the world uses.
func _build_quest_layer(tips) -> void:
	if quest_giver == null:
		quest_giver = QuestGiverScript.new()
		quest_giver.name = "QuestGiver"
		add_child(quest_giver)
	quest_giver.configure(warband, hud, tips)
	if not warband.changed.is_connected(_refresh_marker):
		warband.changed.connect(_refresh_marker)
	_refresh_marker()


## Hang the gold arrow over whichever keeper has business, or put it away. Asked
## on every ledger change, after every `G`, and on a slow clock - the three ways
## "who has something to say" can change without a panel closing.
func _refresh_marker() -> void:
	if quest_marker == null:
		return
	var service: String = quest_giver.marker_service() if quest_giver != null else ""
	var keeper: Node3D = keepers.get(service, null) as Node3D
	if keeper == null or not is_instance_valid(keeper):
		quest_marker.visible = false
		quest_marker.detach()
		return
	quest_marker.visible = true
	if quest_marker.target() != keeper:
		quest_marker.attach_to(keeper, TALK_ARROW_HEIGHT)

## Whether the ledger is carrying the ichor order, which is the one thing the
## square has to point its hint at: a reagent in the stash is useless until a
## player knows the altar is where it is worked.
func _altar_wanted() -> bool:
	return warband != null and warband.quests.is_active(ICHOR_ORDER)

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
## `"vendor_vey"`, `"gate"` or `""`, which is what a single `G` handler and the
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
			# The first G names the hire rows in one tip over the board it is
			# describing. Once that line is offered - and always at the cap, when
			# talk has nothing to say - `G` is the board and nothing else.
			screen.open()
			var hiring := "Hire from the recruiter board: the first eight oaths cost nothing," \
				+ " and every body arms itself out of the shared stash."
			screen.set_status(hiring)
			if quest_giver == null or not quest_giver.talk("recruiter", peer_id):
				hud.set_status(hiring, 5.0)
			else:
				hud.set_status("The recruiter has something to say about the eight.", 4.0)
		"quartermaster":
			_hide_panels()
			if quest_giver != null and quest_giver.talk("quartermaster", peer_id):
				hud.set_status("The quartermaster has an order.", 4.0)
			else:
				quartermaster.open()
				hud.set_status("The quartermaster sells plain steel into the shared stash.", 4.0)
		"vendor_orla":
			_open_vendor(0)
		"vendor_brann":
			_open_vendor(1)
		"vendor_vey":
			_open_vendor(2)
		"gate":
			var gate_state: Dictionary = gate.prompt(peer_id)
			hud.set_status(str(gate_state.get("message", "")), 5.0)
	# The arrow is a question about the ledger, and a press can answer it.
	_refresh_marker()
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
## stride): what decides whether the town's key line or the trail's is the one
## worth showing. `margin` widens the ring, which is what a rule that needs two
## answers - "is it a town body" now, and "has it left for good" - asks with, so a
## body on the line cannot flicker between them.
func in_square(actor, margin: float = 0.0) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var local: Vector3 = actor.global_position - global_position
	var reach: float = WALL_RADIUS + 2.0 + maxf(margin, 0.0)
	return Vector2(local.x, local.z).length() <= reach


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
		"vendor_orla":
			return vendor_orla.global_position
		"vendor_brann":
			return vendor_brann.global_position
		"vendor_vey":
			return vendor_vey.global_position
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
	var text := "O - warband   ·   TAB - weapon set   ·   P - stash and gear   ·   G - use what you stand at"
	match service:
		"stash":
			text = "G - shared stash and paperdoll   ·   O - warband"
		"altar":
			text = "G - the Sacrificial Altar (anoint weapons / unbind / distil / brand)"
		"recruiter":
			text = "G - swear a new body (the first eight are free)"
		"quartermaster":
			text = "G - buy plain steel into the shared stash"
		"vendor_orla":
			text = "G - buy bows and staves, or sell spare gear"
		"vendor_brann":
			text = "G - buy blades and shields, or sell spare gear"
		"vendor_vey":
			text = "G - buy armour, or sell spare gear"
		"gate":
			text = "G - launch an expedition with the line you deployed"
	# A reagent in the stash is worthless until a player knows where it is worked,
	# so while the ichor order is on the ledger the altar is named everywhere.
	if service != "altar" and _altar_wanted():
		text += "   ·   G - the altar anoints with ichor"
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
		"vendor_orla":
			return "G - Storekeeper Orla"
		"vendor_brann":
			return "G - Smith Brann"
		"vendor_vey":
			return "G - Quartermaster Vey"
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
	if vendor_menu != null and vendor_menu.is_open():
		vendor_menu.close()

func _panel_open() -> bool:
	return (screen != null and screen.is_open()) \
		or (paperdoll != null and paperdoll.is_open()) \
		or (altar != null and altar.is_open()) \
		or (quartermaster != null and quartermaster.is_open()) \
		or (vendor_menu != null and vendor_menu.is_open())

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
	# A bow with nothing to shoot is a stick: the band opens with one bunch of
	# shafts in the shared quiver, and every keeper sells more.
	warband.seed_quiver()
	warband.cruor.add(Contracts.CruorTier.T1_RITUAL_TALLOW, 25)
	warband.cruor.add(Contracts.CruorTier.T2_BLACK_BILE, 10)
	warband.cruor.add(Contracts.CruorTier.T3_COAGULATED_CRUOR, 5)
