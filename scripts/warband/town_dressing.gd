extends RefCounted
## The town square's dressing: the market that was built around the services.
##
## `town_hub.gd` builds the square's bones - the ground and its flagstones, four
## walls, the fire, the stash chest, the recruiter's and the keeper's desks, the
## altar, the signpost and the gate - and every one of them stands in the open.
## This module is the settlement around them: a booth over each counter with the
## goods hanging off its front bar, a hide awning over the collective stash, a
## fingerpost that actually names where each road goes, the ring of stones and
## benches around the fire, and the four lanterns that pool light at the square's
## corners.
##
## Same three rules as the camp (`camp_dressing.gd`):
##
## 1. **Presentation only.** No `PhysicsBody3D`, no `CollisionShape3D`. Nothing
##    stands on a spawn ring, a service point or the gate. The root carries
##    `props` (name, position, radius, `blocks`, zone); `blocks` is true only for
##    something a body would stand in, so the regression can hold every spawn and
##    every `G` point clear.
## 2. **The village's palette.** Merged `MeshInstance3D`s, one surface per
##    material, materials from `VillageKit.materials()` - plus `Geo.material()`
##    for the iron, rope and lit-glass the kits do not carry.
## 3. **The scene owns the layout.** Counter and stash positions are read off the
##    nodes `town_hub.gd` already placed, so a service that moves takes its
##    dressing with it. Only the fingerpost and the lantern corners are declared
##    here, and `WALL_RADIUS` mirrors the scene's own constant.

const Geo = preload("res://scripts/geo.gd")

## Mirrors `town_hub.gd::WALL_RADIUS`: the walkable square is this half-side, and
## the regression compares the two so a wall move fails loudly.
const WALL_RADIUS := 18.0

## Where the fingerpost stands: the plaza's north-west edge, clear of the stash
## ring, the altar ring and the muster ring.
const SIGN_POST := Vector3(-12.5, 0.0, 8.0)

## The three boards, each pointing at the thing it names: a destination and the
## point in this square that it really is. `SIGN_TARGETS` is what the yaw is
## solved from, so the sign cannot point at nothing.
const SIGN_BOARDS := [
	{"text": "THE ALTAR", "target": Vector3(8.0, 0.0, 4.0)},
	{"text": "THE KEEPERS", "target": Vector3(-4.0, 0.0, -9.0)},
	{"text": "DEAD FIELD", "target": Vector3(8.0, 0.0, -6.0)},
]

## Lantern corners: the four diagonals of the square, each arm reaching in
## toward the fire.
const LANTERN_POSTS := [
	Vector3(11.5, 0.0, 11.5), Vector3(-11.5, 0.0, 11.5),
	Vector3(-11.5, 0.0, -11.5), Vector3(11.5, 0.0, -11.5),
]

## Bench angles around the fire, in degrees. They sit in the one free arc of the
## muster ring - the side that faces the expedition gate - so no body spawns
## inside a bench.
const BENCH_ANGLES := [240.0, 285.0, 330.0]

## The woodpile's spot: outside the bench arc, on the gate side of the fire.
const FIREWOOD := Vector3(3.45, 0.0, -2.95)

static var _fittings: Dictionary = {}


## The dressing root: a plain `Node3D` carrying the prop records the regression
## reads back.
class Root extends Node3D:
	var props: Array = []


## Builds the whole town dressing under `scene` and returns its root.
static func build(scene: Node3D) -> Node3D:
	if scene == null:
		return null
	var root := Root.new()
	root.name = "TownDressing"
	scene.add_child(root)
	var mats: Dictionary = VillageKit.materials()
	var own := fittings()
	_build_counters(root, scene, mats, own)
	_build_stash_awning(root, scene, mats, own)
	_build_fingerpost(root, mats)
	_build_fire_ring(root, scene, mats)
	_build_lanterns(root, mats, own)
	print("TOWN_DRESSING_READY props=%d" % root.props.size())
	return root


# --- palette ---------------------------------------------------------------

## The few materials the village kit does not carry. `Geo.material` is the shared
## flat-colour helper; the lit glass gets the same emission treatment the town's
## own fire uses.
static func fittings() -> Dictionary:
	if not _fittings.is_empty():
		return _fittings
	var m: Dictionary = {}
	m["iron"] = Geo.material(Color(0.20, 0.20, 0.21), 0.62, 0.50)
	m["steel"] = Geo.material(Color(0.36, 0.37, 0.39), 0.74, 0.38)
	m["rope"] = Geo.material(Color(0.33, 0.28, 0.19), 0.0, 0.90)
	m["lamp"] = _lit(Color(1.0, 0.86, 0.58), Color(1.0, 0.72, 0.35), 2.6)
	_fittings = m
	return m


static func _lit(colour: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var material := Geo.material(colour, 0.0, 0.45)
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = energy
	return material


# --- plumbing --------------------------------------------------------------

static func _group(root: Node3D, label: String) -> Node3D:
	var node := Node3D.new()
	node.name = label
	root.add_child(node)
	return node


static func _record(root: Root, label: String, at: Vector3, radius: float,
		blocks: bool = true) -> void:
	root.props.append({
		"name": label, "position": at, "radius": radius,
		"blocks": blocks, "zone": "town",
	})


## Yaw that turns a prop's local +Z toward the fire, which is how a lantern arm
## reaches into the square.
static func _inward(at: Vector3) -> float:
	return atan2(-at.x, -at.z)


## Yaw that turns a prop's local +X toward `target` (a finger board points along
## its own length).
static func _toward(at: Vector3, target: Vector3) -> float:
	var delta := target - at
	return atan2(-delta.z, delta.x)


# --- the two counters ------------------------------------------------------

## The recruiter's and the keeper's booths. Each is four posts around the desk
## `town_hub.gd` built, a crossbar frame, a hide awning pitched over it, the
## keeper's tally board, and the goods hanging off the front bar: charms and
## hides for the recruiter, strings of plain steel for the quartermaster.
static func _build_counters(root: Root, scene: Node3D, mats: Dictionary,
		own: Dictionary) -> void:
	var holder := _group(root, "Counters")
	var recruiter := scene.get_node_or_null("RecruiterDesk") as Node3D
	if recruiter != null:
		_counter(root, holder, recruiter, "RecruiterCounter", mats, own, 401, false)
	var keeper := scene.get_node_or_null("QuartermasterDesk") as Node3D
	if keeper != null:
		_counter(root, holder, keeper, "QuartermasterCounter", mats, own, 809, true)


static func _counter(root: Root, holder: Node3D, desk: Node3D, label: String,
		mats: Dictionary, own: Dictionary, seed_base: int, steel: bool) -> void:
	var at: Vector3 = desk.position
	var m := VillageKit.Merged.new()
	m.base = Transform3D(Basis.IDENTITY, at)
	# Four posts, each lashed at the head to the crossbar frame.
	for x in [-1.30, 1.30]:
		for z in [-0.80, 0.80]:
			VillageKit.add_beam(m, Vector3(x, -0.05, z), Vector3(x * 0.97, 2.46, z * 0.97),
				0.065, mats["timber"], 5, 0.052)
			VillageKit.add_ring(m, Vector3(x * 0.97, 2.38, z * 0.97), 0.0, 0.060, 0.090,
				own["rope"], 0.0, 8, 3)
	for z in [-0.80, 0.80]:
		VillageKit.add_beam(m, Vector3(-1.30, 2.42, z), Vector3(1.30, 2.44, z), 0.048,
			mats["log_dark"], 5)
	for x in [-1.30, 1.30]:
		VillageKit.add_beam(m, Vector3(x, 2.42, -0.80), Vector3(x, 2.44, 0.80), 0.044,
			mats["log_dark"], 5)
	# The awning: a hide panel pitched off the back bar, and its dripping edge.
	VillageKit.add_box(m, Vector3(3.00, 0.04, 2.10), Vector3(0.0, 2.38, 0.05),
		mats["hide_dark"], 0.0, -0.16, 0.0)
	VillageKit.add_box(m, Vector3(3.10, 0.05, 0.30), Vector3(0.0, 2.26, 1.02),
		mats["hide"], 0.0, -0.16, 0.0)
	# What the booth sells, hanging off the front bar.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_base
	for index in 4:
		var x := -0.98 + float(index) * 0.65
		if steel:
			# Strings of plain blades: this is what the keeper actually trades in.
			VillageKit.add_beam(m, Vector3(x, 2.19, 1.02),
				Vector3(x + rng.randf_range(-0.04, 0.04), 1.45, 1.02), 0.012,
				own["rope"], 3)
			VillageKit.add_box(m, Vector3(0.07, 0.34, 0.025),
				Vector3(x, 1.30, 1.02), own["steel"], 0.0, 0.0,
				rng.randf_range(-0.18, 0.18))
			VillageKit.add_box(m, Vector3(0.10, 0.06, 0.05),
				Vector3(x, 1.10, 1.02), mats["iron"], 0.0, 0.0, 0.0)
		else:
			VillageKit.add_hanging(m, mats, Vector3(x, 2.19, 1.02),
				rng.randf_range(-0.35, 0.35), seed_base + index * 13, 0.52)
	# The tally board both keepers keep their names and prices on.
	VillageKit.add_box(m, Vector3(0.90, 0.54, 0.03), Vector3(0.0, 1.88, -0.82),
		mats["hide_dark"])
	for mark in 4:
		VillageKit.add_box(m, Vector3(0.055, 0.30, 0.02),
			Vector3(-0.26 + float(mark) * 0.17, 1.88, -0.795), mats["ochre"], 0.0, 0.0,
				rng.randf_range(-0.10, 0.10))
	m.commit(holder, label)
	# Only the four posts hold ground; the awning and the goods hang over the
	# desk, so they never occupy the spot a body stands in to use it.
	for x in [-1.30, 1.30]:
		for z in [-0.80, 0.80]:
			_record(root, "%sPost" % label, at + Vector3(x, 0.0, z), 0.20)
	_record(root, "%sAwning" % label, at, 1.60, false)


# --- the stash -------------------------------------------------------------

## The collective stash under a hide roof: four posts, a ridge, a market scale
## hanging over the chest, and two crates of incoming stock.
static func _build_stash_awning(root: Root, scene: Node3D, mats: Dictionary,
		own: Dictionary) -> void:
	var holder := _group(root, "StashAwning")
	var chest := scene.get_node_or_null("StashChest") as Node3D
	var at: Vector3 = chest.position if chest != null else Vector3(-8.0, 0.0, 4.0)
	var m := VillageKit.Merged.new()
	m.base = Transform3D(Basis.IDENTITY, at)
	for x in [-1.55, 1.55]:
		for z in [-1.15, 1.15]:
			VillageKit.add_beam(m, Vector3(x, -0.05, z), Vector3(x, 2.30, z * 0.94), 0.075,
				mats["timber"], 5, 0.060)
			VillageKit.add_ring(m, Vector3(x, 2.22, z * 0.94), 0.0, 0.065, 0.095,
				own["rope"], 0.0, 8, 3)
	# The ridge and the two pitched panels that hang off it.
	for x in [-1.55, 1.55]:
		VillageKit.add_beam(m, Vector3(x, 2.28, -1.08), Vector3(x, 2.36, 1.08), 0.050,
			mats["log_dark"], 5)
	VillageKit.add_beam(m, Vector3(-1.62, 2.44, 0.0), Vector3(1.62, 2.44, 0.0), 0.055,
		mats["log_dark"], 5)
	VillageKit.add_box(m, Vector3(3.35, 0.05, 1.30), Vector3(0.0, 2.32, -0.60),
		mats["hide_dark"], 0.0, 0.20, 0.0)
	VillageKit.add_box(m, Vector3(3.35, 0.05, 1.30), Vector3(0.0, 2.32, 0.60),
		mats["hide_dark"], 0.0, -0.20, 0.0)
	# A market scale over the chest: the one thing in this square everybody trusts.
	var hook := Vector3(0.0, 2.40, 0.0)
	VillageKit.add_beam(m, hook, hook + Vector3(0.0, -0.34, 0.0), 0.012, own["rope"], 3)
	VillageKit.add_beam(m, hook + Vector3(-0.28, -0.36, 0.0), hook + Vector3(0.28, -0.36, 0.0),
		0.014, own["iron"], 4)
	for side in [-1.0, 1.0]:
		var pan := hook + Vector3(side * 0.28, -0.52, 0.0)
		VillageKit.add_beam(m, hook + Vector3(side * 0.28, -0.36, 0.0), pan, 0.008,
			own["rope"], 3)
		VillageKit.add_ball(m, 0.11, pan, own["steel"], Vector3(1.0, 0.30, 1.0), 8, 4)
	# Incoming stock: two crates and a sack beside the chest.
	VillageKit.add_box(m, Vector3(0.86, 0.66, 0.72), Vector3(1.72, 0.33, -0.72),
		mats["log"], 0.22)
	VillageKit.add_box(m, Vector3(0.68, 0.54, 0.62), Vector3(1.74, 0.93, -0.68),
		mats["log_dark"], -0.14)
	VillageKit.add_ball(m, 0.34, Vector3(-1.80, 0.30, 0.62), mats["hide"],
		Vector3(1.0, 1.15, 0.9), 9, 6)
	m.commit(holder, "StashRoof")
	for x in [-1.55, 1.55]:
		for z in [-1.15, 1.15]:
			_record(root, "StashPost", at + Vector3(x, 0.0, z), 0.16)
	_record(root, "StashRoof", at, 1.90, false)
	_record(root, "StashStock", at + Vector3(1.73, 0.0, -0.70), 0.55)


# --- the fingerpost --------------------------------------------------------

## A real fingerpost: a post and three boards, each solved to point at the thing
## its text names, with the text cut into the board.
static func _build_fingerpost(root: Root, mats: Dictionary) -> void:
	var holder := _group(root, "Signpost")
	var at := SIGN_POST
	var m := VillageKit.Merged.new()
	m.base = Transform3D(Basis.IDENTITY, at)
	VillageKit.add_ball(m, 0.20, Vector3(0.0, 0.04, 0.0), mats["stone"],
		Vector3(1.3, 0.4, 1.3), 7, 4)
	VillageKit.add_beam(m, Vector3(0.0, -0.12, 0.0), Vector3(0.02, 3.18, 0.0), 0.10,
		mats["log_dark"], 6, 0.078)
	VillageKit.add_ball(m, 0.12, Vector3(0.02, 3.22, 0.0), mats["timber"],
		Vector3(1.1, 0.8, 1.1), 7, 4)
	m.commit(holder, "Post")
	for index in SIGN_BOARDS.size():
		var height := 2.52 - float(index) * 0.46
		var board := Node3D.new()
		board.name = "Board%d" % (index + 1)
		board.position = at + Vector3(0.0, height, 0.0)
		board.rotation.y = _toward(at, SIGN_BOARDS[index]["target"])
		holder.add_child(board)
		var bm := VillageKit.Merged.new()
		# A board that starts at the post and runs out along its own +X.
		VillageKit.add_box(bm, Vector3(1.62, 0.32, 0.045), Vector3(0.83, 0.0, 0.0),
			mats["log"])
		VillageKit.add_box(bm, Vector3(1.62, 0.035, 0.055), Vector3(0.83, 0.16, 0.0),
			mats["ochre"])
		VillageKit.add_box(bm, Vector3(1.62, 0.035, 0.055), Vector3(0.83, -0.16, 0.0),
			mats["ochre"])
		VillageKit.add_box(bm, Vector3(0.22, 0.32, 0.045), Vector3(1.68, 0.0, 0.0),
			mats["log_dark"], 0.0, 0.0, PI * 0.25)
		bm.commit(board, "Board")
		var label := Label3D.new()
		label.name = "BoardText"
		label.text = String(SIGN_BOARDS[index]["text"])
		label.font_size = 64
		label.pixel_size = 0.0034
		label.modulate = Color(0.94, 0.89, 0.78)
		label.outline_size = 8
		label.outline_modulate = Color(0.09, 0.06, 0.04, 0.85)
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.position = Vector3(0.86, 0.0, 0.032)
		board.add_child(label)
		_record(root, "SignBoard%d" % (index + 1), at, 1.70, false)
	_record(root, "SignPost", at, 0.30)


# --- the fire --------------------------------------------------------------

## The ring around the fire: a kerb of field stones outside the pit's own, an
## ash spill, three split-log benches and the wood waiting to go on.
static func _build_fire_ring(root: Root, scene: Node3D, mats: Dictionary) -> void:
	var holder := _group(root, "FireRing")
	var fire := scene.get_node_or_null("Campfire") as Node3D
	var at: Vector3 = fire.position if fire != null else Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = 515
	var m := VillageKit.Merged.new()
	m.base = Transform3D(Basis.IDENTITY, at)
	# Ash carried out past the pit by years of feet and wind. It clears the
	# square's flagstones by a centimetre, so nothing z-fights under it.
	VillageKit.add_cyl_disc(m, 2.05, 0.03, Vector3(0.0, 0.088, 0.0), mats["ash"], 18)
	# The kerb: a second, wider ring of stones outside the fire's own eight.
	for index in 14:
		var angle := TAU * float(index) / 14.0 + rng.randf_range(-0.07, 0.07)
		var radius := 1.62 + rng.randf_range(-0.08, 0.08)
		VillageKit.add_ball(m, rng.randf_range(0.16, 0.24),
			Vector3(cos(angle) * radius, 0.09, sin(angle) * radius), mats["boulder_stone"],
			Vector3(1.25, 0.55, 1.0), 7, 4)
	# Three benches between the muster posts, laid tangent to the fire.
	for index in BENCH_ANGLES.size():
		var angle := deg_to_rad(float(BENCH_ANGLES[index]))
		_bench(m, mats, Vector3(cos(angle) * 2.62, 0.0, sin(angle) * 2.62), angle, index)
	m.commit(holder, "FireRing")
	# Firewood, split and stacked where the square keeps it, clear of the seats.
	# It is its own merge so the ring itself stays centred on the pit.
	var wood := VillageKit.Merged.new()
	wood.base = Transform3D(Basis.IDENTITY, at)
	for log in 3:
		var offset := Vector3(0.0, 0.10 + float(log % 2) * 0.19, float(log) * 0.07 - 0.07)
		VillageKit.add_beam(wood, FIREWOOD + offset + Vector3(-0.42, 0.0, 0.0),
			FIREWOOD + offset + Vector3(0.42, 0.0, 0.02), 0.085, mats["log"], 6, 0.075)
	VillageKit.add_ball(wood, 0.16, FIREWOOD + Vector3(0.0, 0.40, 0.0), mats["ash"],
		Vector3(1.6, 0.5, 1.2), 7, 4)
	wood.commit(holder, "Firewood")
	_record(root, "FireKerb", at, 1.62, false)
	for index in BENCH_ANGLES.size():
		var angle := deg_to_rad(float(BENCH_ANGLES[index]))
		_record(root, "FireBench%d" % (index + 1),
			at + Vector3(cos(angle) * 2.62, 0.0, sin(angle) * 2.62), 0.80)
	_record(root, "Firewood", at + FIREWOOD, 0.55)


## A split log on two stumps, laid across the fire's radius so it is a seat and
## not a wheel.
static func _bench(m, mats: Dictionary, centre: Vector3, angle: float, index: int) -> void:
	var across := Vector3(-sin(angle), 0.0, cos(angle))
	for side in [-1.0, 1.0]:
		var foot: Vector3 = centre + across * (float(side) * 0.50)
		VillageKit.add_beam(m, foot + Vector3(0.0, -0.10, 0.0), foot + Vector3(0.0, 0.36, 0.0),
			0.11, mats["log_dark"], 6, 0.10)
	VillageKit.add_beam(m, centre - across * 0.72 + Vector3(0.0, 0.38, 0.0),
		centre + across * 0.72 + Vector3(0.0, 0.38, 0.0), 0.19, mats["log"], 7, 0.19)
	# A rag somebody left on the seat.
	VillageKit.add_box(m, Vector3(0.40, 0.02, 0.28), centre + Vector3(0.0, 0.57, 0.0),
		mats["rag"], -angle + float(index) * 0.4)


# --- the lanterns ----------------------------------------------------------

## Four lanterns on the square's diagonals: a post, an arm reaching in over the
## square, an iron lantern with four lit panes, and the light pool it casts.
static func _build_lanterns(root: Root, mats: Dictionary, own: Dictionary) -> void:
	var holder := _group(root, "LanternPools")
	for index in LANTERN_POSTS.size():
		var at: Vector3 = LANTERN_POSTS[index]
		var node := Node3D.new()
		node.name = "Lantern%d" % (index + 1)
		node.position = at
		node.rotation.y = _inward(at)
		holder.add_child(node)
		var m := VillageKit.Merged.new()
		VillageKit.add_ball(m, 0.22, Vector3(0.0, 0.04, 0.0), mats["stone"],
			Vector3(1.3, 0.4, 1.3), 7, 4)
		VillageKit.add_beam(m, Vector3(0.0, -0.12, 0.0), Vector3(0.02, 2.88, 0.0), 0.085,
			mats["timber"], 6, 0.062)
		VillageKit.add_beam(m, Vector3(0.0, 2.72, 0.0), Vector3(0.0, 2.80, 0.60), 0.045,
			own["iron"], 5)
		VillageKit.add_beam(m, Vector3(0.0, 2.34, 0.0), Vector3(0.0, 2.72, 0.34), 0.026,
			own["iron"], 4)
		var lamp := Vector3(0.0, 2.44, 0.60)
		VillageKit.add_ring(m, Vector3(0.0, 2.86, 0.60), 0.0, 0.045, 0.075, own["iron"],
			PI * 0.5, 8, 3)
		VillageKit.add_beam(m, Vector3(0.0, 2.84, 0.60), Vector3(0.0, 2.63, 0.60), 0.012,
			own["iron"], 4)
		VillageKit.add_box(m, Vector3(0.26, 0.05, 0.26), lamp + Vector3(0.0, 0.18, 0.0),
			own["iron"])
		VillageKit.add_box(m, Vector3(0.26, 0.05, 0.26), lamp + Vector3(0.0, -0.18, 0.0),
			own["iron"])
		for corner in [[-1.0, -1.0], [-1.0, 1.0], [1.0, -1.0], [1.0, 1.0]]:
			VillageKit.add_beam(m, lamp + Vector3(corner[0] * 0.10, -0.18, corner[1] * 0.10),
				lamp + Vector3(corner[0] * 0.10, 0.18, corner[1] * 0.10), 0.018, own["iron"], 4)
		VillageKit.add_box(m, Vector3(0.20, 0.30, 0.20), lamp, own["lamp"])
		m.commit(node, "LanternPost")
		var light := FireFlicker.new()
		light.name = "LanternLight"
		light.position = lamp
		light.light_color = Color(1.0, 0.76, 0.44)
		light.light_energy = 2.0
		light.omni_range = 9.5
		light.omni_attenuation = 1.5
		light.shadow_enabled = false
		light.flicker = 0.09
		node.add_child(light)
		_record(root, "Lantern%d" % (index + 1), at, 0.50)
