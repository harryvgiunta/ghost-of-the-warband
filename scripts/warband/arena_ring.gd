class_name ArenaRing
extends Node3D
## The arena's ground: a walled stone ring built as one node, standing well above
## the campaign's own terrain.
##
## It is a **placeholder** on purpose - a flat disc of packed sand, twenty pillars
## and a gate with no ornament on it - because what the ring is for is the fight
## in the middle of it. The geometry is `Geo` primitives and one static body, so
## it costs a few hundred triangles and nothing else.

const Geo = preload("res://scripts/geo.gd")
const TerrainScript = preload("res://scripts/warband/terrain.gd")

## How high off the campaign's ground the ring stands. Out of sight of anything,
## and far enough that the heightfield's own 69 m crest cannot reach it.
const LIFT := 260.0
const RADIUS := 26.0
const WALL_RADIUS := 27.2
const PILLARS := 20
const PILLAR_HEIGHT := 4.4
const FLOOR_THICKNESS := 0.6
## Where a body stands when it walks in, and where the foe line stands: one arc
## at the south gate, one at the north wall.
const ENTRY_Z := -19.0
const FOE_Z := 15.0
const SPREAD := 4.2


## The pad's own centre.
static func centre() -> Vector3:
	return Vector3(0.0, LIFT, 0.0)


## A post on the entry arc, `index` of `count`.
static func entry_post(index: int, count: int = 3) -> Vector3:
	return _arc(index, count, ENTRY_Z)


## A post on the foes' line.
static func foe_post(index: int, count: int = 3) -> Vector3:
	return _arc(index, count, FOE_Z)


static func _arc(index: int, count: int, z: float) -> Vector3:
	var n := maxi(count, 1)
	var offset := (float(index) - float(n - 1) * 0.5) * SPREAD
	return Vector3(offset, LIFT + 0.1, z)


func _ready() -> void:
	_build()


func _build() -> void:
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.52, 0.45, 0.34)
	sand.roughness = 1.0
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.34, 0.33, 0.31)
	stone.roughness = 0.95

	var disc := Node3D.new()
	disc.name = "Sand"
	add_child(disc)
	Geo.cylinder(disc, RADIUS, RADIUS, FLOOR_THICKNESS,
		Vector3(0.0, -FLOOR_THICKNESS * 0.5, 0.0), sand, 40)

	var wall := Node3D.new()
	wall.name = "Wall"
	add_child(wall)
	for index in PILLARS:
		var angle := TAU * float(index) / float(PILLARS)
		# The gate: the two pillars either side of the south opening are left out.
		if _in_gate(angle):
			continue
		var at := Vector3(cos(angle) * WALL_RADIUS, PILLAR_HEIGHT * 0.5, sin(angle) * WALL_RADIUS)
		Geo.box(wall, Vector3(1.5, PILLAR_HEIGHT, 1.5), at, stone)
		Geo.box(wall, Vector3(2.1, 0.4, 2.1),
			at + Vector3(0.0, PILLAR_HEIGHT * 0.5 + 0.2, 0.0), stone)
	# The gate itself: two taller pillars and a lintel over them.
	for side in [-1.0, 1.0]:
		var post := Vector3(float(side) * 4.6, PILLAR_HEIGHT * 0.7, -WALL_RADIUS + 0.4)
		Geo.box(wall, Vector3(1.8, PILLAR_HEIGHT * 1.4, 1.8), post, stone)
	Geo.box(wall, Vector3(11.4, 0.9, 1.9),
		Vector3(0.0, PILLAR_HEIGHT * 1.4 + 0.45, -WALL_RADIUS + 0.4), stone)

	var body := StaticBody3D.new()
	body.name = "RingFloor"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(RADIUS * 2.0, FLOOR_THICKNESS, RADIUS * 2.0)
	shape.shape = box
	shape.position = Vector3(0.0, -FLOOR_THICKNESS * 0.5, 0.0)
	body.add_child(shape)
	# The wall is a real wall: a body that runs at it stops at it.
	for index in PILLARS:
		var angle := TAU * float(index) / float(PILLARS)
		if _in_gate(angle):
			continue
		var ring := CollisionShape3D.new()
		var ring_box := BoxShape3D.new()
		ring_box.size = Vector3(3.0, PILLAR_HEIGHT, 3.0)
		ring.shape = ring_box
		ring.position = Vector3(cos(angle) * WALL_RADIUS, PILLAR_HEIGHT * 0.5,
			sin(angle) * WALL_RADIUS)
		body.add_child(ring)

	var lamps := Node3D.new()
	lamps.name = "Torches"
	add_child(lamps)
	for index in 8:
		var angle := TAU * float(index) / 8.0
		var at := Vector3(cos(angle) * (WALL_RADIUS - 1.6), 2.6, sin(angle) * (WALL_RADIUS - 1.6))
		var light := OmniLight3D.new()
		light.position = at
		light.light_color = Color(1.0, 0.72, 0.38)
		light.light_energy = 3.2
		light.omni_range = 22.0
		light.shadow_enabled = false
		lamps.add_child(light)
		Geo.cylinder(lamps, 0.14, 0.1, 1.5, at - Vector3(0.0, 1.2, 0.0), stone, 6)


static func _in_gate(angle: float) -> bool:
	# The south opening: the arc the gate's two posts stand on.
	var south := -PI * 0.5
	var delta := absf(wrapf(angle - south, -PI, PI))
	return delta < 0.34
