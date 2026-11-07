extends Node3D
## GHOST OF THE WARBAND: the deep wood at the far end of the road, and the thing
## that lives in it.
##
## This is where the run out of Hearthstead ends. The south end of the trail is a
## ragged pocket cut into the drowned wood - a broken stake ring, twig shelters, a
## fire ring, junk and trees standing inside it - and in the middle of it, on its
## own patch of trodden dirt, **the Horned Thing**: the goat-headed demon of the
## Hollow, standing in the open air where a party can find him.
##
## He is optional. Nothing opens here, nothing gates on him and no order points at
## him: the wood is a place a warband walks into if it wants what he is carrying,
## and the last body of the deepest den in the demo is the one thing in the wood
## that fights back properly. Two keepers of his own stand with him, because a
## master alone is a kite and not a fight.
##
## The geometry and the dressing are the camp's own builders (`camp_clearing.gd`
## for the pocket, `camp_dressing.gd` for the iron and the banners); the cages that
## used to stand here are gone with the opening they belonged to, so the clearing
## is built with no posts at all and the pocket reads as a held place somebody left
## in a hurry.

const ClearingScript = preload("res://scripts/warband/camp_clearing.gd")
const DressingScript = preload("res://scripts/warband/camp_dressing.gd")
const RunForestScript = preload("res://scripts/warband/run_forest.gd")
const DemonScript = preload("res://scripts/warband/delve_demon.gd")

## The pocket this ground was cut into. Mirrors `camp_dressing.gd`'s own copy; the
## regression compares them.
const YARD_HALF_WIDTH := 20.0
const YARD_FRONT := -30.0
const YARD_BACK := 22.0
## The gap the road comes in through, and the run of ordinary wood between it and
## the trail's first waypoint.
const GATE_POINT := Vector3(0.0, 0.0, -30.0)
const MOUTH_HALF_WIDTH := 6.0
const CAMP_TO_ROAD_METRES := 170.0
## Where the demon stands: the middle of the pocket, on its own patch, far enough
## from the mouth that a party walks in with the fight already in front of it.
const BOSS_POINT := Vector3(0.0, 0.0, 6.0)
## His guard: two of the wood's creatures, one either side of him.
const GUARD_POSTS := [Vector3(-3.4, 0.0, 4.2), Vector3(3.4, 0.0, 4.2)]
## The torches that light the pocket: the demon's patch, the fire, and the way in.
const TORCHES := [
	[Vector3(-5.5, 0.0, 2.0), 3.2], [Vector3(5.5, 0.0, 2.0), 3.2],
	[Vector3(-2.0, 0.0, 12.0), 2.6], [Vector3(2.0, 0.0, 12.0), 2.6],
	[Vector3(-6.0, 0.0, -24.0), 3.0], [Vector3(6.0, 0.0, -24.0), 3.0],
]

## The world this wood belongs to (set before the node enters the tree).
var host = null
var clearing: Dictionary = {}
## The master, and the two that stand with him.
var master = null
var guards: Array = []


## The dust and the ruts the ground map wears: the way in from the trail, and the
## cart ruts the dressing lays down.
static func trodden_ground() -> Array:
	var marks: Array = ClearingScript.trodden_ground([], [])
	marks.append({"points": ClearingScript.corridor_line(GATE_POINT, CAMP_TO_ROAD_METRES),
		"half_width": 2.6, "strength": 0.9})
	marks.append_array(DressingScript.rut_lines())
	return marks


## Where the demon stands (read by the regression and the map sheet).
func boss_point() -> Vector3:
	return BOSS_POINT


## Whether the master is still standing.
func master_alive() -> bool:
	return master != null and is_instance_valid(master) and bool(master.get("alive"))


func _ready() -> void:
	_build_clearing()
	_build_master()


func _build_clearing() -> void:
	var keep_clear: Array = []
	for post in DressingScript.GIBBET_POSTS:
		keep_clear.append({"point": post, "radius": 3.2})
	for post in DressingScript.BANNER_POSTS:
		keep_clear.append({"point": post, "radius": 2.2})
	for post in DressingScript.BRAZIER_POSTS:
		keep_clear.append({"point": post, "radius": 2.0})
	for entry in TORCHES:
		keep_clear.append({"point": entry[0], "radius": 1.6})
	# The demon's own patch: nothing grows where the fight is meant to happen.
	keep_clear.append({"point": BOSS_POINT, "radius": 7.5})
	for post in GUARD_POSTS:
		keep_clear.append({"point": post, "radius": 2.2})
	clearing = ClearingScript.build(self, {
		"half_width": YARD_HALF_WIDTH,
		"front": YARD_FRONT,
		"back": YARD_BACK,
		"cage_posts": [],
		"mouth": GATE_POINT,
		"mouth_half_width": MOUTH_HALF_WIDTH,
		"to_road": CAMP_TO_ROAD_METRES,
		"torches": TORCHES,
		"keep_clear": keep_clear,
	}, RunForestScript.night_style())
	DressingScript.build(self)


## The master and his pair. He is the Hollow's goat, in the open: five and a half
## times the goat's pool, a heavier blow, the floor's prize on his corpse, and a
## post he holds instead of roaming. Both halves are the same `devil_mob` AI the
## Hollow fields, so a party that has been below recognises him.
func _build_master() -> void:
	var ground: Vector3 = Vector3(BOSS_POINT.x, 0.0, BOSS_POINT.z)
	master = DemonScript.new()
	master.boss = true
	master.name = "HornedThing"
	master.position = ground
	master.rotation.y = PI
	add_child(master)
	master.home = ground
	master.safe_center = _safe_center()
	guards.append(master)
	for index in GUARD_POSTS.size():
		var post: Vector3 = GUARD_POSTS[index]
		var keeper := DemonScript.new()
		keeper.name = "WoodKeeper%d" % (index + 1)
		keeper.position = Vector3(post.x, 0.0, post.z)
		keeper.rotation.y = PI
		add_child(keeper)
		keeper.home = keeper.position
		keeper.safe_center = _safe_center()
		guards.append(keeper)
	if host != null:
		var listed: Array = host.get("guards")
		if listed != null:
			for body in guards:
				listed.append(body)
	print("WOOD_BOSS_READY guards=%d boss=%s" % [guards.size(), str(master.get("display"))])


## The square a demon will not chase into: Hearthstead's own fire.
func _safe_center() -> Vector3:
	if host != null:
		var town = host.get("town")
		if town is Node3D:
			return (town as Node3D).global_position
	return Vector3.ZERO


## Where a party stands when it walks in (read by the checkpoint ring).
func spawn_posts() -> Array[Vector3]:
	return [Vector3(0.0, 0.2, -18.0), Vector3(-2.4, 0.2, -18.6), Vector3(2.4, 0.2, -18.6)]
