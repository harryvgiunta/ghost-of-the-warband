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
## The plan is `delve_layout.gd`: ten areas round Gorehorn's lair, built for more
## than one party - six shafts on the rim, each in its own area, each a landing and
## a rope up. This node turns the plan into a place. The rooms are rasterised onto
## a half-metre grid and every cell that is not floor is rock, merged into as few
## collider boxes as the grid allows, so the squad's map (`squad_nav.gd`) sees the
## same boxes the bodies collide with. What is drawn is more than the boxes: each
## room's own shell carries only the rock nearest it (`Layout.wall_rects`), and
## over it a rock skin, the dripstone and breakdown grown along it and the life
## that moves in it (`delve_rock.gd`, `delve_dressing.gd`, `delve_fauna.gd`), so a
## room - and every light the renderer counts against it - stays local, and a
## room's lights and its life go quiet while the eye is far from it (`LIGHT_NEAR` /
## `LIGHT_FAR`). The air follows the eye from area to area (`_settle_air`).
##
## Watchers wait in eight dens - ten bodies for every post a den was written with
## (`Layout.den_members`) - and the demon in the lair. A den sleeps - its bodies
## stand their posts outside the world's hostile list, so nothing in the next room
## picks a fight through rock - until one of its own sees a body, hears a fight or
## takes a blow, or a body walks into the room. Then the whole den wakes at once
## and joins `host.guards`, where the squad, the retarget and the session find it
## like any other hostile.

## A den just woke: `label` is how the HUD names it.
signal den_woke(den_id: String, label: String)
## The floor's master died.
signal master_slain(master_name: String)

const Layout = preload("res://scripts/warband/delve_layout.gd")
const Dressing = preload("res://scripts/warband/delve_dressing.gd")
const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
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
## How often the sleepers are asked whether they have noticed anything.
const WAKE_POLL := 0.25
## A sleeper further than this from every standing body of the party is rested
## (`rest`): no brain at all until the party comes back inside. It is past every
## sleeper's sight (the watchers' 22-32 m, the master's 34 m) by more than a
## sprinting body covers between two polls, so nothing a sleeper could have
## seen is missed - and the den still wakes on a blow or a cry, from the poll.
const REST_DISTANCE := 40.0
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

## `{id, label, rect, mobs, awake}` per den, in `Layout.DENS` order, the lair last.
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
	if local.y < -6.0 or local.y > Layout.TOP + 6.0:
		return false
	return Layout.BOUNDS.has_point(Vector2(local.x, local.z))


## The ground a party lands on at one shaft, in the world, one post per body.
func entry_posts(landing_id: String, count: int) -> Array[Vector3]:
	var centre: Vector3 = _landing(landing_id)["centre"]
	var out: Array[Vector3] = []
	for index in maxi(1, count):
		var angle := TAU * float(index % ENTRY_POSTS) / float(ENTRY_POSTS)
		var radius := ENTRY_RADIUS + 1.2 * float(index / ENTRY_POSTS)
		out.append(to_global(centre + Vector3(cos(angle) * radius, SPAWN_LIFT, sin(angle) * radius)))
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

## Build the floor into `world`. The node must already be in the tree at its own
## origin: the rock's colliders, the mobs' homes and the squad's map are all read
## in world space.
func build(world: Node3D, as_replica: bool = false) -> void:
	host = world
	replica = as_replica
	loot_rng.randomize()
	_build_environment()
	_build_rock()
	for index in Layout.ROOMS.size():
		Dressing.dress_room(_rooms[index], index)
	_build_ropes()
	_build_lights()
	_build_props()
	_build_mobs()
	fauna = FaunaScript.new()
	fauna.name = "Fauna"
	add_child(fauna)
	fauna.build(self, _room_lights)
	nav = NavScript.new()
	var bounds := Layout.BOUNDS
	nav.build(self, Rect2(global_position.x + bounds.position.x, global_position.z + bounds.position.y,
		bounds.size.x, bounds.size.y), [], global_position.y)
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
	environment.fog_density = 0.016
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


## The rock: one floor slab under everything, a collider box for every run of grid
## that is not floor, and a ceiling over every room. Each room's node draws its
## own floor, roof and the rock nearest it in its area's stone.
func _build_rock() -> void:
	var solids := StaticBody3D.new()
	solids.name = "Rock"
	solids.collision_layer = 1
	solids.collision_mask = 0
	add_child(solids)
	var bounds := Layout.BOUNDS
	_box_collider(solids, Vector3(bounds.size.x, 1.0, bounds.size.y),
		Vector3(bounds.get_center().x, -0.5, bounds.get_center().y))
	var walls: Array = Layout.wall_rects()
	for index in Layout.ROOMS.size():
		var room: Dictionary = Layout.ROOMS[index]
		var node := Node3D.new()
		node.name = "Room_%s" % str(room["id"])
		add_child(node)
		_rooms.append(node)
		_room_lights.append([])
		var stone: Dictionary = Dressing.stone(str(room["area"]))
		var shell := VillageKit.Merged.new()
		var rect: Rect2 = room["rect"]
		var height := float(room["height"])
		VillageKit.add_box(shell, Vector3(rect.size.x, 0.2, rect.size.y),
			Vector3(rect.get_center().x, -0.1, rect.get_center().y), stone["floor"])
		var ceiling := Vector3(rect.size.x, Layout.TOP - height, rect.size.y)
		var ceiling_at := Vector3(rect.get_center().x, (height + Layout.TOP) * 0.5, rect.get_center().y)
		VillageKit.add_box(shell, ceiling, ceiling_at, stone["roof"])
		_box_collider(solids, ceiling, ceiling_at)
		for block in walls[index]:
			var wall: Rect2 = block
			VillageKit.add_box(shell, Vector3(wall.size.x, Layout.TOP, wall.size.y),
				Vector3(wall.get_center().x, Layout.TOP * 0.5, wall.get_center().y), stone["wall"])
		shell.commit(node, "Shell", false)
	_room_lit.resize(Layout.ROOMS.size())
	_room_lit.fill(1)
	for block in Layout.rock_rects():
		_box_collider(solids, Vector3(block.size.x, Layout.TOP, block.size.y),
			Vector3(block.get_center().x, Layout.TOP * 0.5, block.get_center().y))


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
		_own(index, Dressing.rope(_rooms[index], landing, float(Layout.ROOMS[index]["height"])))


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


## Ease the haze and the ambient toward the air of the area the eye is in.
func _settle_air(delta: float) -> void:
	if environment == null:
		return
	var spec: Dictionary = CaveKit.AREAS.get(_air_area, CaveKit.AREAS["mouth"])
	var k := clampf(delta * AIR_EASE, 0.0, 1.0)
	environment.fog_light_color = environment.fog_light_color.lerp(spec["fog"], k)
	environment.ambient_light_color = environment.ambient_light_color.lerp(spec["ambient"], k)
	environment.fog_density = lerpf(environment.fog_density, float(spec["haze"]), k)


# --- the hostiles ------------------------------------------------------------

func _build_mobs() -> void:
	var mobs_root := Node3D.new()
	mobs_root.name = "Mobs"
	add_child(mobs_root)
	for spec in Layout.DENS:
		var members: Array = []
		var index := 0
		for row in Layout.den_members(spec):
			index += 1
			var at: Vector3 = row["at"]
			var face: Vector3 = row["face"]
			members.append(_spawn_watcher(mobs_root, "Hollow%s%d" % [str(spec["id"]).capitalize(), index],
				str(row["species"]), at, atan2(-(face.x - at.x), -(face.z - at.z))))
		MobWander.assign_all(members, PACK_RADIUS)
		_dens.append({"id": str(spec["id"]), "label": str(spec["label"]),
			"rect": Layout.room(str(spec["room"]))["rect"], "mobs": members, "awake": false})
	master = DemonScript.new()
	master.name = MASTER_NAME
	master.position = Layout.MASTER_POINT + Vector3(0.0, SPAWN_LIFT, 0.0)
	master.rotation.y = Layout.MASTER_YAW
	mobs_root.add_child(master)
	master.home = master.global_position
	master.safe_center = _safe_center()
	_wire(master)
	master.defeated.connect(_on_master_defeated)
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
	watcher.position = at + Vector3(0.0, SPAWN_LIFT, 0.0)
	watcher.rotation.y = yaw
	parent.add_child(watcher)
	watcher.home = watcher.global_position
	watcher.safe_center = _safe_center()
	_wire(watcher)
	return watcher


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
		Loot.settle(enemy, enemy == master, loot_rng)
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
	den["awake"] = true
	for mob in den["mobs"]:
		if not is_instance_valid(mob) or not bool(mob.get("alive")):
			continue
		mob.rest(false)
		_enlist(mob)
		var prey = _nearest(mob.global_position, standing)
		if prey != null:
			mob.targets = standing
			mob.hunt(prey)
	den_woke.emit(str(den["id"]), str(den["label"]))


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
