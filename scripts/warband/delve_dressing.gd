extends RefCounted
## The Weeping Hollow's dressing: the stone each area is cut from, the rock skin
## over every wall and roof (`delve_rock.gd`), the dripstone and breakdown that
## stand along the walls and hang from the roofs, the ropes down the six shafts
## and the light that falls down them, and the lights and props
## `delve_layout.gd` names. The rock, the formations and the stone they are cut
## from are the cave kit (`CaveKit`: Blender-built from CC0 scans, see
## `tools/build_cave_kit.py`); the fires, timber, bones and charms are the same
## `VillageKit` / `CampKit` / `FireFx` merges the camp and the town are dressed
## with. Every light made here is handed back to the caller, so the cave can put a
## room's lights out while the eye is far from it.
##
## Nothing is placed at a height the plan authored: every piece that stands is set
## on the ground under it (`delve_floor.gd`, `Floor.height`), so a spire on a swell
## of the floor stands higher than its neighbour in a hollow, a pool lies in the
## pan cut for it and a body's post is on level ground.
##
## Each area reads differently: dry limestone and warm torchlight at the mouth and
## the dens, dark wet rock and witch-light over the drowned gallery's black water,
## pale fungus and green-filmed stone through the garden, curtains and columns
## round the mere, bleached stone and candles in the chapel, roots and earthy
## strata in the rooted hall, broken strata and timber in the old workings, and
## red rock round Gorehorn's blood in the lair.

const Layout = preload("res://scripts/warband/delve_layout.gd")
const Floor = preload("res://scripts/warband/delve_floor.gd")
const Rock = preload("res://scripts/warband/delve_rock.gd")
const CampDressing = preload("res://scripts/warband/camp_dressing.gd")
const VillageKit = preload("res://scripts/world/village_kit.gd")
const TextureLibrary = preload("res://scripts/world/texture_library.gd")

## The fungus each area grows: the colour its gills glow and the light it gives.
const FUNGUS := {
	"gallery": {"emission": Color(0.28, 0.66, 1.0), "light": Color(0.40, 0.72, 1.0)},
	"garden": {"emission": Color(0.62, 1.0, 0.70), "light": Color(0.66, 1.0, 0.74)},
	"default": {"emission": Color(0.30, 0.95, 0.72), "light": Color(0.40, 0.95, 0.78)},
}

## How much rock each area grows. `roof` is stalactite clusters per 10 m² of roof,
## `wall` the chance of a piece every couple of metres of wall foot, `floor` the
## stands of dripstone growing up out of every 10 m² of open floor, and the four
## weights pick what a wall piece is: dripstone `spires`, a `flowstone` mound,
## fallen `breakdown` or a `talus` pile. `curtains` hang along a hall's wall heads
## per 40 m of wall.
const FORMATIONS := {
	"mouth": {"roof": 0.5, "wall": 0.4, "floor": 0.3, "spires": 3, "flowstone": 1, "breakdown": 3,
		"talus": 3, "curtains": 1},
	"den": {"roof": 0.4, "wall": 0.35, "floor": 0.25, "spires": 2, "flowstone": 1, "breakdown": 4,
		"talus": 3, "curtains": 0},
	"gallery": {"roof": 1.1, "wall": 0.55, "floor": 0.7, "spires": 4, "flowstone": 3, "breakdown": 1,
		"talus": 1, "curtains": 3},
	"ossuary": {"roof": 0.45, "wall": 0.35, "floor": 0.3, "spires": 3, "flowstone": 1, "breakdown": 2,
		"talus": 2, "curtains": 1},
	"garden": {"roof": 0.8, "wall": 0.5, "floor": 0.45, "spires": 4, "flowstone": 3, "breakdown": 1,
		"talus": 1, "curtains": 2},
	"mere": {"roof": 1.2, "wall": 0.6, "floor": 0.8, "spires": 5, "flowstone": 3, "breakdown": 1,
		"talus": 1, "curtains": 4},
	"chapel": {"roof": 0.5, "wall": 0.35, "floor": 0.35, "spires": 3, "flowstone": 2, "breakdown": 1,
		"talus": 1, "curtains": 2},
	"rooted": {"roof": 0.25, "wall": 0.4, "floor": 0.2, "spires": 1, "flowstone": 1, "breakdown": 3,
		"talus": 3, "curtains": 0},
	"workings": {"roof": 0.2, "wall": 0.5, "floor": 0.12, "spires": 1, "flowstone": 0, "breakdown": 5,
		"talus": 4, "curtains": 0},
	"ring": {"roof": 0.6, "wall": 0.45, "floor": 0.3, "spires": 3, "flowstone": 1, "breakdown": 2,
		"talus": 2, "curtains": 1},
	"lair": {"roof": 0.7, "wall": 0.5, "floor": 0.4, "spires": 4, "flowstone": 1, "breakdown": 3,
		"talus": 2, "curtains": 1},
}
## Hanging length below the root of each stalactite piece, at scale 1.
const HANG := {"StalactiteCarrot": 1.7, "StalactiteRibbed": 0.95, "Curtain": 1.4}
## The lowest a stalactite's tip may hang over the floor of a hall, and of a way.
const HEADROOM := 2.9
const HEADROOM_TUNNEL := 2.7
## Nothing grows within this many metres of a jamb, along the wall.
const JAMB_CLEAR := 1.8
## Every room grows from this and its own index, whatever order rooms are built in.
const GROWTH_SEED := 9100

## The floor is built `PLAN` times the size its lamps were authored at: a lamp
## reaches `PLAN` times as far and burns `PLAN` squared as bright - the same light
## at twice the distance - so a hall that doubled is lit exactly as it was.
const PLAN := Layout.SCALE

static var _stone_sets: Dictionary = {}
static var _mats: Dictionary = {}
static var _grown: Dictionary = {}
static var _disc: CylinderMesh = null
static var _drop: SphereMesh = null


# --- materials ---------------------------------------------------------------

## An area's wall, floor and roof stone: the cave kit's rock in the area's set and
## tints (`CaveKit.AREAS`), cached.
static func stone(area: String) -> Dictionary:
	if _stone_sets.has(area):
		return _stone_sets[area]
	var out := {}
	for part in ["wall", "floor", "roof"]:
		out[part] = CaveKit.rock_material(area, part)
	_stone_sets[area] = out
	return out


## The cave's own few materials, on top of the kits'.
static func materials() -> Dictionary:
	if not _mats.is_empty():
		return _mats
	var m := {}
	m["paving"] = TextureLibrary.paving_material(Color(0.55, 0.52, 0.48))
	m["slab"] = TextureLibrary.granite_material(Color(0.60, 0.56, 0.50))
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.015, 0.022, 0.026)
	water.roughness = 0.06
	water.metallic_specular = 0.9
	m["water"] = water
	var wax := StandardMaterial3D.new()
	wax.albedo_color = Color(0.86, 0.80, 0.64)
	wax.roughness = 0.55
	m["wax"] = wax
	var blood := StandardMaterial3D.new()
	blood.albedo_color = Color(0.20, 0.03, 0.03)
	blood.roughness = 0.35
	m["blood"] = blood
	# The night at the top of a shaft: a dim moonlit blue, not a lamp.
	var sky := StandardMaterial3D.new()
	sky.albedo_color = Color(0.13, 0.17, 0.27)
	sky.emission_enabled = true
	sky.emission = Color(0.16, 0.21, 0.34)
	sky.emission_energy_multiplier = 0.7
	sky.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m["sky"] = sky
	m["cold_flame"] = CampDressing.cold_flame()
	var cold_core := StandardMaterial3D.new()
	cold_core.albedo_color = Color(0.62, 0.84, 1.0)
	cold_core.emission_enabled = true
	cold_core.emission = Color(0.36, 0.62, 1.0)
	cold_core.emission_energy_multiplier = 1.3
	cold_core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m["cold_core"] = cold_core
	var drop := StandardMaterial3D.new()
	drop.albedo_color = Color(0.72, 0.8, 0.86, 0.6)
	drop.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m["drop"] = drop
	var mote := StandardMaterial3D.new()
	mote.albedo_color = Color(0.75, 0.82, 1.0, 0.5)
	mote.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mote.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mote.vertex_color_use_as_albedo = true
	m["mote"] = mote
	_mats = m
	return m


# --- the rock of a room -----------------------------------------------------

## The rock of one room (`Layout.ROOMS` index): its skin - walls, lintels and a
## vaulted roof over the collider boxes - and the cave that grows on it:
## stalactite clusters and curtains hanging from the roof with their tips clear of
## any head, dripstone spires, flowstone, fallen breakdown and talus along the wall
## feet and in the corners, the stands of stalagmites out in the open floor of a
## hall, and water dripping from the roofs of the wet areas.
## Nothing grows within `JAMB_CLEAR` of a way out, on a landing, at a den's post,
## or under a light or a prop. The big pieces - a spire as tall as a man, a boulder
## to the knee, a corner cluster - stop bodies and stand on the squad's map; the
## small ones hug the wall. What grows is drawn from the room's own seed, so it is
## the same on every machine and every descent, and it is grown once per process
## (`_grow`): a later descent only places it again.
static func dress_room(node: Node3D, index: int) -> void:
	var area := str(Layout.ROOMS[index]["area"])
	var skin := MeshInstance3D.new()
	skin.name = "Skin"
	skin.mesh = Rock.skin(index)
	skin.material_override = stone(area)["wall"]
	skin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(skin)
	var grown := _grow(index)
	if grown["mesh"] != null:
		var formations := MeshInstance3D.new()
		formations.name = "Formations"
		formations.mesh = grown["mesh"]
		formations.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(formations)
	var solids := StaticBody3D.new()
	solids.name = "RockSolids"
	solids.collision_layer = 1
	solids.collision_mask = 0
	node.add_child(solids)
	for stop in grown["stops"]:
		_cylinder(solids, stop[0], float(stop[1]), float(stop[2]))
	if float(CaveKit.AREAS.get(area, {}).get("wet", 0.0)) >= 0.3:
		_drips(node, grown["tips"], index)


## What grows in a room, from the room's own seed: `{mesh, stops, tips}` - the
## merged formations, the `[at, radius, tall]` of every piece that stops a body,
## and the tips water drips from. Grown on first ask and kept.
static func _grow(index: int) -> Dictionary:
	if _grown.has(index):
		return _grown[index]
	var area := str(Layout.ROOMS[index]["area"])
	var rng := RandomNumberGenerator.new()
	rng.seed = GROWTH_SEED + index * 7919
	var grown := {"kit": VillageKit.Merged.new(), "material": CaveKit.formation_material(area),
		"stops": [], "clear": _clearings(index), "tips": []}
	var style: Dictionary = FORMATIONS.get(area, FORMATIONS["mouth"])
	_roof_rock(grown, index, style, rng)
	_wall_rock(grown, index, style, rng)
	_floor_rock(grown, index, style, rng)
	var kit: VillageKit.Merged = grown["kit"]
	var out := {"mesh": null if kit.is_empty() else kit.build_mesh(), "stops": grown["stops"], "tips": grown["tips"]}
	_grown[index] = out
	return out


## A piece that stops bodies: a post collider round it on the room's rock.
static func _stop(grown: Dictionary, at: Vector3, radius: float, tall: float) -> void:
	(grown["stops"] as Array).append([at, radius, tall])


## Where nothing may grow in or round a room: `[point, radius]` pairs (cave x/z) -
## the landings and their ropes, the dens' posts, the master's blood, and every
## light and prop.
static func _clearings(index: int) -> Array:
	var near: Rect2 = (Layout.ROOMS[index]["rect"] as Rect2).grow(3.0)
	var out: Array = []
	var keep := func(at: Vector3, radius: float) -> void:
		var flat := Vector2(at.x, at.z)
		if near.has_point(flat):
			out.append([flat, radius])
	for entry in Layout.LANDINGS:
		keep.call(entry["centre"], 6.0)
		keep.call(entry["rope"], 3.0)
	for den in Layout.DENS:
		for member in Layout.den_members(den):
			keep.call(member["at"], 2.4)
	keep.call(Layout.MASTER_POINT, 5.0)
	for spec in Layout.LIGHTS:
		keep.call(_spot(spec), 1.7)
	for spec in Layout.PROPS:
		var size: Vector2 = spec.get("size", Vector2.ZERO)
		keep.call(_spot(spec), maxf(2.0, maxf(size.length() * 0.6, float(spec.get("radius", 0.0)) + 1.5)))
	return out


static func _spot(spec: Dictionary) -> Vector3:
	if spec.has("wall"):
		return Layout.wall_point(str(spec["room"]), str(spec["wall"]), float(spec["along"]))["at"]
	return spec.get("at", Vector3.ZERO)


static func _is_clear(clear: Array, at: Vector2, reach: float) -> bool:
	for entry in clear:
		if at.distance_to(entry[0]) < float(entry[1]) + reach:
			return false
	return true


static func _near_rope(at: Vector2, reach: float) -> bool:
	for entry in Layout.LANDINGS:
		var rope: Vector3 = entry["rope"]
		if at.distance_to(Vector2(rope.x, rope.z)) < reach:
			return true
	return false


## Stalactite clusters over the whole roof, every tip above `HEADROOM`, and in a
## hall curtains hung along the wall heads.
static func _roof_rock(grown: Dictionary, index: int, style: Dictionary, rng: RandomNumberGenerator) -> void:
	var room: Dictionary = Layout.ROOMS[index]
	var rect: Rect2 = room["rect"]
	var tunnel := bool(room.get("tunnel", false))
	var headroom := HEADROOM_TUNNEL if tunnel else HEADROOM
	var kit: VillageKit.Merged = grown["kit"]
	var material: Material = grown["material"]
	var clusters := int(round(rect.get_area() * float(style["roof"]) / 10.0 * (0.6 if tunnel else 1.0)))
	for cluster in clusters:
		var centre := Vector2(rng.randf_range(rect.position.x + 0.6, rect.end.x - 0.6),
			rng.randf_range(rect.position.y + 0.6, rect.end.y - 0.6))
		if _near_rope(centre, 2.4):
			continue
		var count := 1 + rng.randi_range(0, 1 if tunnel else 3)
		for k in count:
			var spot := centre if k == 0 else centre + Vector2(rng.randf_range(-0.75, 0.75), rng.randf_range(-0.75, 0.75))
			if not rect.grow(-0.35).has_point(spot):
				continue
			var piece := "StalactiteCarrot" if rng.randf() < 0.66 else "StalactiteRibbed"
			var roof := Rock.roof_height(index, spot.x, spot.y)
			var size := rng.randf_range(0.6, 1.3) if k == 0 else rng.randf_range(0.22, 0.6)
			size = minf(size, _clearance(spot, roof) / float(HANG[piece]))
			if size < 0.15:
				continue
			var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled_local(
				Vector3(size * rng.randf_range(0.85, 1.2), size, size * rng.randf_range(0.85, 1.2)))
			kit.add(CaveKit.formation(piece), Transform3D(basis, Vector3(spot.x, roof - 0.02, spot.y)), material)
			if k == 0:
				(grown["tips"] as Array).append(Vector3(spot.x, roof - 0.02 - float(HANG[piece]) * size, spot.y))
	if tunnel:
		return
	var runs: Array = Rock.wall_runs(index)
	var metres := 0.0
	for run in runs:
		var along: PackedFloat32Array = run["along"]
		metres += along[along.size() - 1]
	for curtain in int(round(float(style["curtains"]) * metres / 40.0)):
		var run: Dictionary = runs[rng.randi() % runs.size()]
		var along: PackedFloat32Array = run["along"]
		var total := along[along.size() - 1]
		if total < JAMB_CLEAR * 2.0 + 1.6:
			continue
		var sample := Rock.sample(run, rng.randf_range(JAMB_CLEAR + 0.8, total - JAMB_CLEAR - 0.8))
		var dir: Vector2 = sample["dir"]
		if absf(dir.x) > 0.5 and absf(dir.y) > 0.5:
			continue
		var point: Vector2 = sample["point"]
		var at := point + dir * (Rock.relief(index, point.x, Rock.ceiling(index) - 0.15, point.y,
			sample["open"], sample["arch"]) + 0.1)
		var roof := Rock.roof_height(index, at.x, at.y)
		var size := minf(rng.randf_range(0.7, 1.25), _clearance(at, roof) / float(HANG["Curtain"]))
		if size < 0.3 or _near_rope(at, 2.4):
			continue
		var tangent: Vector2 = sample["tangent"]
		var across := Vector3(tangent.x, 0.0, tangent.y)
		var basis := Basis(across, Vector3.UP, across.cross(Vector3.UP)).scaled_local(Vector3.ONE * size)
		kit.add(CaveKit.formation("Curtain"), Transform3D(basis, Vector3(at.x, roof - 0.03, at.y)), material)


## Along every wall foot: a piece every couple of metres by the area's odds, and a
## cluster in each of a hall's own corners.
static func _wall_rock(grown: Dictionary, index: int, style: Dictionary, rng: RandomNumberGenerator) -> void:
	var tunnel := bool(Layout.ROOMS[index].get("tunnel", false))
	var weights := {"spires": float(style["spires"]), "flowstone": float(style["flowstone"]),
		"breakdown": float(style["breakdown"]), "talus": float(style["talus"])}
	for run in Rock.wall_runs(index):
		var points: PackedVector2Array = run["points"]
		var dirs: PackedVector2Array = run["dirs"]
		var along: PackedFloat32Array = run["along"]
		var total := along[along.size() - 1]
		if not tunnel:
			for k in range(1, points.size() - 1):
				var turned := (points[k] - points[k - 1]).dot(points[k + 1] - points[k]) < 0.01
				if turned and along[k] >= JAMB_CLEAR + 0.6 and total - along[k] >= JAMB_CLEAR + 0.6:
					_corner(grown, index, Rock.sample(run, along[k]), rng)
		var s := rng.randf_range(JAMB_CLEAR, JAMB_CLEAR + 1.2)
		var step := 3.0 if tunnel else 2.2
		while s < total - JAMB_CLEAR:
			var sample := Rock.sample(run, s)
			var dir: Vector2 = sample["dir"]
			var corner := absf(dir.x) > 0.5 and absf(dir.y) > 0.5
			if not corner and rng.randf() < float(style["wall"]) * (0.7 if tunnel else 1.0):
				_wall_piece(grown, index, sample, _pick(weights, rng), rng)
			s += step * rng.randf_range(0.7, 1.35)


static func _pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for key in weights:
		total += float(weights[key])
	var roll := rng.randf() * total
	for key in weights:
		roll -= float(weights[key])
		if roll <= 0.0:
			return str(key)
	return "talus"


## One piece at a wall foot, set just proud of the skin's talus skirt.
static func _wall_piece(grown: Dictionary, index: int, sample: Dictionary, kind: String,
		rng: RandomNumberGenerator) -> void:
	var room: Dictionary = Layout.ROOMS[index]
	var tunnel := bool(room.get("tunnel", false))
	var kit: VillageKit.Merged = grown["kit"]
	var material: Material = grown["material"]
	var point: Vector2 = sample["point"]
	var dir: Vector2 = sample["dir"]
	var tangent: Vector2 = sample["tangent"]
	var ground := Floor.height(point.x, point.y)
	var foot := Rock.relief(index, point.x, ground + 0.3, point.y, sample["open"], sample["arch"])
	match kind:
		"spires":
			var size := rng.randf_range(0.35, 0.7) if tunnel else rng.randf_range(0.5, 1.15)
			var piece := "StalagmiteTall"
			if rng.randf() > 0.55:
				piece = "StalagmiteSquat" if rng.randf() < 0.6 else "StalagmiteStump"
			var at := point + dir * (foot + 0.34 * size)
			if not _is_clear(grown["clear"], at, 0.45 * size):
				return
			_stand(kit, material, piece, at, size, rng)
			for extra in rng.randi_range(0, 2):
				var small := size * rng.randf_range(0.3, 0.6)
				var beside := point + tangent * rng.randf_range(-0.9, 0.9) * (0.5 + size * 0.5) \
					+ dir * (foot + 0.3 * small + rng.randf_range(0.0, 0.2))
				_stand(kit, material, "StalagmiteSquat" if rng.randf() < 0.5 else "StalagmiteTall", beside, small, rng)
			if not tunnel and size >= 0.75 and piece == "StalagmiteTall":
				_stop(grown, _at_ground(at), 0.3 * size + 0.05, 2.4 * size)
		"flowstone":
			var size := rng.randf_range(0.45, 0.7) if tunnel else rng.randf_range(0.6, 1.05)
			var at := point + dir * (foot * 0.55 + 0.5 * size)
			if not _is_clear(grown["clear"], at, 0.9 * size):
				return
			var across := Vector3(tangent.x, 0.0, tangent.y)
			var basis := Basis(across, Vector3.UP, across.cross(Vector3.UP)).scaled_local(
				Vector3(size, size * rng.randf_range(0.8, 1.2), size))
			kit.add(CaveKit.formation("Flowstone"), Transform3D(basis, _at_ground(at) - Vector3(0.0, 0.04, 0.0)),
				material)
			if not tunnel and size >= 0.8:
				_stop(grown, _at_ground(at), 0.55 * size, 0.8 * size)
		"breakdown":
			var piece: String = ["BoulderA", "BoulderB", "BoulderC", "Slab"][rng.randi() % 4]
			var size := rng.randf_range(0.3, 0.55) if tunnel else rng.randf_range(0.45, 1.0)
			var at := point + dir * (foot + 0.55 * size)
			if not _is_clear(grown["clear"], at, 0.8 * size):
				return
			_lay(kit, material, piece, at, size, rng)
			if not tunnel and size >= 0.65:
				_stop(grown, _at_ground(at), 0.7 * size, 1.1 * size)
			if rng.randf() < 0.6:
				var chips := point + dir * (foot + 0.3) + tangent * rng.randf_range(-1.0, 1.0)
				_lay(kit, material, "Talus", chips, rng.randf_range(0.45, 0.75), rng)
		_:
			var size := rng.randf_range(0.55, 0.9) if tunnel else rng.randf_range(0.8, 1.35)
			var at := point + dir * (foot * 0.6 + 0.45 * size)
			if not _is_clear(grown["clear"], at, 0.7 * size):
				return
			_lay(kit, material, "Talus", at, size, rng)


## Dripstone growing up out of the open floor: stands of stalagmites out in the
## middle of a hall, where the wall's talus does not reach, each on the ground
## under it - so a stand on a swell of the floor stands higher and one in a hollow
## lower - with the wet flowstone the water leaves banked at its foot. A stand
## taller than a knee stops bodies and stands on the squad's map; a snub of stone
## stops nobody. Ways out keep their middle clear: a passage is not a hall.
static func _floor_rock(grown: Dictionary, index: int, style: Dictionary, rng: RandomNumberGenerator) -> void:
	var room: Dictionary = Layout.ROOMS[index]
	var rect: Rect2 = room["rect"]
	if bool(room.get("tunnel", false)):
		return
	var stands := int(round(rect.get_area() * float(style.get("floor", 0.0)) / 10.0))
	var inner := rect.grow(-2.8)
	if stands <= 0 or inner.size.x < 1.8 or inner.size.y < 1.8:
		return
	var kit: VillageKit.Merged = grown["kit"]
	var material: Material = grown["material"]
	var pieces := ["StalagmiteSquat", "StalagmiteStump", "StalagmiteTall"]
	for stand in stands:
		var at := Vector2(rng.randf_range(inner.position.x, inner.end.x),
			rng.randf_range(inner.position.y, inner.end.y))
		if _near_rope(at, 2.6) or not _is_clear(grown["clear"], at, 1.3):
			continue
		var main := rng.randf_range(0.45, 1.15)
		if rng.randf() < 0.3:
			# A snub of stone, knee high, that grew and stopped.
			main *= 0.4
		_stand(kit, material, "StalagmiteTall", at, main, rng)
		for extra in rng.randi_range(0, 2):
			var beside := at + Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2))
			_stand(kit, material, pieces[rng.randi() % pieces.size()], beside,
				main * rng.randf_range(0.28, 0.6), rng)
		if main >= 0.7:
			_stop(grown, _at_ground(at), 0.26 * main + 0.06, 2.2 * main)
		if rng.randf() < 0.55:
			var across := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled_local(
				Vector3.ONE * main * rng.randf_range(0.75, 1.15))
			kit.add(CaveKit.formation("Flowstone"), Transform3D(across,
				_at_ground(at) - Vector3(0.0, 0.03, 0.0)), material)


## A hall's own corner: a stand of dripstone round a tall spire, flowstone banked
## behind it, one collider round the lot.
static func _corner(grown: Dictionary, index: int, sample: Dictionary, rng: RandomNumberGenerator) -> void:
	var point: Vector2 = sample["point"]
	var dir: Vector2 = sample["dir"]
	var kit: VillageKit.Merged = grown["kit"]
	var material: Material = grown["material"]
	var foot := Rock.relief(index, point.x, Floor.height(point.x, point.y) + 0.3, point.y,
		sample["open"], sample["arch"])
	var at := point + dir * (foot + 0.55)
	if not _is_clear(grown["clear"], at, 1.0):
		return
	var main := rng.randf_range(0.8, 1.3)
	_stand(kit, material, "StalagmiteTall", at, main, rng)
	var pieces := ["StalagmiteSquat", "StalagmiteStump", "StalagmiteTall"]
	for extra in 2 + rng.randi_range(0, 2):
		var off := Vector2(rng.randf_range(-0.85, 0.85), rng.randf_range(-0.85, 0.85))
		_stand(kit, material, pieces[rng.randi() % pieces.size()], at + off, main * rng.randf_range(0.3, 0.65), rng)
	if rng.randf() < 0.55:
		var behind := point + dir * (foot * 0.4 + 0.2)
		var across := Vector3(-dir.y, 0.0, dir.x).normalized()
		var basis := Basis(across, Vector3.UP, across.cross(Vector3.UP)).scaled_local(Vector3.ONE * rng.randf_range(0.7, 1.0))
		kit.add(CaveKit.formation("Flowstone"), Transform3D(basis, _at_ground(behind) - Vector3(0.0, 0.04, 0.0)),
			material)
	_stop(grown, _at_ground(at), 0.75, 2.6)


## A floor piece stood upright at a cave point, turned at random: its foot on the
## ground there, whatever the ground is doing.
static func _stand(kit: VillageKit.Merged, material: Material, piece: String, at: Vector2, size: float,
		rng: RandomNumberGenerator) -> void:
	var girth := size * rng.randf_range(0.85, 1.15)
	var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled_local(
		Vector3(girth, size * rng.randf_range(0.9, 1.25), girth))
	kit.add(CaveKit.formation(piece), Transform3D(basis, _at_ground(at)), material)


## A fallen piece laid at a cave point: any yaw, a little tilt, on the ground.
static func _lay(kit: VillageKit.Merged, material: Material, piece: String, at: Vector2, size: float,
		rng: RandomNumberGenerator) -> void:
	var basis := (Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis(Vector3.RIGHT, rng.randf_range(-0.14, 0.14))) \
		.scaled_local(Vector3.ONE * size)
	kit.add(CaveKit.formation(piece), Transform3D(basis, _at_ground(at)), material)


## A cave point on the floor: the ground there and no other height.
static func _at_ground(at: Vector2) -> Vector3:
	return Vector3(at.x, Floor.height(at.x, at.y), at.y)


## How much clear air there is under a piece of roof over a cave point, in metres:
## the rock overhead less the ground under it.
static func _clearance(at: Vector2, roof: float) -> float:
	return roof - Floor.height(at.x, at.y)


## Water dripping off a few stalactite tips onto the floor of a wet room.
static func _drips(node: Node3D, tips: Array, index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GROWTH_SEED + 31 + index * 7919
	if tips.is_empty():
		return
	if _drop == null:
		_drop = SphereMesh.new()
		_drop.radius = 0.008
		_drop.height = 0.034
		_drop.radial_segments = 6
		_drop.rings = 3
		_drop.material = materials()["drop"]
	for drip in mini(5, tips.size()):
		var tip: Vector3 = tips[rng.randi() % tips.size()]
		var drips := CPUParticles3D.new()
		drips.name = "Drip%d" % drip
		drips.position = tip
		drips.mesh = _drop
		drips.amount = 1
		# The drop falls through the floor and out of sight; the rest of its life is
		# the pause before the next one.
		drips.lifetime = rng.randf_range(1.6, 3.4)
		drips.preprocess = rng.randf_range(0.0, 3.0)
		drips.direction = Vector3.DOWN
		drips.spread = 0.0
		drips.initial_velocity_min = 0.0
		drips.initial_velocity_max = 0.0
		drips.gravity = Vector3(0.0, -9.8, 0.0)
		drips.local_coords = false
		node.add_child(drips)


# --- the ropes ---------------------------------------------------------------

## One shaft's way up: a knotted rope out of a hole of night in the chamber's roof,
## the cold light that falls through it - a pale cone with dust turning in it -
## and a word on the stone so it is found. `top` is the rock over the rope, in the
## cave's frame: the rope is as long as the ground under it is low, so a shaft that
## opens over a fallen floor is a longer climb and a shaft over a mound a shorter
## one. Returns the light.
static func rope(node: Node3D, landing: Dictionary, top: float) -> Array[Light3D]:
	var mats: Dictionary = CampKit.materials()
	var rope_at: Vector3 = landing["rope"]
	var foot := Floor.height(rope_at.x, rope_at.z)
	var rise := maxf(1.0, top - foot)
	var m := VillageKit.Merged.new()
	var hang := Vector3(rope_at.x, foot + rise, rope_at.z)
	VillageKit.add_beam(m, hang, Vector3(rope_at.x, foot + 0.25, rope_at.z), 0.045, mats["drift"], 6)
	var knots := int((rise - 0.6) / 0.9)
	for index in knots:
		VillageKit.add_ball(m, 0.075, Vector3(rope_at.x, foot + 0.7 + float(index) * 0.9, rope_at.z),
			mats["drift"], Vector3(1.0, 0.8, 1.0), 6, 4)
	# The hole sits just under the roof skin, which flattens to meet it.
	VillageKit.add_cyl_disc(m, 0.9, 0.04, hang - Vector3(0.0, 0.08, 0.0), materials()["sky"], 18)
	m.commit(node, "Rope_%s" % str(landing["id"]), false)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.85
	cone.bottom_radius = 1.9
	cone.height = rise
	cone.radial_segments = 24
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var beam := MeshInstance3D.new()
	beam.name = "Beam_%s" % str(landing["id"])
	beam.mesh = cone
	beam.material_override = CaveKit.shaft_material(Color(0.55, 0.66, 0.92), rise)
	beam.position = Vector3(rope_at.x, foot + rise * 0.5, rope_at.z)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(beam)
	node.add_child(_motes(Vector3(rope_at.x, foot + rise * 0.5, rope_at.z), rise))
	var shaft := SpotLight3D.new()
	shaft.name = "NightShaft_%s" % str(landing["id"])
	shaft.position = hang - Vector3(0.0, 0.2, 0.0)
	shaft.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	shaft.light_color = Color(0.62, 0.72, 0.95)
	shaft.light_energy = 3.0
	shaft.spot_range = rise + 2.0
	shaft.spot_angle = 32.0
	shaft.shadow_enabled = false
	node.add_child(shaft)
	var word := Label3D.new()
	word.name = "WayUp_%s" % str(landing["id"])
	word.text = "THE WAY UP"
	word.font_size = 56
	word.pixel_size = 0.006
	word.outline_size = 10
	word.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	word.modulate = Color(0.86, 0.90, 1.0)
	word.outline_modulate = Color(0.02, 0.03, 0.06, 0.9)
	word.position = Vector3(rope_at.x, foot + 2.7, rope_at.z)
	node.add_child(word)
	var out: Array[Light3D] = [shaft]
	return out


## Dust turning slowly in a shaft's light: faint additive specks that fade in and
## out over a column `tall` metres high round `at`.
static func _motes(at: Vector3, tall: float) -> CPUParticles3D:
	var speck := QuadMesh.new()
	speck.size = Vector2(0.018, 0.018)
	speck.material = materials()["mote"]
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.3, Color(1.0, 1.0, 1.0, 0.9))
	fade.add_point(0.7, Color(1.0, 1.0, 1.0, 0.9))
	var motes := CPUParticles3D.new()
	motes.name = "Motes"
	motes.position = at
	motes.mesh = speck
	motes.amount = 40
	motes.lifetime = 9.0
	motes.preprocess = 9.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(1.0, tall * 0.45, 1.0)
	motes.direction = Vector3.UP
	motes.spread = 180.0
	motes.initial_velocity_min = 0.01
	motes.initial_velocity_max = 0.06
	motes.gravity = Vector3(0.0, -0.015, 0.0)
	motes.color_ramp = fade
	motes.local_coords = true
	return motes


# --- lights ------------------------------------------------------------------

## A lamp at the plan's scale. A flickering lamp breathes around the energy it was
## born with (`FireFlicker.base_energy`), so that moves with it: scaling only the
## energy it holds would be undone on the lamp's first frame.
static func _at_plan(lamp: OmniLight3D) -> void:
	lamp.omni_range *= PLAN
	lamp.light_energy *= PLAN * PLAN
	if lamp.get("base_energy") != null:
		lamp.set("base_energy", lamp.light_energy)


## One `Layout.LIGHTS` row, built into its room's node. Returns every light it made.
static func light(node: Node3D, spec: Dictionary, seed_value: int) -> Array[Light3D]:
	var kind := str(spec["kind"])
	var room_id := str(spec["room"])
	var area := str(Layout.room(room_id).get("area", ""))
	var tunnel := bool(Layout.room(room_id).get("tunnel", false))
	var at := Vector3.ZERO
	var inward := Vector3.FORWARD
	if spec.has("wall"):
		var mount: Dictionary = Layout.wall_point(room_id, str(spec["wall"]), float(spec["along"]))
		at = mount["at"]
		inward = mount["inward"]
	else:
		at = spec["at"]
	# Whatever the plan authored at the floor is a spot on the ground: a fire, a
	# brazier, a wall's sconce two metres up it - every one of them is read from the
	# ground under it, not from a level the cave no longer has.
	at = Floor.lift(at)
	match kind:
		"sconce":
			return _sconce(node, at, inward, seed_value, false, 10.0 if tunnel else 13.0)
		"witch":
			return _sconce(node, at, inward, seed_value, true, 10.0 if tunnel else 12.0)
		"lantern":
			return _lantern(node, at, inward, seed_value)
		"fungus":
			return _fungus(node, at, inward, seed_value, area)
		"fire":
			return _fire(node, at, seed_value)
		"brazier":
			return _brazier(node, at, seed_value)
		"candles":
			return _candles(node, at, seed_value)
	push_error("delve dressing: unknown light kind %s" % kind)
	return []


static func _sconce(node: Node3D, at: Vector3, inward: Vector3, seed_value: int, cold: bool,
		reach: float) -> Array[Light3D]:
	var host := Node3D.new()
	host.name = "Sconce%d" % seed_value
	host.position = at
	host.rotation.y = atan2(inward.x, inward.z)
	node.add_child(host)
	var mats: Dictionary = CampKit.materials()
	var iron: Dictionary = CampDressing.metal()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var m := CampKit.Merged.new()
	CampKit.add_beam(m, Vector3(0.0, 2.05, -0.1), Vector3(0.0, 2.05, 0.30), 0.03, iron["iron"], 5)
	CampKit.add_ring(m, Vector3(0.0, 2.05, 0.34), 0.0, 0.05, 0.08, iron["iron"], 0.0, 8, 3)
	CampKit.add_beam(m, Vector3(0.0, 1.75, 0.30), Vector3(0.0, 2.36, 0.40), 0.045, mats["drift_dark"], 6, 0.035)
	CampKit.add_ball(m, 0.07, Vector3(0.0, 2.38, 0.40), materials()["cold_core"] if cold else mats["fire_core"],
		Vector3(1.0, 0.6, 1.0), 7, 4)
	var saved: Transform3D = m.push(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.40)))
	FireFx.flame_cards(m, materials()["cold_flame"] if cold else mats["flame"], rng, 0.42, 2.36)
	m.group = saved
	m.commit(host, "Torch", false)
	var lamp := FireFlicker.new()
	lamp.name = "TorchLight"
	lamp.position = Vector3(0.0, 2.6, 0.62)
	lamp.light_color = Color(0.45, 0.72, 1.0) if cold else Color(1.0, 0.58, 0.26)
	lamp.light_energy = 2.4 if cold else 3.0
	lamp.omni_range = reach
	lamp.omni_attenuation = 1.0
	lamp.flicker = 0.16 if cold else 0.24
	lamp.shadow_enabled = false
	_at_plan(lamp)
	host.add_child(lamp)
	var out: Array[Light3D] = [lamp]
	return out


## A miner's lantern on an iron bracket: a little cage round a flame.
static func _lantern(node: Node3D, at: Vector3, inward: Vector3, seed_value: int) -> Array[Light3D]:
	var host := Node3D.new()
	host.name = "Lantern%d" % seed_value
	host.position = at
	host.rotation.y = atan2(inward.x, inward.z)
	node.add_child(host)
	var mats: Dictionary = CampKit.materials()
	var iron: Dictionary = CampDressing.metal()
	var m := CampKit.Merged.new()
	CampKit.add_beam(m, Vector3(0.0, 2.5, -0.1), Vector3(0.0, 2.5, 0.42), 0.025, iron["iron"], 5)
	CampKit.add_beam(m, Vector3(0.0, 2.5, 0.42), Vector3(0.0, 2.32, 0.42), 0.012, iron["iron"], 4)
	var centre := Vector3(0.0, 2.1, 0.42)
	CampKit.add_cyl_disc(m, 0.12, 0.03, centre + Vector3(0.0, 0.2, 0.0), iron["iron"], 8)
	CampKit.add_cyl_disc(m, 0.11, 0.03, centre - Vector3(0.0, 0.18, 0.0), iron["iron"], 8)
	for corner in 4:
		var angle := TAU * float(corner) / 4.0 + PI * 0.25
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * 0.1
		CampKit.add_beam(m, centre + offset - Vector3(0.0, 0.18, 0.0), centre + offset + Vector3(0.0, 0.2, 0.0),
			0.01, iron["iron"], 4)
	CampKit.add_ball(m, 0.06, centre, mats["fire_core"], Vector3(1.0, 1.5, 1.0), 7, 4)
	m.commit(host, "Lantern", false)
	var lamp := FireFlicker.new()
	lamp.name = "LanternLight"
	lamp.position = centre + Vector3(0.0, 0.1, 0.2)
	lamp.light_color = Color(1.0, 0.74, 0.40)
	lamp.light_energy = 2.6
	lamp.omni_range = 11.0
	lamp.omni_attenuation = 1.0
	lamp.flicker = 0.12
	lamp.shadow_enabled = false
	_at_plan(lamp)
	host.add_child(lamp)
	var out: Array[Light3D] = [lamp]
	return out


## Glowing growth on the wet stone at a wall's foot - bracket shelves up the
## dressed rock and clusters of caps at its foot, their gills alight - and the cold
## light it gives.
static func _fungus(node: Node3D, wall: Vector3, inward: Vector3, seed_value: int, area: String) -> Array[Light3D]:
	var kind := area if FUNGUS.has(area) else "default"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var m := VillageKit.Merged.new()
	var flora := CaveKit.flora_material(FUNGUS[kind]["emission"], 1.8)
	var along := Vector3(inward.z, 0.0, -inward.x)
	var facing := Basis(Vector3.UP.cross(inward), Vector3.UP, inward)
	for shelf in 2:
		var spot := wall + inward * 0.08 + along * rng.randf_range(-0.8, 0.8) \
			+ Vector3(0.0, rng.randf_range(0.55, 1.6), 0.0)
		m.add(CaveKit.flora("Shelf"), Transform3D(facing.scaled_local(Vector3.ONE * rng.randf_range(0.8, 1.3)), spot), flora)
	for cluster in 3:
		var spot := wall + inward * rng.randf_range(0.4, 0.9) + along * rng.randf_range(-1.0, 1.0)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled_local(Vector3.ONE * rng.randf_range(0.8, 1.5))
		m.add(CaveKit.flora("CapCluster"), Transform3D(basis, spot), flora)
	m.commit(node, "Fungus%d" % seed_value, false)
	var lamp := OmniLight3D.new()
	lamp.name = "FungusLight%d" % seed_value
	lamp.position = wall + inward * 1.0 + Vector3(0.0, 0.8, 0.0)
	lamp.light_color = FUNGUS[kind]["light"]
	lamp.light_energy = 1.1
	lamp.omni_range = 7.5
	lamp.omni_attenuation = 1.3
	lamp.shadow_enabled = false
	_at_plan(lamp)
	node.add_child(lamp)
	var out: Array[Light3D] = [lamp]
	return out


static func _fire(node: Node3D, at: Vector3, seed_value: int) -> Array[Light3D]:
	var host := Node3D.new()
	host.name = "Fire%d" % seed_value
	host.position = at
	node.add_child(host)
	CampKit.fire_ring(host, CampKit.materials(), seed_value)
	var out: Array[Light3D] = []
	var lamp := host.get_node_or_null("CampFireLight") as OmniLight3D
	if lamp != null:
		lamp.light_energy = 2.0
		lamp.omni_range = 10.0
		_at_plan(lamp)
		out.append(lamp)
	return out


static func _brazier(node: Node3D, at: Vector3, seed_value: int) -> Array[Light3D]:
	var host := Node3D.new()
	host.name = "Brazier%d" % seed_value
	host.position = at
	node.add_child(host)
	var mats: Dictionary = CampKit.materials()
	var iron: Dictionary = CampDressing.metal()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var m := CampKit.Merged.new()
	for index in 3:
		var angle := TAU * float(index) / 3.0
		CampKit.add_beam(m, Vector3(cos(angle) * 0.34, 0.0, sin(angle) * 0.34),
			Vector3(cos(angle) * 0.18, 0.95, sin(angle) * 0.18), 0.035, iron["iron"], 5)
	CampKit.add_ring(m, Vector3(0.0, 1.0, 0.0), 0.0, 0.28, 0.36, iron["iron"], 0.0, 12, 4)
	CampKit.add_ball(m, 0.26, Vector3(0.0, 1.04, 0.0), mats["ember"], Vector3(1.1, 0.35, 1.1), 8, 4)
	CampKit.add_ball(m, 0.12, Vector3(0.0, 1.12, 0.0), mats["fire_core"], Vector3(1.0, 0.5, 1.0), 7, 4)
	FireFx.flame_cards(m, mats["flame"], rng, 0.85, 1.1)
	m.commit(host, "Brazier", false)
	FireFx.embers(host, 1.14, 0.22, 14)
	var lamp := FireFlicker.new()
	lamp.name = "BrazierLight"
	lamp.position = Vector3(0.0, 1.9, 0.0)
	lamp.light_color = Color(1.0, 0.42, 0.18)
	lamp.light_energy = 2.6
	lamp.omni_range = 13.0
	lamp.omni_attenuation = 1.0
	lamp.flicker = 0.28
	lamp.shadow_enabled = false
	_at_plan(lamp)
	host.add_child(lamp)
	var out: Array[Light3D] = [lamp]
	return out


## Tallow candles stood where `at` says (a plinth's top, a ledge): wax, wicks and
## small flames, and the close warm light they make.
static func _candles(node: Node3D, at: Vector3, seed_value: int) -> Array[Light3D]:
	var host := Node3D.new()
	host.name = "Candles%d" % seed_value
	host.position = at
	node.add_child(host)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mats: Dictionary = CampKit.materials()
	var m := CampKit.Merged.new()
	for index in 7:
		var angle := TAU * float(index) / 7.0 + rng.randf_range(-0.3, 0.3)
		var spot := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.12, 0.42)
		var tall := rng.randf_range(0.10, 0.30)
		var girth := rng.randf_range(0.025, 0.04)
		CampKit.add_beam(m, spot, spot + Vector3(0.0, tall, 0.0), girth, materials()["wax"], 7, girth * 0.92)
		CampKit.add_ball(m, 0.016, spot + Vector3(0.0, tall + 0.02, 0.0), mats["fire_core"],
			Vector3(1.0, 1.8, 1.0), 5, 3)
		var saved: Transform3D = m.push(Transform3D(Basis.IDENTITY, spot))
		FireFx.flame_cards(m, mats["flame"], rng, 0.07, tall)
		m.group = saved
	m.commit(host, "Candles", false)
	var lamp := FireFlicker.new()
	lamp.name = "CandleLight"
	lamp.position = Vector3(0.0, 0.5, 0.0)
	lamp.light_color = Color(1.0, 0.62, 0.30)
	lamp.light_energy = 1.4
	lamp.omni_range = 6.5
	lamp.omni_attenuation = 1.2
	lamp.flicker = 0.2
	lamp.shadow_enabled = false
	_at_plan(lamp)
	host.add_child(lamp)
	var out: Array[Light3D] = [lamp]
	return out


# --- props -------------------------------------------------------------------

## One `Layout.PROPS` row. Merged pieces go into `clutter` (the room's one prop
## mesh); kit pieces that commit themselves stand on their own node; colliders go
## on the room's `solids`. Returns any light a kit piece made for itself.
static func prop(node: Node3D, clutter, solids: StaticBody3D, spec: Dictionary,
		seed_value: int) -> Array[Light3D]:
	var room_index := Layout.room_index(str(spec["room"]))
	var rock := CaveKit.formation_material(str(Layout.room(str(spec["room"])).get("area", "mouth")))
	var out: Array[Light3D] = []
	var vmats: Dictionary = VillageKit.materials()
	var kind := str(spec["kind"])
	var at: Vector3 = Floor.lift(spec.get("at", Vector3.ZERO))
	var yaw := float(spec.get("yaw", 0.0))
	var height := float(Layout.room(str(spec["room"])).get("height", 6.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	match kind:
		"bones":
			VillageKit.bone_heap(clutter, vmats, at, yaw, seed_value)
		"stakes":
			VillageKit.skull_stakes(clutter, vmats, at, yaw, int(spec.get("count", 4)), 0.95, seed_value)
		"totem":
			var pole := _host(node, "Totem%d" % seed_value, at)
			VillageKit.totem(pole, vmats, solids, float(spec.get("height", 3.8)), seed_value)
		"altar":
			var altar := _host(node, "Altar%d" % seed_value, at)
			VillageKit.sacrifice_ground(altar, vmats, solids, seed_value)
			var glow := altar.get_node_or_null("OfferingGlow") as Light3D
			if glow != null:
				out.append(glow)
		"blood":
			_blood(clutter, at, float(spec.get("radius", 3.2)), vmats["bone"], rng)
		"pool":
			_pool(clutter, at, spec.get("size", Vector2(3.0, 2.0)), bool(spec.get("square", false)), rock, rng)
		"column":
			_column(clutter, solids, at, float(spec.get("radius", 1.0)), room_index, rock, rng)
		"caps":
			_caps(clutter, solids, at, int(spec.get("count", 4)), rng)
		"roots":
			_roots(clutter, at, spec.get("size", Vector2(6.0, 6.0)), height, rng)
		"rootpost":
			_root_post(clutter, solids, at, height, rng)
		"frame":
			_frame(clutter, at, yaw, height)
		"post":
			var mount: Dictionary = Layout.wall_point(str(spec["room"]), str(spec["wall"]), float(spec["along"]))
			_post(clutter, Floor.lift(mount["at"]), mount["inward"], height)
		"cart":
			_cart(clutter, solids, at, yaw, rock, rng)
		"rubble":
			_rubble_heap(clutter, solids, at, float(spec.get("radius", 1.4)), rock, rng)
		"coffin":
			_coffin(clutter, solids, at, yaw, rng)
		"plinth":
			_plinth(clutter, solids, at, yaw)
		_:
			push_error("delve dressing: unknown prop kind %s" % kind)
	for lamp in out:
		_at_plan(lamp)
	return out


static func _host(node: Node3D, label: String, at: Vector3) -> Node3D:
	var host := Node3D.new()
	host.name = label
	host.position = at
	node.add_child(host)
	return host


static func _cylinder(solids: StaticBody3D, at: Vector3, radius: float, tall: float) -> void:
	VillageKit.add_post_collider(solids, Transform3D.IDENTITY, radius, tall, at)


static func _box(solids: StaticBody3D, at: Vector3, size: Vector3, yaw: float) -> void:
	VillageKit.add_collider(solids, Transform3D.IDENTITY, size, at + Vector3(0.0, size.y * 0.5, 0.0), yaw)


## A stain of old blood, and a rim of bone set in the stone round it. The floor of
## a hall is not level and a stain is not a table: the disc is laid ring by ring on
## the ground it covers (`Floor.height`), so it follows the hall's own pitch, and
## the rim is drawn as short lengths of bone from point to point of the ground
## rather than as one flat hoop. Shallow, and it stops nothing.
static func _blood(m, at: Vector3, radius: float, bone: Material, rng: RandomNumberGenerator) -> void:
	var segments := 32
	var rings := 3
	var verts := PackedVector3Array([Vector3(at.x, Floor.height(at.x, at.z) + 0.02, at.z)])
	var normals := PackedVector3Array([Vector3.UP])
	for ring in range(1, rings + 1):
		var reach := radius * float(ring) / float(rings)
		for k in segments:
			var angle := TAU * float(k) / float(segments)
			var x := at.x + cos(angle) * reach
			var z := at.z + sin(angle) * reach
			verts.append(Vector3(x, Floor.height(x, z) + 0.02, z))
			normals.append(Vector3.UP)
	var indices := PackedInt32Array()
	for k in segments:
		var next := (k + 1) % segments
		indices.append_array(PackedInt32Array([0, 1 + k, 1 + next]))
	for ring in range(1, rings):
		var here := 1 + (ring - 1) * segments
		var out := here + segments
		for k in segments:
			var next := (k + 1) % segments
			indices.append_array(PackedInt32Array([here + k, out + k, out + next,
				here + k, out + next, here + next]))
	# The side Godot draws a triangle from is the one its winding turns away from:
	# the floor's own triangles (`delve_floor.mesh`) have (b - a) x (c - a) turning
	# down, so a stain that is to be seen from above is wound the same way.
	var first := PackedVector3Array([verts[indices[0]], verts[indices[1]], verts[indices[2]]])
	if (first[1] - first[0]).cross(first[2] - first[0]).y > 0.0:
		for k in range(0, indices.size(), 3):
			var swap := indices[k + 1]
			indices[k + 1] = indices[k + 2]
			indices[k + 2] = swap
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var stain := ArrayMesh.new()
	stain.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.add(stain, Transform3D.IDENTITY, materials()["blood"])
	# The rim of bone, laid on the ground point to point.
	var count := maxi(16, int(round(TAU * radius / 1.3)))
	var rim := PackedVector3Array()
	for k in count + 1:
		var angle := TAU * float(k % count) / float(count)
		var x := at.x + cos(angle) * radius * rng.randf_range(0.99, 1.03)
		var z := at.z + sin(angle) * radius * rng.randf_range(0.99, 1.03)
		rim.append(Vector3(x, Floor.height(x, z) + 0.04, z))
	for k in count:
		VillageKit.add_beam(m, rim[k], rim[k + 1], 0.075, bone, 4)


## Still black water lying in a hollow of the floor, its rim broken stone. Shallow:
## a body wades through it, so it stops nothing.
static func _pool(m, at: Vector3, size: Vector2, square: bool, rock: Material, rng: RandomNumberGenerator) -> void:
	var mats := materials()
	if square:
		VillageKit.add_box(m, Vector3(size.x * 2.0, 0.02, size.y * 2.0), at + Vector3(0.0, 0.012, 0.0), mats["water"])
		# A kerb of laid stone, flush with the floor so nobody trips on it.
		for side in [-1.0, 1.0]:
			VillageKit.add_box(m, Vector3(size.x * 2.0 + 0.7, 0.06, 0.35),
				at + Vector3(0.0, 0.03, side * (size.y + 0.17)), mats["paving"])
			VillageKit.add_box(m, Vector3(0.35, 0.06, size.y * 2.0),
				at + Vector3(side * (size.x + 0.17), 0.03, 0.0), mats["paving"])
		return
	var disc := Transform3D(Basis.IDENTITY.scaled(Vector3(size.x, 1.0, size.y)), at + Vector3(0.0, 0.012, 0.0))
	m.add(_unit_disc(), disc, mats["water"])
	var around := TAU * sqrt((size.x * size.x + size.y * size.y) * 0.5)
	var count := maxi(8, int(around / 0.8))
	var pieces := ["BoulderA", "BoulderB", "BoulderC", "Slab"]
	for index in count:
		var angle := TAU * float(index) / float(count) + rng.randf_range(-0.08, 0.08)
		var rim := Vector2(cos(angle) * size.x, sin(angle) * size.y) * rng.randf_range(0.98, 1.08)
		_lay(m, rock, pieces[index % pieces.size()], Vector2(at.x, at.z) + rim, rng.randf_range(0.12, 0.26), rng)


static func _unit_disc() -> CylinderMesh:
	if _disc == null:
		_disc = CylinderMesh.new()
		_disc.top_radius = 1.0
		_disc.bottom_radius = 1.0
		_disc.height = 0.02
		_disc.radial_segments = 32
		_disc.rings = 1
	return _disc


## A column where a stalagmite met the stalactite over it: the kit's column, its
## girth at a man's height the collider's, stretched from under the floor into the
## roof skin over it, with breakdown at its foot. It stops bodies, arrows and sight.
static func _column(m, solids: StaticBody3D, at: Vector3, radius: float, index: int, rock: Material,
		rng: RandomNumberGenerator) -> void:
	var roof := Rock.roof_height(index, at.x, at.z)
	var girth := radius * 1.4
	var rise := (roof - at.y + 0.2) / 6.1
	var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled_local(Vector3(girth, rise, girth))
	m.add(CaveKit.formation("Column"), Transform3D(basis, at), rock)
	var pieces := ["Talus", "BoulderA", "BoulderB"]
	for piece in 5:
		var angle := TAU * float(piece) / 5.0 + rng.randf_range(-0.3, 0.3)
		var spot := Vector2(at.x, at.z) + Vector2(cos(angle), sin(angle)) * radius * 1.25
		var size := 0.9 if piece % 3 == 0 else rng.randf_range(0.3, 0.5)
		_lay(m, rock, pieces[piece % 3], spot, size, rng)
	_cylinder(solids, at, radius * 0.9, maxf(1.0, roof - at.y))


## A stand of pale fungus taller than a man: the kit's giant caps leaning out of
## one root, the tallest first, clusters of small caps round their feet, every gill
## alight. One collider round the root, where the stems are.
static func _caps(m, solids: StaticBody3D, at: Vector3, count: int, rng: RandomNumberGenerator) -> void:
	var flora := CaveKit.flora_material(FUNGUS["garden"]["emission"], 1.6)
	for index in count:
		var angle := TAU * float(index) / float(count) + rng.randf_range(-0.4, 0.4)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var foot := at + out * (rng.randf_range(0.0, 0.15) if index == 0 else rng.randf_range(0.3, 0.7))
		var size := rng.randf_range(1.0, 1.15) if index == 0 else rng.randf_range(0.35, 0.85)
		# Leaning out from the root: turned about the axis across the lean.
		var lean := Basis(Vector3(-out.z, 0.0, out.x), -rng.randf_range(0.03, 0.08) if index == 0
			else -rng.randf_range(0.12, 0.3))
		var basis := (lean * Basis(Vector3.UP, rng.randf_range(0.0, TAU))).scaled_local(Vector3.ONE * size)
		m.add(CaveKit.flora("CapGiant"), Transform3D(basis, foot), flora)
	for cluster in 3:
		var angle := rng.randf_range(0.0, TAU)
		var spot := at + Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.7, 1.2)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled_local(Vector3.ONE * rng.randf_range(1.0, 1.8))
		m.add(CaveKit.flora("CapCluster"), Transform3D(basis, spot), flora)
	_cylinder(solids, at, 0.75, 2.4)


## Roots of whatever grows above the hollow, hanging out of the roof over an area.
## They end well over a man's head, so they stop nothing.
static func _roots(m, at: Vector3, size: Vector2, ceiling: float, rng: RandomNumberGenerator) -> void:
	var bark: Material = VillageKit.materials()["bark"]
	var count := int(size.x * size.y / 3.5)
	for index in count:
		var top := Vector3(at.x + rng.randf_range(-size.x, size.x) * 0.5, at.y + ceiling + 0.1,
			at.z + rng.randf_range(-size.y, size.y) * 0.5)
		var end := at.y + rng.randf_range(3.4, maxf(3.5, ceiling - 1.2))
		var point := top
		var radius := rng.randf_range(0.05, 0.12)
		var steps := 3
		for step in steps:
			var fall := (top.y - end) / float(steps)
			var next := point + Vector3(rng.randf_range(-0.35, 0.35), -fall, rng.randf_range(-0.35, 0.35))
			VillageKit.add_beam(m, point, next, radius, bark, 5, radius * 0.7)
			point = next
			radius *= 0.7


## A root as thick as a man that reached the floor and took hold of it.
static func _root_post(m, solids: StaticBody3D, at: Vector3, ceiling: float, rng: RandomNumberGenerator) -> void:
	var bark: Material = VillageKit.materials()["bark"]
	var point := at + Vector3(0.0, ceiling + 0.1, 0.0)
	var radius := 0.22
	var steps := 5
	for step in steps:
		var next := Vector3(at.x + rng.randf_range(-0.25, 0.25),
			at.y + ceiling * (1.0 - float(step + 1) / float(steps)),
			at.z + rng.randf_range(-0.25, 0.25))
		if step == steps - 1:
			next = at
		VillageKit.add_beam(m, point, next, radius, bark, 7, radius * 1.12)
		point = next
		radius *= 1.12
	# The flare where it grips the stone.
	for index in 5:
		var angle := TAU * float(index) / 5.0 + rng.randf_range(-0.3, 0.3)
		VillageKit.add_beam(m, at + Vector3(0.0, 0.9, 0.0),
			at + Vector3(cos(angle) * 0.9, 0.02, sin(angle) * 0.9), 0.14, bark, 5, 0.04)
	_cylinder(solids, at, 0.45, ceiling)


## A timber set across a way: two posts against its walls and a cap piece over
## them. `yaw` turns the set's span (local x) across the way.
static func _frame(m, at: Vector3, yaw: float, ceiling: float) -> void:
	var timber: Material = VillageKit.materials()["timber"]
	var across := Vector3(cos(yaw), 0.0, -sin(yaw))
	var half := 1.82
	var top := ceiling - 0.25
	for side in [-1.0, 1.0]:
		var foot: Vector3 = at + across * side * half
		VillageKit.add_beam(m, foot, foot + Vector3(0.0, top, 0.0), 0.13, timber, 6, 0.12)
	VillageKit.add_beam(m, at - across * (half + 0.15) + Vector3(0.0, top, 0.0),
		at + across * (half + 0.15) + Vector3(0.0, top, 0.0), 0.14, timber, 6)


## A timber post set against a hall's wall, its cap pressed into the roof.
static func _post(m, at: Vector3, inward: Vector3, ceiling: float) -> void:
	var timber: Material = VillageKit.materials()["timber"]
	var foot := at + inward * 0.12
	VillageKit.add_beam(m, foot, foot + Vector3(0.0, ceiling, 0.0), 0.14, timber, 6, 0.13)
	var along := Vector3(inward.z, 0.0, -inward.x)
	VillageKit.add_beam(m, foot - along * 0.9 + Vector3(0.0, ceiling - 0.2, 0.0),
		foot + along * 0.9 + Vector3(0.0, ceiling - 0.2, 0.0), 0.13, timber, 6)
	VillageKit.add_beam(m, foot + Vector3(0.0, 1.6, 0.0) + inward * 0.05,
		foot + along * 0.85 + Vector3(0.0, ceiling - 0.3, 0.0), 0.08, timber, 5)


## An ore cart left where its axle broke, tipped on one wheel, its load spilled.
static func _cart(m, solids: StaticBody3D, at: Vector3, yaw: float, rock: Material, rng: RandomNumberGenerator) -> void:
	var vmats := VillageKit.materials()
	var iron: Dictionary = CampDressing.metal()
	var saved: Transform3D = m.push(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, 0.12), at))
	VillageKit.add_box(m, Vector3(1.4, 0.08, 0.9), Vector3(0.0, 0.42, 0.0), vmats["timber"])
	for side in [-1.0, 1.0]:
		VillageKit.add_box(m, Vector3(1.4, 0.55, 0.07), Vector3(0.0, 0.72, side * 0.43), vmats["timber"])
		VillageKit.add_box(m, Vector3(0.07, 0.55, 0.9), Vector3(side * 0.68, 0.72, 0.0), vmats["timber"])
		VillageKit.add_box(m, Vector3(1.46, 0.06, 0.05), Vector3(0.0, 0.98, side * 0.46), iron["iron"])
		for end in [-1.0, 1.0]:
			VillageKit.add_ring(m, Vector3(end * 0.45, 0.25, side * 0.5), 0.0, 0.17, 0.25, iron["iron"],
				PI * 0.5, 12, 4)
	m.group = saved
	var pieces := ["BoulderA", "BoulderB", "BoulderC"]
	for index in 6:
		var spill := Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(0.6, 1.3)).rotated(Vector3.UP, yaw)
		_lay(m, rock, pieces[index % pieces.size()], Vector2(at.x + spill.x, at.z + spill.z),
			rng.randf_range(0.12, 0.22), rng)
	_lay(m, rock, "Talus", Vector2(at.x, at.z) + Vector2(0.0, 0.9).rotated(-yaw), 0.7, rng)
	_box(solids, at, Vector3(1.5, 1.0, 1.0), yaw)


## A heap of fallen roof: broken slabs and boulders on a skirt of talus, too high to
## step over.
static func _rubble_heap(m, solids: StaticBody3D, at: Vector3, radius: float, rock: Material,
		rng: RandomNumberGenerator) -> void:
	var pieces := ["BoulderA", "BoulderB", "BoulderC", "Slab"]
	for index in 7:
		var angle := rng.randf_range(0.0, TAU)
		var reach := rng.randf_range(0.0, radius * 0.7)
		var size := rng.randf_range(0.4, 0.75) * (1.25 if reach < radius * 0.3 else 1.0)
		_lay(m, rock, pieces[index % pieces.size()], Vector2(at.x + cos(angle) * reach, at.z + sin(angle) * reach),
			size, rng)
	_lay(m, rock, "Talus", Vector2(at.x, at.z), radius * 0.9, rng)
	_cylinder(solids, at, radius * 0.75, 1.3)


## A stone coffin with its lid shoved half off.
static func _coffin(m, solids: StaticBody3D, at: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var mats := materials()
	var vmats := VillageKit.materials()
	var saved: Transform3D = m.push(Transform3D(Basis(Vector3.UP, yaw), at))
	VillageKit.add_box(m, Vector3(2.1, 0.62, 0.86), Vector3(0.0, 0.31, 0.0), mats["slab"])
	VillageKit.add_box(m, Vector3(2.0, 0.02, 0.7), Vector3(0.0, 0.62, 0.0), vmats["char"])
	VillageKit.add_box(m, Vector3(2.16, 0.12, 0.92), Vector3(rng.randf_range(0.3, 0.6), 0.69, 0.18),
		mats["slab"], rng.randf_range(-0.2, 0.2))
	m.group = saved
	_box(solids, at, Vector3(2.2, 0.8, 0.95), yaw)


## A block of dressed stone the keepers set their offerings on: skulls, ochre and
## (from `LIGHTS`) the candles on top. Its top is a metre up.
static func _plinth(m, solids: StaticBody3D, at: Vector3, yaw: float) -> void:
	var mats := materials()
	var vmats := VillageKit.materials()
	var saved: Transform3D = m.push(Transform3D(Basis(Vector3.UP, yaw), at))
	VillageKit.add_box(m, Vector3(1.5, 0.9, 0.8), Vector3(0.0, 0.45, 0.0), mats["slab"])
	VillageKit.add_box(m, Vector3(1.7, 0.1, 0.95), Vector3(0.0, 0.95, 0.0), mats["slab"])
	VillageKit.add_box(m, Vector3(1.2, 0.08, 0.02), Vector3(0.0, 0.62, 0.41), vmats["ochre"])
	VillageKit.add_skull(m, vmats, Vector3(-0.6, 1.08, 0.12), 0.4, 0.8, true)
	VillageKit.add_skull(m, vmats, Vector3(0.62, 1.07, -0.1), -0.6, 0.7, false)
	m.group = saved
	_box(solids, at, Vector3(1.7, 1.0, 0.95), yaw)
