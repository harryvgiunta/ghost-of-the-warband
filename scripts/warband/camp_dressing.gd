extends RefCounted
## The cage camp's dressing: everything the yard is *read* from.
##
## `cage_escape.gd` builds the camp's bones - the floor, the palisade, four bar
## cages, a cold altar, nine torches - and nothing else. This module is the rest
## of what a cult's holding pen looks like: padlocks and slack chain on the cage
## doors, the cult's banners on the palisade, two gibbets on the approach, the
## dressing around the cold altar, ember braziers that burn on the existing flame
## shader, and the litter of a yard people were dragged through - straw, blood,
## cart ruts.
##
## Three rules hold this together.
##
## 1. **Presentation only.** Nothing here is a `PhysicsBody3D`; the yard is the
##    play space and a prop must never stand where a body spawns, walks or
##    fights. The regression proves it: the root carries `props`, one record per
##    prop (`name`, `position`, `radius`, `blocks`, `zone`), and `blocks` is true
##    only for a prop that has a footprint a body would stand in. Flat ground
##    litter is `blocks = false`, so it may lie under a spawn ring.
## 2. **The forest's palette.** Geometry is merged the way the world kits merge
##    it - one `MeshInstance3D` per prop group, one surface per material - and
##    every material comes from `CampKit.materials()` (textured timber, hide,
##    bone, ochre), `TextureLibrary`'s flame shader, or `Geo.material()` for the
##    things the kits do not carry (iron, blood, rutted earth).
## 3. **The scene owns the layout.** Cage centres and the altar are read off the
##    nodes `cage_escape.gd` already placed, so a moved cage moves its hardware.
##    Only the yard's own bounds and the free-standing posts are declared here,
##    and `YARD_*` mirrors the scene's constants - the regression fails loudly if
##    the two ever drift apart.

const Geo = preload("res://scripts/geo.gd")

## The yard this dressing is laid out inside. Mirrors `cage_escape.gd`'s
## `YARD_HALF_WIDTH` / `YARD_FRONT` / `YARD_BACK`; the regression compares them.
const YARD_HALF_WIDTH := 30.0
const YARD_FRONT := -42.0
const YARD_BACK := 26.0
## The wider floor under it (100 x 140 m at z = -16). The gibbets stand outside
## the palisade but still on ground, framing the gate the reinforcements run
## through.
const FLOOR_HALF_WIDTH := 50.0
const FLOOR_FRONT := -86.0
const FLOOR_BACK := 54.0

## Four cages, in `CAGE_POSTS` order: `Cage1`..`Cage4`.
const CAGE_COUNT := 4

## Cult banners lashed to the inside of the palisade: two per side wall, two on
## the back wall. They are hung well clear of the cage line, so the walk from the
## cages to the gate is a corridor of cloth.
const BANNER_POSTS := [
	Vector3(-28.9, 0.0, -30.0), Vector3(-28.9, 0.0, 4.0),
	Vector3(28.9, 0.0, -19.0), Vector3(28.9, 0.0, 15.0),
	Vector3(-12.0, 0.0, 24.9), Vector3(12.0, 0.0, 24.9),
]

## The gibbets: outside the palisade, one either side of the gate road, at the
## far edge of the fog. Nothing of the fight ever reaches them.
const GIBBET_POSTS := [
	Vector3(-12.5, 0.0, -46.5), Vector3(13.5, 0.0, -47.5),
]

## Ember braziers: two flanking the gate approach inside the yard, two lighting
## the long flanks. Each stands clear of the torches the scene already carries.
const BRAZIER_POSTS := [
	Vector3(-9.5, 0.0, -33.5), Vector3(9.5, 0.0, -33.5),
	Vector3(-21.5, 0.0, -12.0), Vector3(21.5, 0.0, -12.0),
]

## Straw dragged out of the cages and never swept up: flat ground litter, so it
## may lie anywhere it looks right.
const STRAW_POSTS := [
	Vector3(-6.6, 0.0, 4.2), Vector3(-4.4, 0.0, 3.5), Vector3(0.0, 0.0, 3.9),
	Vector3(4.8, 0.0, 3.4), Vector3(8.6, 0.0, 4.6), Vector3(-1.9, 0.0, 9.2),
	Vector3(6.8, 0.0, 10.4), Vector3(-9.6, 0.0, 7.6), Vector3(2.2, 0.0, -2.6),
]

## Blood: thin, dark stains of a yard that has been used. Flat, so also no
## footprint.
const BLOOD_POSTS := [
	Vector3(0.0, 0.0, 4.6), Vector3(-4.7, 0.0, -2.0), Vector3(3.2, 0.0, -6.0),
	Vector3(-1.6, 0.0, -14.0), Vector3(6.4, 0.0, 2.2), Vector3(-8.2, 0.0, -18.5),
]

## Cart ruts: the two tracks that run from the gate into the yard, stopping
## short of the cage line.
const RUT_FROM := 4.0
const RUT_TO := -37.0
const RUT_HALF_TRACK := 1.15

static var _fittings: Dictionary = {}


## The dressing root. A plain `Node3D` that carries the prop records the
## regression reads back, so the scene script never has to know them.
class Root extends Node3D:
	var props: Array = []


## Builds the whole camp dressing under `scene` and returns its root. The caller
## owns the node from then on; nothing here is ever rebuilt.
static func build(scene: Node3D) -> Node3D:
	if scene == null:
		return null
	var root := Root.new()
	root.name = "CampDressing"
	scene.add_child(root)
	var mats: Dictionary = CampKit.materials()
	var iron := metal()
	_build_cage_hardware(root, scene, mats, iron)
	_build_banners(root, mats)
	_build_gibbets(root, mats, iron)
	_build_altar(root, scene, mats, iron)
	_build_braziers(root, mats, iron)
	_build_scatter(root, mats, iron)
	print("CAMP_DRESSING_READY props=%d" % root.props.size())
	return root


# --- palette ---------------------------------------------------------------

## The few materials the forest kits do not carry. `Geo.material` is the shared
## flat-colour helper the two warband scenes already build their own palettes
## with, so the camp stays in the same convention.
static func metal() -> Dictionary:
	if not _fittings.is_empty():
		return _fittings
	var m: Dictionary = {}
	m["iron"] = Geo.material(Color(0.17, 0.17, 0.18), 0.62, 0.52)
	m["steel"] = Geo.material(Color(0.34, 0.35, 0.37), 0.72, 0.40)
	m["blood"] = Geo.material(Color(0.125, 0.022, 0.022), 0.0, 0.90)
	m["rut"] = Geo.material(Color(0.070, 0.060, 0.052), 0.0, 0.99)
	_fittings = m
	return m


## The flame shader asking in a cold blue instead of firelight: the altar burns
## for something that is not warmth. `TextureLibrary.flame_material()` is shared
## and cached, so the cold variant has to be its own duplicate.
static func cold_flame() -> ShaderMaterial:
	var cold: ShaderMaterial = TextureLibrary.flame_material().duplicate()
	cold.set_shader_parameter("hot_color", Color(0.62, 0.80, 1.0))
	cold.set_shader_parameter("cool_color", Color(0.20, 0.38, 0.92))
	cold.set_shader_parameter("glow", 1.1)
	cold.set_shader_parameter("waver", 0.12)
	return cold


# --- plumbing --------------------------------------------------------------

static func _group(root: Node3D, label: String) -> Node3D:
	var node := Node3D.new()
	node.name = label
	root.add_child(node)
	return node


static func _record(root: Root, label: String, at: Vector3, radius: float,
		blocks: bool = true, zone: String = "yard") -> void:
	root.props.append({
		"name": label, "position": at, "radius": radius,
		"blocks": blocks, "zone": zone,
	})


## Yaw that turns a prop's local +Z toward the middle of the camp, which is how
## a banner faces the yard and a gibbet faces the gate.
static func _inward(at: Vector3) -> float:
	return atan2(-at.x, -at.z)


## A handful of broken straw: thin tapered straws leaning out of a heap.
static func _straw(m, mats: Dictionary, at: Vector3, rng: RandomNumberGenerator,
		spread: float, amount: int) -> void:
	for strand in amount:
		var angle := rng.randf_range(0.0, TAU)
		var foot := at + Vector3(cos(angle) * rng.randf_range(0.0, spread), 0.0,
			sin(angle) * rng.randf_range(0.0, spread))
		var tip := foot + Vector3(cos(angle) * rng.randf_range(0.12, 0.36),
			rng.randf_range(0.05, 0.24), sin(angle) * rng.randf_range(0.12, 0.34))
		CampKit.add_beam(m, foot, tip, rng.randf_range(0.009, 0.019),
			mats["thatch"] if strand % 2 == 0 else mats["thatch_dark"], 3, 0.004)


# --- the cages -------------------------------------------------------------

## Padlocks, hasp, slack chain, straw and bone charms on the four cages.
##
## Every iron fitting sits on the *fixed* frame, never on the door: the door is
## the node `cage_escape.gd` lifts when the latch is cut, and a padlock welded to
## it would rise into the sky with the bars.
static func _build_cage_hardware(root: Root, scene: Node3D, mats: Dictionary,
		iron: Dictionary) -> void:
	var holder := _group(root, "CageHardware")
	for index in CAGE_COUNT:
		var cage := scene.get_node_or_null("Cage%d" % (index + 1)) as Node3D
		if cage == null:
			continue
		var centre: Vector3 = cage.position
		var m := CampKit.Merged.new()
		# The door face is local -Z. Hasp across the door's right edge onto the
		# corner post, with the padlock hanging off the post's outer corner: the
		# hardware is the cage's, never the caged body's.
		CampKit.add_box(m, Vector3(0.36, 0.10, 0.06), Vector3(1.14, 1.22, -1.24), iron["iron"])
		CampKit.add_ring(m, Vector3(1.08, 1.22, -1.31), 0.0, 0.048, 0.072, iron["iron"],
			PI * 0.5, 8, 4)
		CampKit.add_box(m, Vector3(0.13, 0.17, 0.09), Vector3(1.08, 1.05, -1.33), iron["iron"])
		CampKit.add_ring(m, Vector3(1.08, 1.15, -1.33), 0.0, 0.042, 0.064, iron["steel"],
			PI * 0.5, 8, 4)
		CampKit.add_box(m, Vector3(0.03, 0.05, 0.03), Vector3(1.08, 1.01, -1.36), iron["steel"])
		# Two strap irons banding the corner post it is bolted to.
		for strap in 2:
			CampKit.add_box(m, Vector3(0.21, 0.05, 0.21),
				Vector3(1.15, 0.62 + float(strap) * 0.86, -1.15), iron["iron"])
		# A slack chain from the front-left post, then the same chain coiled in
		# the dirt where somebody dropped it.
		var from := Vector3(-1.17, 1.68, -1.20)
		var to := Vector3(-1.92, 0.12, -1.06)
		for link in 7:
			var t := (float(link) + 0.5) / 7.0
			var at := from.lerp(to, t)
			at.y -= sin(t * PI) * 0.10
			CampKit.add_ring(m, at, 0.0, 0.036, 0.060, iron["iron"],
				PI * 0.5 if link % 2 == 0 else 0.0, 8, 4)
		for coil in 4:
			CampKit.add_ring(m, Vector3(-1.94, 0.035 + float(coil) * 0.045, -1.28),
				0.4 * float(coil), 0.10 + float(coil) * 0.02, 0.135 + float(coil) * 0.02,
				iron["iron"], 0.0, 9, 4)
		# Straw bedding kicked out through the bars, and a heap at the back.
		var rng := RandomNumberGenerator.new()
		rng.seed = 331 + index * 29
		_straw(m, mats, Vector3(-1.68, 0.0, -1.62), rng, 0.30, 8)
		_straw(m, mats, Vector3(1.56, 0.0, -1.70), rng, 0.26, 7)
		_straw(m, mats, Vector3(0.30, 0.0, 1.62), rng, 0.34, 9)
		# The cult's marks: a bone charm on one post and a rune board on the
		# other, both high enough to clear a body's shoulders.
		CampKit.add_hanging(m, mats, Vector3(-1.15, 2.66, -1.30), 0.0, 101 + index * 3, 0.40)
		CampKit.add_hanging(m, mats, Vector3(1.16, 2.66, -1.30), PI, 117 + index, 0.38)
		var node := m.commit(holder, "Cage%dHardware" % (index + 1))
		if node != null:
			node.position = centre
		_record(root, "Cage%dPadlock" % (index + 1), centre + Vector3(1.08, 0.0, -1.33), 0.24)
		_record(root, "Cage%dChain" % (index + 1), centre + Vector3(-1.90, 0.0, -1.20), 0.46)
		_record(root, "Cage%dStrawFront" % (index + 1), centre + Vector3(-1.68, 0.0, -1.62), 0.34, false)
		_record(root, "Cage%dStrawBack" % (index + 1), centre + Vector3(0.30, 0.0, 1.62), 0.38, false)
		_record(root, "Cage%dCharms" % (index + 1), centre + Vector3(0.0, 0.0, -1.30), 0.22, false)


# --- the palisade ----------------------------------------------------------

## The cult's banners: a mast lashed against the palisade, a crossbar, one long
## hide standard with the ochre sigil and the tally marks, a torn strip beside
## it and an antlered skull on top.
static func _build_banners(root: Root, mats: Dictionary) -> void:
	var holder := _group(root, "Banners")
	for index in BANNER_POSTS.size():
		var at: Vector3 = BANNER_POSTS[index]
		var m := CampKit.Merged.new()
		m.base = Transform3D(Basis(Vector3.UP, _inward(at)), at)
		CampKit.add_beam(m, Vector3(0.0, -0.15, 0.0), Vector3(0.05, 3.55, 0.02), 0.055,
			mats["twig_dark"], 5, 0.045)
		CampKit.add_beam(m, Vector3(-0.52, 3.24, 0.0), Vector3(0.52, 3.30, 0.0), 0.042,
			mats["drift"], 5, 0.030)
		CampKit.add_ball(m, 0.07, Vector3(0.0, 3.28, 0.0), mats["rag"],
			Vector3(1.2, 0.8, 1.2), 6, 4)
		# The two lashings holding the crossbar to the mast.
		for side in [-1.0, 1.0]:
			CampKit.add_ring(m, Vector3(side * 0.06, 3.27, 0.0), 0.0, 0.055, 0.085,
				mats["rag"], PI * 0.5, 8, 3)
		# Stays down to the wall top: the standard is tied to the palisade, not
		# standing in the yard on its own. The wall is 0.8 m behind the mast.
		for stay in 2:
			CampKit.add_beam(m, Vector3(0.0, 2.05 + float(stay) * 0.90, 0.0),
				Vector3(0.0, 1.88, -0.86), 0.015, mats["rag"], 3)
		# The standard itself: one long panel, one torn strip, and the sigil.
		CampKit.add_box(m, Vector3(0.90, 1.72, 0.035), Vector3(-0.02, 2.36, 0.06),
			mats["hide_dark"], 0.0, 0.0, -0.04)
		CampKit.add_box(m, Vector3(0.34, 0.62, 0.020), Vector3(0.62, 1.72, 0.05),
			mats["hide"], 0.0, 0.0, 0.10)
		CampKit.add_box(m, Vector3(0.30, 0.30, 0.02), Vector3(-0.02, 2.52, 0.086),
			mats["ochre"], 0.0, 0.0, PI * 0.25)
		for mark in 3:
			CampKit.add_box(m, Vector3(0.035, 0.24, 0.02),
				Vector3(-0.16 + float(mark) * 0.14, 2.06, 0.086), mats["ochre"], 0.0, 0.0, 0.12)
		# The skull that crowns it, muzzle into the yard.
		CampKit.add_skull(m, mats, Vector3(0.02, 3.62, 0.04), PI, 0.62, index % 2 == 0)
		CampKit.add_antler(m, mats, Vector3(-0.10, 3.70, 0.02), PI + 0.5, 0.7)
		m.commit(holder, "Banner%d" % (index + 1))
		_record(root, "Banner%d" % (index + 1), at, 0.60)


# --- the approach ----------------------------------------------------------

## Two gibbets on the road the reinforcements come down: two posts, a beam and
## the iron cage hanging off it, with what was left in the cage still there.
static func _build_gibbets(root: Root, mats: Dictionary, iron: Dictionary) -> void:
	var holder := _group(root, "Gibbets")
	for index in GIBBET_POSTS.size():
		var at: Vector3 = GIBBET_POSTS[index]
		var m := CampKit.Merged.new()
		m.base = Transform3D(Basis(Vector3.UP, _inward(at)), at)
		for side in [-1.0, 1.0]:
			CampKit.add_ball(m, 0.26, Vector3(side * 1.25, 0.02, 0.0), mats["boulder_stone"],
				Vector3(1.2, 0.4, 1.2), 7, 4)
			CampKit.add_beam(m, Vector3(side * 1.25, -0.18, 0.0),
				Vector3(side * 1.18, 3.72, side * 0.04), 0.12, mats["twig_dark"], 6, 0.09)
			CampKit.add_beam(m, Vector3(side * 1.15, 2.96, 0.0),
				Vector3(side * 0.30, 3.58, 0.0), 0.05, mats["twig"], 4, 0.034)
		CampKit.add_beam(m, Vector3(-1.34, 3.64, 0.0), Vector3(1.34, 3.64, 0.02), 0.10,
			mats["drift"], 6, 0.085)
		CampKit.add_beam(m, Vector3(0.0, 3.60, 0.0), Vector3(0.02, 2.74, 0.0), 0.026,
			mats["rag"], 4)
		_gibbet_cage(m, mats, iron, Vector3(0.0, 2.74, 0.0), 400 + index * 37)
		m.commit(holder, "Gibbet%d" % (index + 1))
		_record(root, "Gibbet%d" % (index + 1), at, 1.50, true, "field")


static func _gibbet_cage(m, mats: Dictionary, iron: Dictionary, top: Vector3,
		seed_value: int) -> void:
	for row in [0.0, -0.55, -1.24]:
		CampKit.add_ring(m, top + Vector3(0.0, row, 0.0), 0.0, 0.44, 0.50, iron["iron"],
			0.0, 12, 4)
	for bar in 8:
		var angle := TAU * float(bar) / 8.0
		var base := top + Vector3(cos(angle) * 0.45, -1.24, sin(angle) * 0.45)
		CampKit.add_beam(m, base, base + Vector3(0.0, 1.24, 0.0), 0.022, iron["steel"], 4)
	# What the cage was for.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	CampKit.add_skull(m, mats, top + Vector3(0.02, -1.06, 0.06), 0.4, 0.55, seed_value % 2 == 0)
	CampKit.add_beam(m, top + Vector3(-0.22, -0.74, -0.05), top + Vector3(0.24, -0.82, 0.12),
		0.026, mats["bone"], 3, 0.012)
	CampKit.add_beam(m, top + Vector3(-0.10, -0.92, 0.18),
		top + Vector3(0.14, -1.02, 0.24), 0.020, mats["bone"], 3, 0.010)
	for strip in 3:
		CampKit.add_box(m, Vector3(0.10, rng.randf_range(0.28, 0.46), 0.02),
			top + Vector3(rng.randf_range(-0.3, 0.3), -0.55, 0.46), mats["rag"],
			rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.2, 0.2))


# --- the cold altar --------------------------------------------------------

## The altar the cult works on the yard from. `cage_escape.gd` builds the stone
## itself; this is the service around it: steps down to the dirt, a ring of
## skull-topped sticks, ochre marks, blood, four cold candles burning on the
## flame shader, and the offering left on the slab.
static func _build_altar(root: Root, scene: Node3D, mats: Dictionary,
		iron: Dictionary) -> void:
	var holder := _group(root, "AltarDressing")
	var altar := scene.get_node_or_null("ColdAltar") as Node3D
	var at: Vector3 = altar.position if altar != null else Vector3(0.0, 0.0, 12.5)
	var m := CampKit.Merged.new()
	m.base = Transform3D(Basis.IDENTITY, at)
	# Two shallow steps down to the dirt, on the cage side.
	CampKit.add_box(m, Vector3(3.50, 0.14, 0.80), Vector3(0.0, 0.07, -1.05), mats["stone"])
	CampKit.add_box(m, Vector3(3.00, 0.14, 0.60), Vector3(0.0, 0.21, -0.62), mats["stone"])
	# The ring of skulls and the arc of ochre dashes around it.
	CampKit.skull_ring(m, mats, Vector3.ZERO, 3.05, 9, 611)
	# The cold fire the altar works with: the flame shader asked for its own
	# palette, so this is visibly a rite and not a hearth.
	var cold := cold_flame()
	var rng := RandomNumberGenerator.new()
	rng.seed = 907
	# The offering on the slab: a skull with horns, an iron dish holding a little
	# of the same cold fire, and bound twigs.
	CampKit.add_skull(m, mats, Vector3(0.0, 1.20, 0.42), 0.3, 0.9, true)
	CampKit.add_ball(m, 0.16, Vector3(-0.95, 1.16, 0.0), iron["steel"],
		Vector3(1.0, 0.42, 1.0), 8, 4)
	var dish := m.push(Transform3D(Basis.IDENTITY, Vector3(-0.95, 0.0, 0.0)))
	FireFx.flame_cards(m, cold, rng, 0.32, 1.20)
	m.group = dish
	for twig in 3:
		var angle := TAU * float(twig) / 3.0 + 0.4
		CampKit.add_beam(m, Vector3(1.02, 1.10, 0.0),
			Vector3(1.02 + cos(angle) * 0.30, 1.12, sin(angle) * 0.30), 0.024,
			mats["twig"], 3, 0.012)
	# The blood this slab was used for.
	CampKit.add_ball(m, 0.86, Vector3(0.10, 0.02, -1.95), iron["blood"],
		Vector3(1.35, 0.05, 1.0), 10, 3)
	CampKit.add_ball(m, 0.48, Vector3(-1.42, 0.02, -0.72), iron["blood"],
		Vector3(1.0, 0.05, 1.5), 10, 3)
	# Four cold candles, each on its own iron spike.
	for index in 4:
		var angle := TAU * float(index) / 4.0 + 0.4
		var foot := Vector3(cos(angle) * 1.90, 0.0, sin(angle) * 1.90)
		CampKit.add_beam(m, foot, foot + Vector3(0.0, 0.50, 0.0), 0.045, iron["iron"], 4, 0.028)
		CampKit.add_ball(m, 0.075, foot + Vector3(0.0, 0.51, 0.0), mats["char"],
			Vector3(1.4, 0.5, 1.4), 6, 4)
		var saved := m.push(Transform3D(Basis.IDENTITY, foot))
		FireFx.flame_cards(m, cold, rng, 0.50, 0.52)
		m.group = saved
	# A bone heap beside the steps: the altar's leavings, not the town's.
	CampKit.bone_heap(m, mats, Vector3(2.35, 0.0, -1.15), -0.6, 733)
	m.commit(holder, "ColdAltarDressing")

	var light := OmniLight3D.new()
	light.name = "ColdAltarLight"
	light.position = at + Vector3(0.0, 1.90, 0.0)
	light.light_color = Color(0.42, 0.58, 1.0)
	light.light_energy = 1.5
	light.omni_range = 10.0
	light.omni_attenuation = 1.2
	light.shadow_enabled = false
	holder.add_child(light)
	_record(root, "ColdAltarDressing", at, 3.35)


# --- the ember braziers ----------------------------------------------------

## Four braziers: an iron tripod, a bowl of coals, and a fire built out of the
## forest's own flame cards (`FireFx`) with embers rising off it and a light that
## breathes with them.
static func _build_braziers(root: Root, mats: Dictionary, iron: Dictionary) -> void:
	var holder := _group(root, "Braziers")
	for index in BRAZIER_POSTS.size():
		var at: Vector3 = BRAZIER_POSTS[index]
		var node := Node3D.new()
		node.name = "Brazier%d" % (index + 1)
		node.position = at
		holder.add_child(node)
		var rng := RandomNumberGenerator.new()
		rng.seed = 810 + index * 17
		var m := CampKit.Merged.new()
		for leg in 3:
			var angle := TAU * float(leg) / 3.0 + 0.3
			CampKit.add_beam(m, Vector3(cos(angle) * 0.52, 0.0, sin(angle) * 0.52),
				Vector3(cos(angle) * 0.10, 0.92, sin(angle) * 0.10), 0.045, iron["iron"],
				5, 0.032)
		CampKit.add_ring(m, Vector3(0.0, 0.42, 0.0), 0.0, 0.30, 0.34, iron["iron"], 0.0, 10, 4)
		var bowl := CylinderMesh.new()
		bowl.bottom_radius = 0.26
		bowl.top_radius = 0.46
		bowl.height = 0.26
		bowl.radial_segments = 12
		bowl.rings = 1
		m.add(bowl, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.04, 0.0)), iron["iron"])
		CampKit.add_ring(m, Vector3(0.0, 1.17, 0.0), 0.0, 0.44, 0.49, iron["steel"], 0.0, 12, 4)
		for coal in 4:
			var angle := TAU * float(coal) / 4.0 + 0.7
			CampKit.add_ball(m, 0.075, Vector3(cos(angle) * 0.16, 1.15, sin(angle) * 0.16),
				mats["ember"], Vector3(1.1, 0.55, 1.1), 6, 4)
		CampKit.add_ball(m, 0.14, Vector3(0.0, 1.16, 0.0), mats["fire_core"],
			Vector3(1.0, 0.40, 1.0), 7, 4)
		FireFx.flame_cards(m, mats["flame"], rng, 0.95, 1.14)
		m.commit(node, "Brazier")
		FireFx.embers(node, 1.18, 0.24, 18)
		var light := FireFlicker.new()
		light.name = "BrazierLight"
		light.position = Vector3(0.0, 1.62, 0.0)
		light.light_color = Color(1.0, 0.58, 0.24)
		light.light_energy = 1.9
		light.omni_range = 11.0
		light.omni_attenuation = 1.35
		light.flicker = 0.30
		node.add_child(light)
		_record(root, "Brazier%d" % (index + 1), at, 0.85)


# --- the ground ------------------------------------------------------------

## Litter: straw, blood and the cart ruts from the gate. All of it is flat, so
## none of it has a footprint and none of it may ever be a collider.
static func _build_scatter(root: Root, mats: Dictionary, iron: Dictionary) -> void:
	var holder := _group(root, "GroundScatter")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1471
	var straw := CampKit.Merged.new()
	for post in STRAW_POSTS:
		_straw(straw, mats, post, rng, 0.55, 9)
	straw.commit(holder, "StrawScatter", false)
	var blood := CampKit.Merged.new()
	for post in BLOOD_POSTS:
		CampKit.add_ball(blood, rng.randf_range(0.52, 0.95), post + Vector3(0.0, 0.02, 0.0),
			iron["blood"], Vector3(1.0, 0.03, rng.randf_range(0.70, 1.0)), 10, 3)
	blood.commit(holder, "BloodStains", false)
	var ruts := CampKit.Merged.new()
	var length := RUT_FROM - RUT_TO
	var centre := (RUT_FROM + RUT_TO) * 0.5
	for side in [-1.0, 1.0]:
		CampKit.add_box(ruts, Vector3(0.30, 0.030, length),
			Vector3(side * RUT_HALF_TRACK, 0.012, centre), iron["rut"])
	ruts.commit(holder, "CartRuts", false)
	for post in STRAW_POSTS:
		_record(root, "Straw", post, 0.42, false)
	for post in BLOOD_POSTS:
		_record(root, "Blood", post, 0.75, false)
	_record(root, "CartRuts", Vector3(0.0, 0.0, centre), 0.50, false)
