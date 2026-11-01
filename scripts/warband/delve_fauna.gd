extends Node3D
## The Hollow's small life: bats hanging in the high roofs and flying their loops
## under them, rats working along the wall feet, spiders in old webs across the
## corners, glowworms hanging their lights from the damp roofs, and moths round
## every warm flame.
##
## Presentation only, and each machine's own: nothing here is on the hostile list,
## the squad's map or a collider, and nothing is replicated. A room's creatures of
## one kind are one MultiMesh (`assets/world/cave/cave_fauna.glb`, animated in
## `cave_fauna.gdshader`), so a room's life costs a few draws, and the movers are
## stepped only while their room's lights burn (`cave.room_lit`), so a far room
## costs nothing. A roost stirs when a body walks under it and its bats settle
## again once it has gone; a rat bolts along its wall from a body that comes close
## and goes to ground.

const Layout = preload("res://scripts/warband/delve_layout.gd")
const Rock = preload("res://scripts/warband/delve_rock.gd")

## What lives in each area, spread over its rooms: rats and webs by wall length,
## bats, roosts and glowworms over its halls by floor.
const LIFE := {
	"mouth": {"rats": 4, "webs": 4, "bats": 0, "roosts": 0, "glowworms": 0},
	"den": {"rats": 4, "webs": 5, "bats": 4, "roosts": 1, "glowworms": 0},
	"gallery": {"rats": 0, "webs": 0, "bats": 8, "roosts": 2, "glowworms": 420},
	"ossuary": {"rats": 6, "webs": 9, "bats": 0, "roosts": 0, "glowworms": 0},
	"garden": {"rats": 0, "webs": 2, "bats": 0, "roosts": 0, "glowworms": 520},
	"mere": {"rats": 0, "webs": 0, "bats": 14, "roosts": 3, "glowworms": 360},
	"chapel": {"rats": 4, "webs": 9, "bats": 6, "roosts": 2, "glowworms": 0},
	"rooted": {"rats": 4, "webs": 4, "bats": 0, "roosts": 0, "glowworms": 0},
	"workings": {"rats": 6, "webs": 6, "bats": 0, "roosts": 0, "glowworms": 0},
	"lair": {"rats": 3, "webs": 2, "bats": 10, "roosts": 2, "glowworms": 0},
}
## The cold light of each area's glowworms.
const GLOW := {"gallery": Color(0.42, 0.85, 1.0), "garden": Color(0.55, 1.0, 0.72), "mere": Color(0.45, 0.78, 1.0)}
const MOTHS_PER_FLAME := 3
## A body this close (on the floor plan) under a roost puts its bats up.
const STIR := 4.5
## A body this close sends a rat running.
const BOLT := 2.8
const SENSE_POLL := 0.25
const RAT_PACE := 1.7
const RAT_FLIGHT := 4.4
const BAT_PACE := 3.4

enum { ROOST, FLY, STIRRED, SETTLE }
enum { IDLE, RUN, BOLTING, HIDDEN }

## The cave this life is in (`delve_cave.gd`).
var cave = null
## Per room index: `{bats, rats, moths}` movers, or {} when the room has none.
var _life: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _sense := 0.0
## Cave-local floor points of every body standing below, refreshed each poll.
var _bodies: Array[Vector2] = []

static var _strip: ArrayMesh = null


# --- reading -------------------------------------------------------------------

## How many creatures of a kind the floor holds: "bats", "rats", "moths",
## "spiders", "webs" or "glowworms".
func count(kind: String) -> int:
	var total := 0
	for room in get_children():
		for child in room.get_children():
			if child is MultiMeshInstance3D and str(child.get_meta("kind", "")) == kind:
				total += (child as MultiMeshInstance3D).multimesh.instance_count
			elif child is MeshInstance3D and kind == "webs":
				total += int(child.get_meta("webs", 0))
	return total


# --- the build -------------------------------------------------------------------

## Populate every room. `room_lights[index]` is the lights its room owns (moths
## find the warm ones).
func build(owner_cave, room_lights: Array) -> void:
	cave = owner_cave
	_rng.seed = 7307
	var shares := _shares()
	for index in Layout.ROOMS.size():
		var room: Dictionary = Layout.ROOMS[index]
		var holder := Node3D.new()
		holder.name = "Life_%s" % str(room["id"])
		add_child(holder)
		var life := {}
		var share: Dictionary = shares[index]
		if int(share["bats"]) + int(share["roosts"]) > 0:
			life["bats"] = _bats(holder, index, int(share["roosts"]), int(share["bats"]))
		if int(share["rats"]) > 0:
			life["rats"] = _rats(holder, index, int(share["rats"]))
		var flames: Array[Vector3] = []
		for lamp in room_lights[index]:
			if is_instance_valid(lamp) and (lamp as Light3D).light_color.r > (lamp as Light3D).light_color.b:
				flames.append(to_local((lamp as Node3D).global_position))
		if not flames.is_empty():
			life["moths"] = _moths(holder, flames)
		if int(share["webs"]) > 0:
			_webs(holder, index, int(share["webs"]))
		if int(share["glowworms"]) > 0:
			_glowworms(holder, index, int(share["glowworms"]))
		_life.append(life)


## Each area's numbers spread over its rooms, largest remainder first.
func _shares() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for index in Layout.ROOMS.size():
		out.append({"bats": 0, "roosts": 0, "rats": 0, "webs": 0, "glowworms": 0})
	for area in LIFE:
		var halls: Array[int] = []
		var rooms: Array[int] = []
		var floor_weight: Array[float] = []
		var wall_weight: Array[float] = []
		for index in Layout.ROOMS.size():
			var room: Dictionary = Layout.ROOMS[index]
			if str(room["area"]) != area:
				continue
			rooms.append(index)
			var metres := 0.0
			for run in Rock.wall_runs(index):
				var along: PackedFloat32Array = run["along"]
				metres += along[along.size() - 1]
			wall_weight.append(metres)
			if not bool(room.get("tunnel", false)):
				halls.append(index)
				floor_weight.append((room["rect"] as Rect2).get_area())
		for kind in ["rats", "webs"]:
			_spread(out, rooms, wall_weight, kind, int(LIFE[area][kind]))
		for kind in ["bats", "roosts", "glowworms"]:
			_spread(out, halls, floor_weight, kind, int(LIFE[area][kind]))
	return out


func _spread(out: Array[Dictionary], rooms: Array[int], weights: Array[float], kind: String, total: int) -> void:
	if rooms.is_empty() or total <= 0:
		return
	var sum := 0.0
	for weight in weights:
		sum += weight
	var given := 0
	var remainders: Array = []
	for k in rooms.size():
		var exact := float(total) * weights[k] / maxf(sum, 0.001)
		var whole := int(floor(exact))
		out[rooms[k]][kind] = whole
		given += whole
		remainders.append([exact - float(whole), k])
	remainders.sort_custom(func(a, b): return a[0] > b[0])
	for k in total - given:
		var room: int = rooms[remainders[k % remainders.size()][1]]
		out[room][kind] = int(out[room][kind]) + 1


func _multimesh(holder: Node3D, kind: String, mesh: Mesh, material: Material, count: int,
		custom: bool) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = custom
	multimesh.mesh = mesh
	multimesh.instance_count = count
	var node := MultiMeshInstance3D.new()
	node.name = kind.capitalize()
	node.multimesh = multimesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta("kind", kind)
	holder.add_child(node)
	return node


# --- bats -----------------------------------------------------------------------

func _bats(holder: Node3D, index: int, roosts: int, flyers: int) -> Dictionary:
	var room: Dictionary = Layout.ROOMS[index]
	var rect: Rect2 = room["rect"]
	var height := float(room["height"])
	var list: Array[Dictionary] = []
	var sites: Array[Vector2] = []
	for site in roosts:
		var at := Vector2(_rng.randf_range(rect.position.x + 2.0, rect.end.x - 2.0),
			_rng.randf_range(rect.position.y + 2.0, rect.end.y - 2.0))
		sites.append(at)
		for bat in _rng.randi_range(4, 8):
			var spot := at + Vector2(_rng.randf_range(-0.45, 0.45), _rng.randf_range(-0.45, 0.45))
			var home := Vector3(spot.x, Rock.roof_height(index, spot.x, spot.y) - 0.055, spot.y)
			list.append({"mode": ROOST, "home": home, "site": site, "pos": home, "yaw": _rng.randf_range(0.0, TAU),
				"timer": 0.0, "phase": _rng.randf(), "shade": _rng.randf(), "loop": _loop(rect, height, home)})
	for bat in flyers:
		var loop := _loop(rect, height, Vector3(rect.get_center().x, 0.0, rect.get_center().y))
		list.append({"mode": FLY, "home": Vector3.ZERO, "site": -1, "pos": loop["c"], "yaw": 0.0,
			"timer": 0.0, "phase": _rng.randf(), "shade": _rng.randf(), "loop": loop})
	var node := _multimesh(holder, "bats", CaveKit.fauna("Bat"), CaveKit.fauna_material(0), list.size(), true)
	var state := {"node": node, "list": list, "sites": sites, "index": index}
	_step_bats(state, 0.0)
	return state


## A flight loop under a hall's roof: a slow figure the bat follows round `c`.
func _loop(rect: Rect2, height: float, centre: Vector3) -> Dictionary:
	var rx := maxf(1.5, rect.size.x * _rng.randf_range(0.18, 0.34))
	var rz := maxf(1.5, rect.size.y * _rng.randf_range(0.18, 0.34))
	var c := Vector3(clampf(centre.x, rect.position.x + rx + 0.5, rect.end.x - rx - 0.5), 0.0,
		clampf(centre.z, rect.position.y + rz + 0.5, rect.end.y - rz - 0.5))
	if rect.size.x < 2.0 * rx + 1.0:
		c.x = rect.get_center().x
	if rect.size.y < 2.0 * rz + 1.0:
		c.z = rect.get_center().y
	c.y = clampf(height * _rng.randf_range(0.5, 0.72), 3.0, height - 1.0)
	return {"c": c, "rx": rx, "rz": rz, "w": BAT_PACE / maxf(rx, rz), "p": _rng.randf() * TAU,
		"q": _rng.randf() * TAU, "k": _rng.randf_range(1.25, 1.6)}


func _on_loop(loop: Dictionary, t: float) -> Vector3:
	var a: float = float(loop["w"]) * t + float(loop["p"])
	var c: Vector3 = loop["c"]
	return c + Vector3(float(loop["rx"]) * sin(a), 0.6 * sin(a * 2.3 + float(loop["q"])),
		float(loop["rz"]) * sin(a * float(loop["k"]) + float(loop["q"])))


func _step_bats(state: Dictionary, delta: float) -> void:
	var multimesh: MultiMesh = (state["node"] as MultiMeshInstance3D).multimesh
	var list: Array = state["list"]
	var sites: Array = state["sites"]
	var stirred := {}
	for site in sites.size():
		for body in _bodies:
			if body.distance_to(sites[site]) < STIR:
				stirred[site] = true
	for i in list.size():
		var bat: Dictionary = list[i]
		var mode := int(bat["mode"])
		if mode == ROOST and stirred.has(int(bat["site"])):
			mode = STIRRED
			bat["timer"] = _rng.randf_range(7.0, 11.0)
			# Out from the roost into a tight loop round it.
			var home: Vector3 = bat["home"]
			bat["loop"] = {"c": Vector3(home.x, home.y - _rng.randf_range(1.0, 2.2), home.z),
				"rx": _rng.randf_range(1.6, 3.2), "rz": _rng.randf_range(1.6, 3.2), "w": BAT_PACE / 2.4,
				"p": _rng.randf() * TAU, "q": _rng.randf() * TAU, "k": _rng.randf_range(1.25, 1.6)}
		elif mode == STIRRED:
			bat["timer"] = float(bat["timer"]) - delta
			if float(bat["timer"]) <= 0.0 and not stirred.has(int(bat["site"])):
				mode = SETTLE
		var at: Vector3 = bat["pos"]
		var basis := Basis()
		var motion := 1.0
		match mode:
			ROOST:
				motion = 0.0
				at = bat["home"]
				basis = Basis(Vector3.UP, float(bat["yaw"])) * Basis(Vector3.RIGHT, -PI * 0.5)
			SETTLE:
				var home: Vector3 = bat["home"]
				var step := home - at
				if step.length() < 0.15:
					mode = ROOST
					at = home
					motion = 0.0
					basis = Basis(Vector3.UP, float(bat["yaw"])) * Basis(Vector3.RIGHT, -PI * 0.5)
				else:
					var move := step.normalized() * minf(step.length(), BAT_PACE * delta)
					at += move
					basis = _facing(move)
			_:
				var next := _on_loop(bat["loop"], _clock + float(bat["phase"]) * 40.0)
				basis = _facing(next - at)
				at = next
		bat["mode"] = mode
		bat["pos"] = at
		multimesh.set_instance_transform(i, Transform3D(basis, at))
		multimesh.set_instance_custom_data(i, Color(motion, float(bat["phase"]), float(bat["shade"]), 0.0))


func _facing(direction: Vector3) -> Basis:
	if direction.length_squared() < 1e-8:
		return Basis()
	var forward := direction.normalized()
	if absf(forward.dot(Vector3.UP)) > 0.98:
		forward = (forward + Vector3(0.05, 0.0, 0.0)).normalized()
	return Basis.looking_at(forward, Vector3.UP)


# --- rats ------------------------------------------------------------------------

func _rats(holder: Node3D, index: int, count: int) -> Dictionary:
	var runs: Array = Rock.wall_runs(index)
	var list: Array[Dictionary] = []
	for rat in count:
		var run := _rng.randi() % runs.size()
		var along: PackedFloat32Array = runs[run]["along"]
		var s := _rng.randf_range(0.3, maxf(0.4, along[along.size() - 1] - 0.3))
		list.append({"run": run, "s": s, "target": s, "mode": IDLE, "timer": _rng.randf_range(0.5, 3.0),
			"phase": _rng.randf(), "shade": _rng.randf(), "heading": 1.0})
	var node := _multimesh(holder, "rats", CaveKit.fauna("Rat"), CaveKit.fauna_material(1), list.size(), true)
	var state := {"node": node, "list": list, "index": index, "runs": runs}
	_step_rats(state, 0.0)
	return state


func _step_rats(state: Dictionary, delta: float) -> void:
	var multimesh: MultiMesh = (state["node"] as MultiMeshInstance3D).multimesh
	var runs: Array = state["runs"]
	var index := int(state["index"])
	var list: Array = state["list"]
	for i in list.size():
		var rat: Dictionary = list[i]
		var run: Dictionary = runs[int(rat["run"])]
		var along: PackedFloat32Array = run["along"]
		var total := along[along.size() - 1]
		var mode := int(rat["mode"])
		var s := float(rat["s"])
		var here: Dictionary = Rock.sample(run, s)
		var point: Vector2 = here["point"]
		if mode != HIDDEN and mode != BOLTING:
			for body in _bodies:
				if body.distance_to(point) < BOLT:
					# Away from the body along the wall, and then to ground.
					var tangent: Vector2 = here["tangent"]
					var away := 1.0 if (point - body).dot(tangent) >= 0.0 else -1.0
					rat["target"] = clampf(s + away * _rng.randf_range(4.0, 7.0), 0.0, total)
					mode = BOLTING
					break
		var speed := 0.0
		match mode:
			IDLE:
				rat["timer"] = float(rat["timer"]) - delta
				if float(rat["timer"]) <= 0.0:
					rat["target"] = clampf(s + _rng.randf_range(-4.0, 4.0), 0.2, total - 0.2)
					mode = RUN
			RUN, BOLTING:
				var pace := RAT_FLIGHT if mode == BOLTING else RAT_PACE
				var gap := float(rat["target"]) - s
				var stride := signf(gap) * minf(absf(gap), pace * delta)
				s += stride
				speed = 1.0 if mode == BOLTING else 0.7
				if absf(stride) > 0.0:
					rat["heading"] = signf(stride)
				if absf(float(rat["target"]) - s) < 0.02:
					if mode == BOLTING:
						mode = HIDDEN
						rat["timer"] = _rng.randf_range(4.0, 8.0)
					else:
						mode = IDLE
						rat["timer"] = _rng.randf_range(0.8, 3.5)
			HIDDEN:
				rat["timer"] = float(rat["timer"]) - delta
				if float(rat["timer"]) <= 0.0:
					rat["run"] = _rng.randi() % runs.size()
					var other: PackedFloat32Array = runs[int(rat["run"])]["along"]
					s = _rng.randf_range(0.3, maxf(0.4, other[other.size() - 1] - 0.3))
					rat["target"] = s
					mode = IDLE
					rat["timer"] = _rng.randf_range(1.0, 3.0)
		rat["mode"] = mode
		rat["s"] = s
		if mode == HIDDEN:
			multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
			continue
		var at: Dictionary = Rock.sample(runs[int(rat["run"])], s)
		var spot: Vector2 = at["point"]
		var dir: Vector2 = at["dir"]
		var tangent: Vector2 = at["tangent"]
		var out := Rock.relief(index, spot.x, 0.05, spot.y, at["open"], at["arch"]) + 0.1
		var facing := tangent * float(rat["heading"])
		var basis := Basis(Vector3.UP, atan2(-facing.x, -facing.y))
		multimesh.set_instance_transform(i, Transform3D(basis, Vector3(spot.x + dir.x * out, 0.0, spot.y + dir.y * out)))
		multimesh.set_instance_custom_data(i, Color(speed, float(rat["phase"]), float(rat["shade"]), 0.0))


# --- moths -----------------------------------------------------------------------

func _moths(holder: Node3D, flames: Array[Vector3]) -> Dictionary:
	var list: Array[Dictionary] = []
	for flame in flames:
		for moth in MOTHS_PER_FLAME:
			list.append({"c": flame + Vector3(0.0, _rng.randf_range(-0.15, 0.25), 0.0),
				"r": _rng.randf_range(0.22, 0.6), "w": _rng.randf_range(1.6, 3.2) * (1.0 if _rng.randf() < 0.5 else -1.0),
				"p": _rng.randf() * TAU, "phase": _rng.randf(), "shade": _rng.randf()})
	var node := _multimesh(holder, "moths", CaveKit.fauna("Moth"), CaveKit.fauna_material(3), list.size(), true)
	var state := {"node": node, "list": list}
	_step_moths(state, 0.0)
	return state


func _step_moths(state: Dictionary, _delta: float) -> void:
	var multimesh: MultiMesh = (state["node"] as MultiMeshInstance3D).multimesh
	var list: Array = state["list"]
	for i in list.size():
		var moth: Dictionary = list[i]
		var p := float(moth["p"])
		var w := float(moth["w"])
		var theta := w * _clock + p + 0.6 * sin(1.7 * _clock + p)
		var r := float(moth["r"]) * (0.8 + 0.2 * sin(2.9 * _clock + p))
		var c: Vector3 = moth["c"]
		var at := c + Vector3(cos(theta) * r, 0.12 * sin(3.1 * theta + p) + 0.04 * sin(11.0 * _clock + p), sin(theta) * r)
		var heading := Vector3(-sin(theta), 0.0, cos(theta)) * signf(w)
		multimesh.set_instance_transform(i, Transform3D(_facing(heading), at))
		multimesh.set_instance_custom_data(i, Color(1.0, float(moth["phase"]), float(moth["shade"]), 0.0))


# --- webs and their spiders ------------------------------------------------------------

## Old silk across a room's own corners - and where the room has too few corners,
## across a wall's head - with a spider sitting in about half of them.
func _webs(holder: Node3D, index: int, count: int) -> void:
	var room: Dictionary = Layout.ROOMS[index]
	var height := float(room["height"])
	var tunnel := bool(room.get("tunnel", false))
	var spots: Array[Dictionary] = []
	for run in Rock.wall_runs(index):
		var points: PackedVector2Array = run["points"]
		var along: PackedFloat32Array = run["along"]
		for k in range(1, points.size() - 1):
			if (points[k] - points[k - 1]).dot(points[k + 1] - points[k]) < 0.01:
				spots.append(Rock.sample(run, along[k]))
	if spots.is_empty():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var silk := VillageKit.Merged.new()
	var spiders: Array[Transform3D] = []
	var made := 0
	for web in count:
		var spot: Dictionary = spots[web % spots.size()]
		var point: Vector2 = spot["point"]
		var bisector: Vector2 = (spot["dir"] as Vector2).normalized()
		var y := _rng.randf_range(1.3, minf(height - 1.0, 3.6)) if web < spots.size() else _rng.randf_range(0.5, 1.2)
		var size := _rng.randf_range(0.7, 1.2) if not tunnel else _rng.randf_range(0.5, 0.9)
		var reach := Rock.relief(index, point.x, y, point.y, spot["open"], spot["arch"]) * 1.42 + size * 0.38
		var at := Vector3(point.x + bisector.x * reach, y, point.y + bisector.y * reach)
		var normal := Vector3(bisector.x, 0.0, bisector.y)
		var across := Vector3.UP.cross(normal).normalized()
		var tilt := Basis(normal, _rng.randf_range(-0.5, 0.5))
		var basis := tilt * Basis(across, Vector3.UP, normal)
		silk.add(quad, Transform3D(basis.scaled_local(Vector3(size, size, 1.0)), at), CaveKit.web_material())
		made += 1
		if _rng.randf() < 0.55:
			# A spider sits head up in the web, its back to the room.
			var head_up := Basis(normal.cross(Vector3.DOWN), normal, Vector3.DOWN)
			spiders.append(Transform3D((tilt * head_up).scaled_local(Vector3.ONE * 1.6), at + normal * 0.012))
	var node := silk.commit(holder, "Webs", false)
	if node != null:
		node.set_meta("webs", made)
	if spiders.is_empty():
		return
	var spider_node := _multimesh(holder, "spiders", CaveKit.fauna("Spider"), CaveKit.fauna_material(2),
		spiders.size(), true)
	for i in spiders.size():
		spider_node.multimesh.set_instance_transform(i, spiders[i])
		spider_node.multimesh.set_instance_custom_data(i, Color(0.0, _rng.randf(), _rng.randf(), 0.0))


# --- glowworms -----------------------------------------------------------------------

## Glowworms in patches over a damp roof, a cold point of light and a beaded thread
## each. Still apart from their threads' sway, which the shader keeps.
func _glowworms(holder: Node3D, index: int, count: int) -> void:
	var room: Dictionary = Layout.ROOMS[index]
	var rect: Rect2 = room["rect"]
	var area := str(room["area"])
	var patches := maxi(1, count / 28)
	var centres: Array[Vector2] = []
	for patch in patches:
		centres.append(Vector2(_rng.randf_range(rect.position.x + 1.0, rect.end.x - 1.0),
			_rng.randf_range(rect.position.y + 1.0, rect.end.y - 1.0)))
	var placed: Array[Transform3D] = []
	var custom: Array[Color] = []
	for worm in count:
		var centre: Vector2 = centres[worm % centres.size()]
		var spot := centre + Vector2(_rng.randfn(0.0, 1.1), _rng.randfn(0.0, 1.1))
		if not rect.grow(-0.3).has_point(spot):
			continue
		var roof := Rock.roof_height(index, spot.x, spot.y) - 0.01
		placed.append(Transform3D(Basis(), Vector3(spot.x, roof, spot.y)))
		var length := 0.05 + pow(_rng.randf(), 2.0) * 0.45
		custom.append(Color(length, _rng.randf(), _rng.randf(), 0.0))
	if placed.is_empty():
		return
	var node := _multimesh(holder, "glowworms", _thread(), CaveKit.glow_material(GLOW.get(area, Color(0.45, 0.9, 1.0))),
		placed.size(), true)
	for i in placed.size():
		node.multimesh.set_instance_transform(i, placed[i])
		node.multimesh.set_instance_custom_data(i, custom[i])


## One glowworm's strip: UV.y runs down it, UV.x across; the shader places it.
static func _thread() -> ArrayMesh:
	if _strip != null:
		return _strip
	var steps := PackedFloat32Array([0.0, 0.04, 0.08, 0.12, 0.2, 0.3, 0.42, 0.56, 0.7, 0.85, 1.0])
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for k in steps.size():
		for side in [-0.5, 0.5]:
			verts.append(Vector3(side * 0.05, -steps[k] * 0.55, 0.0))
			uvs.append(Vector2(side, steps[k]))
	for k in steps.size() - 1:
		var a := k * 2
		indices.append_array(PackedInt32Array([a, a + 1, a + 3, a, a + 3, a + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_strip = ArrayMesh.new()
	_strip.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _strip


# --- the clock ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if cave == null or not is_instance_valid(cave):
		return
	_clock += delta
	_sense += delta
	if _sense >= SENSE_POLL:
		_sense = 0.0
		_sense_bodies()
	for index in _life.size():
		var life: Dictionary = _life[index]
		if life.is_empty() or not cave.room_lit(index):
			continue
		if life.has("bats"):
			_step_bats(life["bats"], delta)
		if life.has("rats"):
			_step_rats(life["rats"], delta)
		if life.has("moths"):
			_step_moths(life["moths"], delta)


func _sense_bodies() -> void:
	_bodies.clear()
	var host = cave.host
	if host == null or not is_instance_valid(host):
		return
	var bodies = host.get("bodies")
	if not (bodies is Array):
		return
	for body in bodies:
		if body == null or not is_instance_valid(body) or not (body is Node3D):
			continue
		var at: Vector3 = (body as Node3D).global_position
		if not cave.contains(at):
			continue
		var local: Vector3 = cave.to_local(at)
		_bodies.append(Vector2(local.x, local.z))
