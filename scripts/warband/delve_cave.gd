extends Node3D
## One descent into the Weeping Hollow: floor I, built when a party goes down and
## freed when it comes back up.
##
## The cave is an instance. Every descent builds a fresh copy of the same authored
## floor - the rock, the light, the watchers in their dens and the demon in the
## lair - at `DelveArea.ORIGIN`, far outside the wood's map, and the climb out
## frees all of it: nothing below outlives the party that went down. The floor is
## deterministic (fixed layout, fixed seeds, fixed names), so a co-op guest builds
## the same cave its host built and the host's mob snapshots land on bodies of the
## same name.
##
## The plan is `delve_layout.gd`: eleven areas in three rings - six shafts on the
## outer rim, each in its own area and each a landing and a rope up; the demons'
## ring of four chambers round the lair, one demon a chamber; and Gorehorn's lair
## at the centre with a squad of demons round it. This node turns the plan into a
## place. The rooms are rasterised onto
## a half-metre grid and every cell that is not floor is rock, merged into as few
## collider boxes as the grid allows, so the squad's map (`squad_nav.gd`) sees the
## same boxes the bodies collide with. The floor is not a box: every room's ground
## is a surface of its own (`delve_floor.gd`), drawn and collided from the same
## vertices, and everything that stands on it - the crowd, the lights, the
## dressing - is set on it, not on a level. What is drawn is more than the boxes: each
## room's own shell carries only the rock nearest it (`Layout.wall_rects`), and
## over it a rock skin, the dripstone and breakdown grown along it and the life
## that moves in it (`delve_rock.gd`, `delve_dressing.gd`, `delve_fauna.gd`), so a
## room - and every light the renderer counts against it - stays local, and a
## room's lights and its life go quiet while the eye is far from it (`LIGHT_NEAR` /
## `LIGHT_FAR`). The air follows the eye from area to area (`_settle_air`).
##
## Watchers wait in their dens - ten bodies for every post a den was written with
## (`Layout.den_members`), and one for every archer (`watcher_archer.gd`) or demon
## (`delve_demon.gd`) it names - and the demons' ring and the lair keep one keeper
## a chamber and a squad of five at the centre. A den sleeps - its bodies stand
## their posts outside the world's hostile list, so nothing in the next room picks a
## fight through rock - until one of its own sees a body, hears a fight or takes a
## blow, or a body walks into the room. Then the whole den wakes at once - the
## archers spring with it - and joins `host.guards`, where the squad, the retarget
## and the session find it like any other hostile.

## A den just woke: `label` is how the HUD names it.
signal den_woke(den_id: String, label: String)
## The floor's master died.
signal master_slain(master_name: String)

const Layout = preload("res://scripts/warband/delve_layout.gd")
const Floor = preload("res://scripts/warband/delve_floor.gd")
const Rock = preload("res://scripts/warband/delve_rock.gd")
const Dressing = preload("res://scripts/warband/delve_dressing.gd")
const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const ArcherScript = preload("res://scripts/warband/watcher_archer.gd")
const DemonScript = preload("res://scripts/warband/delve_demon.gd")
const NavScript = preload("res://scripts/warband/squad_nav.gd")
const MobWander = preload("res://scripts/mob_wander.gd")
const VillageKit = preload("res://scripts/world/village_kit.gd")
const FaunaScript = preload("res://scripts/warband/delve_fauna.gd")
const Loot = preload("res://scripts/warband/delve_loot.gd")
const Perf = preload("res://scripts/perf_probe.gd")

const TITLE := "THE WEEPING HOLLOW"
const FLOOR_LABEL := "FLOOR I"
## How close to a rope a body must stand to climb it.
const EXIT_REACH := 2.6
## The landing: a ring in front of the shaft's rope, one post per body.
const ENTRY_RADIUS := 2.3
const ENTRY_POSTS := 8
## The same lift every body in the world is spawned clear of its ground by.
const SPAWN_LIFT := 0.12
const MASTER_NAME := "HollowMaster"
## The longest a sleeper below may see: the wood's archer is sighted for forty
## metres of open lane, and a cave room is not a lane. A den's archer is held to the
## same bound the floor's other sleepers are (the watchers' 32 m), which is what
## `REST_DISTANCE` is a margin past.
const CAVE_SIGHT := 32.0
## How often the sleepers are asked whether they have noticed anything.
const WAKE_POLL := 0.25
## A sleeper further than this from every standing body of the party is rested
## (`rest`): no brain at all until the party comes back inside. It is past every
## sleeper's sight (the watchers' 22-32 m, the master's 34 m) by more than a
## sprinting body covers between two polls, so nothing a sleeper could have
## seen is missed - and the den still wakes on a blow or a cry, from the poll.
const REST_DISTANCE := 40.0
## A body of a den that has already woken rests when the eye has lost it and the
## nearest party body is this far off. Past the 55 m the squad's own retarget
## reaches, so a resting body is never handed a quarry by the band on the next
## tick, and inside the 96 m the culler hides at, so the two clocks agree on which
## bodies are out of the picture.
const REST_FAR := 60.0
## A body this far inside a den's room wakes it whatever the den has seen.
const WAKE_INSET := 1.5
const PACK_RADIUS := 14.0
const SEED := 4409
## The renderer draws only so many lights a frame: a room's lights burn while the
## eye is within `LIGHT_NEAR` of the room and go out past `LIGHT_FAR` (between the
## two they keep what they had), asked every `LIGHT_POLL` - and at once when the
## eye jumps further than `EYE_JUMP`, as it does on a landing.
const LIGHT_NEAR := 40.0
const LIGHT_FAR := 48.0
const LIGHT_POLL := 0.3
const EYE_JUMP := 8.0
## Past this from the eye a body is not a picture anyone can see: the room's
## lights are already out at `LIGHT_FAR`, the haze is half opaque and three rooms
## of bent tunnel stand between. Every body on the floor used to keep its draw
## list alive in every room of it; this is the one rule that keeps the frame's
## cost tied to the room the eye is in. It is the authored floor's 48 m at the
## plan's own scale (`Layout.SCALE`), which stays past the farthest corner of any
## room - a body in the room the eye stands in is always drawn.
const BODY_HIDE_DISTANCE := 48.0 * Layout.SCALE
## How many of those bodies one poll may put back on the screen when they are the
## faint ones (past `NEAR_REVEAL`): the first draw of a rig is the renderer
## building it, and a room revealed in one batch is the stall the player feels
## when a room "comes into range". Bodies this close are revealed at once - that
## is where the fight is and a body that fades in late is a body you swing at
## wrong.
const NEAR_REVEAL := 40.0
const REVEAL_CHUNK := 12
## How fast the air eases to the next area's, per second.
const AIR_EASE := 1.2

## The world this instance is built into.
var host: Node3D = null
## True on a co-op guest: the bodies are the host's to drive, so they go straight
## onto the hostile list as replicas and nothing here wakes them.
var replica := false
## The squad's map of the floor (`squad_nav.gd`).
var nav = null
## The camera's environment while the eye is below.
var environment: Environment = null
## The floor's master (`delve_demon.gd`), or null once freed.
var master = null
## The floor's small life (`delve_fauna.gd`).
var fauna = null
## The host's dice for the floor's loot table (`delve_loot.gd`): drawn afresh every
## descent, so a rare prize is not always on the same post.
var loot_rng := RandomNumberGenerator.new()

## `{id, label, rect, mobs, awake}` per den, in `Layout.DENS` order, the master's
## own last.
var _dens: Array[Dictionary] = []
var _poll := 0.0
## One node per `Layout.ROOMS` entry, and the lights each room owns.
var _rooms: Array[Node3D] = []
var _room_lights: Array = []
var _room_lit := PackedByteArray()
var _light_clock := 0.0
var _last_eye := Vector3(INF, INF, INF)
## The area whose air the eye is in (`CaveKit.AREAS` key).
var _air_area := "mouth"


# --- reading ---------------------------------------------------------------

## Where a shaft's rope hangs, in the world.
func rope_point(landing_id: String) -> Vector3:
	return to_global(_landing(landing_id)["rope"])


## The shaft whose rope a body stands close enough to climb, or "".
func exit_at(actor) -> String:
	if actor == null or not is_instance_valid(actor):
		return ""
	var at: Vector3 = (actor as Node3D).global_position
	for landing in Layout.LANDINGS:
		if at.distance_to(to_global(landing["rope"])) <= EXIT_REACH:
			return str(landing["id"])
	return ""


## Whether a body stands close enough to any rope to climb it.
func at_exit(actor) -> bool:
	return not exit_at(actor).is_empty()


## Whether a world point is inside this instance: under its roof and over its
## floor. The eye is asked this every frame, so it is a box test.
func contains(point: Vector3) -> bool:
	var local := point - global_position
	if local.y < Floor.LOW - 3.0 or local.y > Layout.TOP + 6.0:
		return false
	return Layout.BOUNDS.has_point(Vector2(local.x, local.z))


## The ground a party lands on at one shaft, in the world, one post per body. Each
## post stands on the floor there (`delve_floor.gd`): the ring is dressed flat, so
## a body lands on the level it walked into.
func entry_posts(landing_id: String, count: int) -> Array[Vector3]:
	var centre: Vector3 = _landing(landing_id)["centre"]
	var out: Array[Vector3] = []
	for index in maxi(1, count):
		var angle := TAU * float(index % ENTRY_POSTS) / float(ENTRY_POSTS)
		var radius := ENTRY_RADIUS + 1.2 * float(index / ENTRY_POSTS)
		var x := centre.x + cos(angle) * radius
		var z := centre.z + sin(angle) * radius
		out.append(to_global(Vector3(x, Floor.height(x, z) + SPAWN_LIFT, z)))
	return out


## The way a body landed at a shaft faces: out of its chamber.
func entry_yaw(landing_id: String) -> float:
	return float(_landing(landing_id)["yaw"])


## The area (`Layout.AREAS` key) a world point stands in, or "" in the rock.
func area_at(point: Vector3) -> String:
	var local := to_local(point)
	return Layout.area_at(Vector2(local.x, local.z))


## The rope a body at a world point reaches by the shortest walk: `{id, area,
## metres}`, or {} from inside the rock.
func nearest_rope(point: Vector3) -> Dictionary:
	var local := to_local(point)
	return Layout.nearest_landing(Vector2(local.x, local.z))


## Every hostile this floor fielded, the master included.
func mobs() -> Array:
	var out: Array = []
	for den in _dens:
		out.append_array(den["mobs"])
	return out


## One den's bodies (`Layout.DENS` id, or "lair" for the master).
func den_mobs(den_id: String) -> Array:
	for den in _dens:
		if str(den["id"]) == den_id:
			return den["mobs"]
	return []


## Hostiles still standing.
func living() -> int:
	var count := 0
	for mob in mobs():
		if is_instance_valid(mob) and bool(mob.get("alive")):
			count += 1
	return count


func master_alive() -> bool:
	return master != null and is_instance_valid(master) and bool(master.get("alive"))


## Whether a den has woken (`id` from `Layout.DENS`, or "lair" for the master).
func is_awake(den_id: String) -> bool:
	for den in _dens:
		if str(den["id"]) == den_id:
			return bool(den["awake"])
	return false


## Every light the floor owns.
func light_count() -> int:
	var count := 0
	for lights in _room_lights:
		count += (lights as Array).size()
	return count


## The floor's lights burning now: the ones in rooms near the eye.
func lit_count() -> int:
	var count := 0
	for lights in _room_lights:
		for lamp in lights:
			if is_instance_valid(lamp) and (lamp as Light3D).visible:
				count += 1
	return count


## Whether a room's lights are burning: the eye is near it, so its life moves.
func room_lit(index: int) -> bool:
	return index >= 0 and index < _room_lit.size() and _room_lit[index] != 0


func _landing(landing_id: String) -> Dictionary:
	var found := Layout.landing(landing_id)
	return found if not found.is_empty() else Layout.LANDINGS[0]


# --- the build ---------------------------------------------------------------

## The floor is in the world and whole.
signal floor_built

## False until the last step of `build`/`build_staged` has run. A descent that is
## being built across frames (`built_share`) is not a floor anybody can stand on.
var built := false
## How much of the build is done, 0..1, for the line the player reads while it
## happens.
var built_share := 0.0
## How long one staged frame may spend on the build. A loading frame is not a
## playing frame, but the window still has to paint and the eye still has to move.
const BUILD_FRAME_USEC := 14000

var _steps: Array[Callable] = []
var _step_index := 0


## Build the floor into `world` in one call. The node must already be in the tree
## at its own origin: the rock's colliders, the mobs' homes and the squad's map
## are all read in world space. A descent in the running game uses
## `build_staged` instead - the same steps, a few per frame - so no frame ever
## stops for the two to four seconds this costs.
func build(world: Node3D, as_replica: bool = false) -> void:
	_plan_build(world, as_replica)
	Perf.begin("build")
	while _step_index < _steps.size():
		Perf.begin(_step_name(_step_index))
		(_steps[_step_index] as Callable).call()
		Perf.end()
		_step_index += 1
	Perf.end()
	built = true
	built_share = 1.0
	floor_built.emit()


## The same build, a few steps a frame: the window keeps painting (and the HUD
## line keeps counting) while the floor comes up. `built` is the signal that the
## party may step onto it.
##
## The physics clock is held to two steps a frame while it runs: a build frame is
## longer than a playing one, and left alone the engine pays the debt back as a
## burst of eight steps on one frame - a hundred and seventy milliseconds of a
## stall on the frame the floor was finished, which is the freeze this replaces.
func build_staged(world: Node3D, as_replica: bool = false, warm_room: String = "") -> void:
	_plan_build(world, as_replica)
	built = false
	built_share = 0.0
	var steps_allowance := Engine.max_physics_steps_per_frame
	Engine.max_physics_steps_per_frame = 2
	while _step_index < _steps.size():
		var started := Time.get_ticks_usec()
		while _step_index < _steps.size() \
				and Time.get_ticks_usec() - started < BUILD_FRAME_USEC:
			(_steps[_step_index] as Callable).call()
			_step_index += 1
		built_share = float(_step_index) / float(_steps.size())
		await get_tree().process_frame
	built = true
	built_share = 1.0
	# The warm frames are heavy render work of their own; the clock stays held
	# until they are done, or the engine pays the whole load back in one burst of
	# steps on the frame the eye lands.
	await _warm_view(warm_room)
	Engine.max_physics_steps_per_frame = steps_allowance
	floor_built.emit()


## Draw the room the party is about to land in, once, while the loading line is
## still up. Every material, mesh and rig in it is drawn for the first time on
## some frame, and that frame is the renderer building them: a hundred and fifty
## milliseconds if it lands on the frame the eye arrives in the cave. A camera of
## our own spends it here instead, where the line is already counting, and the
## eye's own first frame in the Hollow is a warm one.
func _warm_view(room_id: String) -> void:
	var index := Layout.room_index(room_id)
	if index < 0 or not is_inside_tree():
		return
	var rect: Rect2 = Layout.ROOMS[index]["rect"]
	var centre := rect.get_center()
	var at := to_global(Vector3(centre.x, Floor.height(centre.x, centre.y) + 2.2, centre.y))
	var previous := get_viewport().get_camera_3d()
	var warm := Camera3D.new()
	warm.fov = 85.0
	warm.far = 200.0
	add_child(warm)
	warm.global_position = at
	var goal := Vector3(centre.x, 0.0, rect.end.y)
	warm.look_at(to_global(Vector3(goal.x, Floor.height(goal.x, goal.z) + 1.0, goal.z)), Vector3.UP)
	warm.current = true
	# The floor's air goes on the host camera for these frames as well: the
	# environment itself is a thing the renderer builds the first time an eye
	# looks through it.
	var host_camera: Camera3D = host.get("camera") if host != null else null
	var air_seen: Environment = host_camera.environment if host_camera != null else null
	if host_camera != null:
		host_camera.environment = environment
	# Every lamp on for these frames: a room's light count is a shader variant,
	# and the frame a room's lamps come up is the frame the renderer builds it.
	for lamps in _room_lights:
		for lamp in lamps:
			if is_instance_valid(lamp):
				(lamp as Light3D).visible = true
	# The culler runs off a camera, so this is also the poll that reveals the
	# bodies standing in this room - and so the poll that draws them first.
	await get_tree().process_frame
	cull_bodies(warm.global_position)
	await get_tree().process_frame
	await get_tree().process_frame
	_sync_lights(true)
	if host_camera != null:
		host_camera.environment = air_seen
	if is_instance_valid(previous):
		previous.current = true
	warm.queue_free()


## What a step is called in the profiler: the heavy stages keep the names the
## one-shot build measured, and the per-room steps report under the stage they
## belong to.
func _step_name(index: int) -> String:
	var share := float(index) / float(maxi(_steps.size(), 1))
	if share < 0.7:
		return "build.rock"
	return "build.mobs"


## The ordered steps. One per room for the rock, its dressing and its crowd, so a
## frame's share of the build is a room and not a hundred of them.
func _plan_build(world: Node3D, as_replica: bool) -> void:
	_steps.clear()
	_step_index = 0
	host = world
	replica = as_replica
	loot_rng.randomize()
	_steps.append(_step_environment)
	_steps.append(_rock_start)
	for index in Layout.ROOMS.size():
		_steps.append(_rock_room.bind(index))
	_steps.append(_rock_end)
	for index in Layout.ROOMS.size():
		_steps.append(_dress_room.bind(index))
	_steps.append(_build_ropes)
	_steps.append(_build_lights)
	_steps.append(_build_props)
	_steps.append(_mobs_start)
	for spec in Layout.DENS:
		_steps.append(_build_den.bind(spec))
	_steps.append(_mobs_end)
	_steps.append(_build_fauna)
	_steps.append(_build_nav)
	_steps.append(_finish_build)


func _step_environment() -> void:
	_build_environment()


func _dress_room(index: int) -> void:
	Dressing.dress_room(_rooms[index], index)


func _build_fauna() -> void:
	fauna = FaunaScript.new()
	fauna.name = "Fauna"
	add_child(fauna)
	fauna.build(self, _room_lights)


func _build_nav() -> void:
	nav = NavScript.new()
	var bounds := Layout.BOUNDS
	# The map reads the colliders against the ground they stand on, which below is
	# a surface and not a slab: the floor's own field, in world space.
	var ground := func(x: float, z: float) -> float:
		return Floor.height(x - global_position.x, z - global_position.z) + global_position.y
	nav.build(self, Rect2(global_position.x + bounds.position.x, global_position.z + bounds.position.y,
		bounds.size.x, bounds.size.y), [], ground)


func _finish_build() -> void:
	_sync_lights(true)
	_settle_air(1.0)


## Underground: no sky, a dim ambient that keeps rock readable between the torches,
## and a close haze so the far end of a hall is a guess. Both take the colour of the
## area the eye is in (`CaveKit.AREAS` fog/ambient), easing over as it walks
## through.
func _build_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.010, 0.009)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.48, 0.44, 0.40)
	environment.ambient_light_energy = 1.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.10, 0.085, 0.07)
	environment.fog_light_energy = 0.8
	environment.fog_sky_affect = 0.0
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	# Godot 4.7 resets the density when the mode is written: the density goes last.
	# The haze is authored at the plan's drawn size. The floor is built `SCALE` times
	# it, and a density `SCALE` times thinner fogs twice the distance exactly as far.
	environment.fog_density = 0.016 / Layout.SCALE
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.35
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 0.95
	environment.adjustment_contrast = 1.06
	environment.adjustment_brightness = 1.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.5
	environment.glow_bloom = 0.08
	environment.glow_hdr_threshold = 1.1


## The rock: a collider box for every run of grid that is not floor, a ceiling
## over every room, and each room's own floor (`_floor_collider`) - the ground is
## a surface, not a slab, and what a body walks on is the very mesh the eye sees
## (`delve_floor.gd`). Each room's node draws its own floor, roof and the rock
## nearest it in its area's stone. Split into a start, a step a room and an end, so
## a descent can build it across frames (`build_staged`) instead of stopping the
## game for one.
var _rock_solids: StaticBody3D = null
var _rock_walls: Array = []

func _rock_start() -> void:
	var solids := StaticBody3D.new()
	solids.name = "Rock"
	solids.collision_layer = 1
	solids.collision_mask = 0
	add_child(solids)
	_rock_solids = solids
	# A bed of rock under the whole floor, deep enough that nothing which somehow
	# left the ground falls out of the world. The floor itself is above this.
	var bounds := Layout.BOUNDS
	_box_collider(solids, Vector3(bounds.size.x, 1.0, bounds.size.y),
		Vector3(bounds.get_center().x, Floor.LOW - 3.5, bounds.get_center().y))
	_rock_walls = Layout.wall_rects()
	_room_lit.resize(Layout.ROOMS.size())
	_room_lit.fill(1)


func _rock_room(index: int) -> void:
	var room: Dictionary = Layout.ROOMS[index]
	var node := Node3D.new()
	node.name = "Room_%s" % str(room["id"])
	add_child(node)
	_rooms.append(node)
	_room_lights.append([])
	var stone: Dictionary = Dressing.stone(str(room["area"]))
	var shell := VillageKit.Merged.new()
	var rect: Rect2 = room["rect"]
	var top: float = Rock.ceiling(index)
	shell.add(Floor.mesh(index), Transform3D.IDENTITY, stone["floor"])
	var ceiling := Vector3(rect.size.x, maxf(0.05, Layout.TOP - top), rect.size.y)
	var ceiling_at := Vector3(rect.get_center().x, (top + Layout.TOP) * 0.5, rect.get_center().y)
	VillageKit.add_box(shell, ceiling, ceiling_at, stone["roof"])
	_box_collider(_rock_solids, ceiling, ceiling_at)
	# The wall's rock reaches down to the lowest the floor can be anywhere on the
	# floor: a hall cut into ground that has fallen away still stands in rock.
	var tall := Layout.TOP - Floor.LOW
	for block in _rock_walls[index]:
		var wall: Rect2 = block
		VillageKit.add_box(shell, Vector3(wall.size.x, tall, wall.size.y),
			Vector3(wall.get_center().x, (Layout.TOP + Floor.LOW) * 0.5, wall.get_center().y), stone["wall"])
	shell.commit(node, "Shell", false)
	_floor_collider(index)


## The ground of one room, as the physics of the ground: the same vertices the room
## draws, so a foot, an arrow or a thrown blade stops exactly on the surface under
## it, dips and mounds and all.
func _floor_collider(index: int) -> void:
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(Floor.faces(index))
	var holder := CollisionShape3D.new()
	holder.shape = shape
	_rock_solids.add_child(holder)


func _rock_end() -> void:
	for block in Layout.rock_rects():
		_box_collider(_rock_solids, Vector3(block.size.x, Layout.TOP - Floor.LOW, block.size.y),
			Vector3(block.get_center().x, (Layout.TOP + Floor.LOW) * 0.5, block.get_center().y))


func _box_collider(solids: StaticBody3D, size: Vector3, at: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var holder := CollisionShape3D.new()
	holder.shape = shape
	holder.position = at
	solids.add_child(holder)


## Every shaft's rope and the night that falls down it.
func _build_ropes() -> void:
	for landing in Layout.LANDINGS:
		var index := Layout.room_index(str(landing["room"]))
		var rope_at: Vector3 = landing["rope"]
		_own(index, Dressing.rope(_rooms[index], landing, Rock.roof_height(index, rope_at.x, rope_at.z)))


func _build_lights() -> void:
	for order in Layout.LIGHTS.size():
		var spec: Dictionary = Layout.LIGHTS[order]
		var index := Layout.room_index(str(spec["room"]))
		_own(index, Dressing.light(_rooms[index], spec, SEED + 11 + order * 13))


## What each area is read from: one merged prop mesh per room, the kit pieces that
## stand on their own, and a `Solids` body per room for whatever stops a body.
func _build_props() -> void:
	var clutter := {}
	var solids := {}
	for order in Layout.PROPS.size():
		var spec: Dictionary = Layout.PROPS[order]
		var index := Layout.room_index(str(spec["room"]))
		if not clutter.has(index):
			clutter[index] = VillageKit.Merged.new()
			solids[index] = _solids(_rooms[index], "Solids")
		_own(index, Dressing.prop(_rooms[index], clutter[index], solids[index], spec, SEED + 501 + order * 17))
	for index in clutter:
		clutter[index].commit(_rooms[index], "Props", false)


func _solids(parent: Node3D, label: String) -> StaticBody3D:
	var solids := StaticBody3D.new()
	solids.name = label
	solids.collision_layer = 1
	solids.collision_mask = 0
	parent.add_child(solids)
	return solids


func _own(index: int, lights: Array) -> void:
	if index < 0:
		return
	(_room_lights[index] as Array).append_array(lights)


# --- the lights --------------------------------------------------------------

func _process(delta: float) -> void:
	Perf.begin("delve.cave")
	_tick_air(delta)
	Perf.end()


func _tick_air(delta: float) -> void:
	_light_clock += delta
	var jumped := false
	if _light_clock < LIGHT_POLL:
		var camera := get_viewport().get_camera_3d()
		jumped = camera != null and camera.global_position.distance_to(_last_eye) >= EYE_JUMP
		if not jumped:
			_settle_air(delta)
			return
	_light_clock = 0.0
	_sync_lights(false)
	# A landing puts the eye in new air at once; a walk eases into it.
	_settle_air(1.0 / AIR_EASE if jumped else delta)


## Light the rooms near the eye and put out the rest, and note the area the eye is
## in. A room without lights is still marked near or far: its life moves only near.
## With no camera there is nothing to save, and every light keeps burning.
func _sync_lights(force: bool) -> void:
	if not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_last_eye = camera.global_position
	var eye := to_local(_last_eye)
	var flat := Vector2(eye.x, eye.z)
	var area := Layout.area_at(flat)
	if not area.is_empty():
		_air_area = area
	for index in _room_lights.size():
		var rect: Rect2 = Layout.ROOMS[index]["rect"]
		var gap := Vector2(maxf(maxf(rect.position.x - flat.x, flat.x - rect.end.x), 0.0),
			maxf(maxf(rect.position.y - flat.y, flat.y - rect.end.y), 0.0)).length()
		var lit := _room_lit[index] != 0
		var want := lit
		if gap <= LIGHT_NEAR:
			want = true
		elif gap > LIGHT_FAR:
			want = false
		if want == lit and not force:
			continue
		_room_lit[index] = 1 if want else 0
		for lamp in _room_lights[index]:
			if is_instance_valid(lamp):
				(lamp as Light3D).visible = want
	cull_bodies(_last_eye)


## Hide the bodies the eye cannot reach, on the clock the lights already keep:
## the same 48 m, the same poll, the same jump. A hidden body keeps its brain,
## its collision and its clock - this only asks it to stop drawing and stop
## posing, which is what the whole floor's rigs were doing in rooms nobody stood
## in. `eye` is world space.
##
## Reveals are staged: a body the eye has just reached is drawn for the first
## time in its life, and the renderer builds its instances and its pipelines on
## that frame - a room's worth revealed in one poll was a hundred and fifty
## milliseconds of stall, which the player reads as the game loading what is
## coming into range. So only the bodies close enough to fight are revealed at
## once; the faint ones past `NEAR_REVEAL` come in `REVEAL_CHUNK` at a time.
func cull_bodies(eye: Vector3) -> void:
	Perf.begin("delve.cull")
	var reach := BODY_HIDE_DISTANCE * BODY_HIDE_DISTANCE
	var near := NEAR_REVEAL * NEAR_REVEAL
	var revealed := 0
	for den in _dens:
		for mob in den["mobs"]:
			if not is_instance_valid(mob) or not mob.has_method("set_culled"):
				continue
			var gap: float = (mob as Node3D).global_position.distance_squared_to(eye)
			if gap > reach:
				mob.set_culled(true)
			elif not bool(mob.get("culled")):
				continue
			elif gap <= near or revealed < REVEAL_CHUNK:
				revealed += 1
				mob.set_culled(false)
	Perf.end()


## Ease the haze and the ambient toward the air of the area the eye is in.
func _settle_air(delta: float) -> void:
	if environment == null:
		return
	var spec: Dictionary = CaveKit.AREAS.get(_air_area, CaveKit.AREAS["mouth"])
	var k := clampf(delta * AIR_EASE, 0.0, 1.0)
	environment.fog_light_color = environment.fog_light_color.lerp(spec["fog"], k)
	environment.ambient_light_color = environment.ambient_light_color.lerp(spec["ambient"], k)
	environment.fog_density = lerpf(environment.fog_density, float(spec["haze"]) / Layout.SCALE, k)


# --- the hostiles ------------------------------------------------------------

var _mobs_root: Node3D = null

func _mobs_start() -> void:
	_mobs_root = Node3D.new()
	_mobs_root.name = "Mobs"
	add_child(_mobs_root)


func _build_den(spec: Dictionary) -> void:
	var members: Array = []
	var index := 0
	var tag := str(spec["id"]).replace("_", " ").capitalize().replace(" ", "")
	for row in Layout.den_members(spec):
		index += 1
		var at: Vector3 = row["at"]
		var face: Vector3 = row["face"]
		var yaw := atan2(-(face.x - at.x), -(face.z - at.z))
		var species := str(row["species"])
		if bool(row.get("demon", false)):
			members.append(_spawn_demon(_mobs_root, "Demon%s%d" % [tag, index], species, at, yaw))
		elif bool(row.get("bow", false)):
			members.append(_spawn_archer(_mobs_root, "Hollow%s%d" % [tag, index], species, at, yaw))
		else:
			members.append(_spawn_watcher(_mobs_root, "Hollow%s%d" % [tag, index], species, at, yaw))
	MobWander.assign_all(members, PACK_RADIUS)
	# A body stands its post asleep, not simulating until the poll has had a
	# look at where the party landed. Built awake, a floor's 298 bodies all ran
	# their brains, senses and a swept collision for the first frames under the
	# player's feet - the engine's own catch-up then spent eight physics steps a
	# frame doing it, which is a second of freeze in anybody's hands.
	for mob in members:
		if not is_instance_valid(mob):
			continue
		# Hidden first, shown by the culler a few at a time: a body is drawn for
		# the first time on the frame it is revealed, and that is where the
		# renderer builds it.
		if mob.has_method("set_culled"):
			mob.set_culled(true)
		if mob.has_method("rest"):
			mob.rest(true)
	_dens.append({"id": str(spec["id"]), "label": str(spec["label"]),
		"rect": Layout.room(str(spec["room"]))["rect"], "mobs": members, "awake": false})


func _mobs_end() -> void:
	master = DemonScript.new()
	master.boss = true
	master.name = MASTER_NAME
	master.position = Floor.lift(Layout.MASTER_POINT) + Vector3(0.0, SPAWN_LIFT, 0.0)
	master.rotation.y = Layout.MASTER_YAW
	_mobs_root.add_child(master)
	master.home = master.global_position
	master.safe_center = _safe_center()
	_wire(master)
	master.defeated.connect(_on_master_defeated)
	if master.has_method("set_culled"):
		master.set_culled(true)
	if master.has_method("rest"):
		master.rest(true)
	_dens.append({"id": "lair", "label": "Gorehorn rises from the blood.",
		"rect": Layout.room(Layout.MASTER_ROOM)["rect"], "mobs": [master], "awake": false})
	if replica:
		# The host drives every body: a guest's copies are replicas from their
		# first frame and are on the hostile list so the snapshots find them.
		for mob in mobs():
			_enlist(mob)


func _spawn_watcher(parent: Node3D, label: String, species: String, at: Vector3, yaw: float):
	var watcher = WatcherScript.new()
	watcher.name = label
	watcher.mob_id = species
	watcher.position = Floor.lift(at) + Vector3(0.0, SPAWN_LIFT, 0.0)
	watcher.rotation.y = yaw
	parent.add_child(watcher)
	watcher.home = watcher.global_position
	watcher.safe_center = _safe_center()
	_wire(watcher)
	return watcher


## One of the hollow wardens with a bow (`watcher_archer.gd`): the same body on the
## same post, with the den's post as its anchor and the floor's own sight. It never
## closes to blade reach - it holds a ring 8-16 m out and puts real shafts through
## the air - and it is hidden until its den wakes (`_wake` springs it), so a body
## that has not noticed the party does not start shooting at it.
func _spawn_archer(parent: Node3D, label: String, species: String, at: Vector3, yaw: float):
	var archer = ArcherScript.new()
	archer.name = label
	archer.mob_id = species
	archer.position = Floor.lift(at) + Vector3(0.0, SPAWN_LIFT, 0.0)
	archer.rotation.y = yaw
	parent.add_child(archer)
	archer.home = archer.global_position
	archer.safe_center = _safe_center()
	archer.set_anchor(archer.global_position)
	archer.host = host
	archer.profile["sight"] = minf(float(archer.profile.get("sight", CAVE_SIGHT)), CAVE_SIGHT)
	_wire(archer)
	return archer


## One of the floor's demons (`delve_demon.gd`): a keeper of the ring, or one of the
## squad in the lair. It keeps its post like everything else below - it is given a
## name the host and a guest both build, a safe ring and the world's kill wiring -
## and it bleeds the altar's essence when it falls (`demon`).
func _spawn_demon(parent: Node3D, label: String, species: String, at: Vector3, yaw: float):
	var demon = DemonScript.new()
	demon.name = label
	demon.mob_id = species
	demon.position = Floor.lift(at) + Vector3(0.0, SPAWN_LIFT, 0.0)
	demon.rotation.y = yaw
	parent.add_child(demon)
	demon.home = demon.global_position
	demon.safe_center = _safe_center()
	_wire(demon)
	return demon


func _wire(mob) -> void:
	if replica or host == null:
		return
	if host.has_method("_on_enemy_defeated"):
		mob.defeated.connect(_on_mob_defeated)
	if host.has_method("_on_enemy_attack"):
		mob.attacked.connect(Callable(host, "_on_enemy_attack"))


## A body below falls: the floor's loot table settles what it leaves, then the
## world pays and books the kill exactly as it does above.
func _on_mob_defeated(enemy, reward: int) -> void:
	if is_instance_valid(enemy):
		Loot.settle(enemy, enemy == master or (enemy.has_method("demon") and bool(enemy.demon())),
			loot_rng)
	host._on_enemy_defeated(enemy, reward)


## The town's ring is the one ground nobody hunts on; the cave is nowhere near it.
func _safe_center() -> Vector3:
	var town = host.get("town") if host != null else null
	if town != null and is_instance_valid(town):
		return (town as Node3D).global_position
	return Vector3(0.0, 0.0, 1.0e6)


func _enlist(mob) -> void:
	if host == null or not is_instance_valid(mob):
		return
	var guards = host.get("guards")
	if guards is Array and not (guards as Array).has(mob):
		(guards as Array).append(mob)


## The host's clock: wake any den that has noticed the party. `party` is every
## standing body of the party below.
func tick(delta: float, party: Array) -> void:
	if replica:
		return
	_poll += delta
	if _poll < WAKE_POLL:
		return
	_poll = 0.0
	var standing: Array[CharacterBody3D] = []
	for body in party:
		if body is CharacterBody3D and is_instance_valid(body) and bool(body.get("alive")) \
				and not bool(body.get("downed")):
			standing.append(body)
	for den in _dens:
		if bool(den["awake"]):
			_rest_the_quiet(den, standing)
			continue
		if _den_noticed(den, standing):
			_wake(den, standing)
			continue
		# Asleep, but with its eyes open: every sleeper watches the nearest body,
		# so what wakes it is its own sight cone and the rock between - never
		# distance through a wall. A sleeper too far to see anybody rests.
		for mob in den["mobs"]:
			if is_instance_valid(mob) and bool(mob.get("alive")):
				var prey = _nearest(mob.global_position, standing)
				mob.player = prey
				var gap: float = mob.global_position.distance_to(prey.global_position) \
					if prey != null else INF
				mob.rest(gap > REST_DISTANCE, gap)


## A den that has woken does not keep thinking for the rest of the descent. A body
## of it that the eye has lost (`culled`, past `BODY_HIDE_DISTANCE`) and that no
## body of the party stands within `REST_FAR` of rests again - the rest a sleeper
## is already on, which is exactly "nothing can see it and it can see nothing". The
## party coming back inside `REST_DISTANCE` lifts it on the next poll (0.25 s, a
## metre and a half of walking), so nothing that could have been seen is missed;
## a blow lifts it at once (`take_damage` -> `mob_wake`).
##
## Without this an awake set only ever grew: a party that walked the floor woke
## every den it passed and paid for every body of every one of them until it
## climbed out - two hundred bodies sweeping collision and two hundred brains on
## the frame budget in rooms nobody stood in.
func _rest_the_quiet(den: Dictionary, standing: Array[CharacterBody3D]) -> void:
	for mob in den["mobs"]:
		if not is_instance_valid(mob) or not bool(mob.get("alive")):
			continue
		if not mob.has_method("rest"):
			continue
		var prey = _nearest(mob.global_position, standing)
		var gap: float = mob.global_position.distance_to(prey.global_position) \
			if prey != null else INF
		if bool(mob.get("culled")) and gap > REST_FAR:
			mob.rest(true, gap)
		elif gap <= REST_DISTANCE or not bool(mob.get("culled")):
			mob.rest(false, gap)


func _den_noticed(den: Dictionary, standing: Array[CharacterBody3D]) -> bool:
	for mob in den["mobs"]:
		if not is_instance_valid(mob):
			continue
		if not bool(mob.get("alive")) or float(mob.get("health")) < float(mob.get("max_health")) - 0.01:
			return true
		if mob.alerted():
			return true
	var inner := (den["rect"] as Rect2).grow(-WAKE_INSET)
	for body in standing:
		var local := to_local(body.global_position)
		if inner.has_point(Vector2(local.x, local.z)):
			return true
	return false


## The whole den at once: onto the hostile list, each body on the nearest of the
## party, and one line for the HUD.
func _wake(den: Dictionary, standing: Array[CharacterBody3D]) -> void:
	Perf.begin("delve.wake")
	den["awake"] = true
	for mob in den["mobs"]:
		if not is_instance_valid(mob) or not bool(mob.get("alive")):
			continue
		mob.rest(false)
		_enlist(mob)
		var prey = _nearest(mob.global_position, standing)
		if prey != null:
			mob.targets = standing
			# An archer is ambush-first: `hunt` is refused until its ambush is
			# sprung, and the whole den waking at once is the spring.
			if mob.has_method("begin_ambush"):
				mob.begin_ambush(prey)
			else:
				mob.hunt(prey)
	den_woke.emit(str(den["id"]), str(den["label"]))
	Perf.end()


func _nearest(point: Vector3, standing: Array[CharacterBody3D]):
	var best = null
	var best_distance := INF
	for body in standing:
		var distance := point.distance_to(body.global_position)
		if distance < best_distance:
			best_distance = distance
			best = body
	return best


func _on_master_defeated(_enemy, _reward: int) -> void:
	master_slain.emit(str(master.get_display_name()) if is_instance_valid(master) else "Gorehorn")


# --- leaving ---------------------------------------------------------------

## Take this floor out of the world: its bodies off the hostile list, every drop
## and missile still lying inside it freed with it, and every body left in it -
## the party's own dead included - no longer a container. The cave's own nodes -
## rock, light, corpses, ragdolls - go with the node.
func teardown() -> void:
	if host != null and is_instance_valid(host):
		var guards = host.get("guards")
		if guards is Array:
			for mob in mobs():
				(guards as Array).erase(mob)
		for list_name in ["pickups", "projectiles"]:
			var list = host.get(list_name)
			if not (list is Array):
				continue
			for index in range((list as Array).size() - 1, -1, -1):
				var node = (list as Array)[index]
				if not is_instance_valid(node):
					(list as Array).remove_at(index)
					continue
				if node is Node3D and contains((node as Node3D).global_position):
					(list as Array).remove_at(index)
					(node as Node).queue_free()
		var loot = host.get("loot")
		if loot != null and is_instance_valid(loot) and loot.has_method("pickups"):
			for pickup in loot.pickups():
				if is_instance_valid(pickup) and contains(pickup.global_position):
					pickup.queue_free()
			# The party's dead stay below, and so does whatever nobody took back
			# off them: no body down here is a container once the floor is gone.
			for corpse_id in loot.corpse_ids():
				if contains(loot.corpse_position(corpse_id)):
					loot.forget_corpse(corpse_id)
	_dens.clear()
	master = null
	queue_free()
