extends RefCounted
## The Weeping Hollow's first floor, as authored: its ten areas, the rooms each is
## cut from, the six shafts a party comes down (and climbs out of), the dens, the
## master, and every light and prop. Pure data and the geometry asked of it -
## nothing here touches the scene tree, so the regression reads the plan without
## building a cave and a co-op guest's copy is the host's by construction.
##
## The floor is laid out for more than one party. The six shafts stand on the
## floor's rim, two rows of three, each in its own area and each at least fifty
## metres of rock from the next; the areas between them are dens, and Gorehorn's
## lair is the hub in the middle with a way in from every side. Every shaft is
## also a way up, so a party can climb out of whichever rope it reaches first.
##
## The frame is the cave's own: x across, +Z back toward the town's side, -Z
## deeper. Every room is an axis-aligned rectangle on the half-metre raster; two
## rooms connect only by sharing an edge (no two overlap - a lower ceiling would
## hang into the taller room), and everything that is not a room is rock.
##
## Everything below is authored at the floor's drawn size and the floor is built
## `SCALE` times it, so the table reads as the cave looks and one number makes the
## whole Hollow bigger: the rooms, the rock between them, the shafts and their
## landings, every den post, the master's ring and the plan the map draws. Nothing
## authored at the size of a body - the crowd's spacing, a light's reach, the
## ropes' landing ring - scales with the floor.

## How much bigger than the authored plan the floor is built. 2.0 is the shipped
## floor; 1.0 is the plan as drawn.
const SCALE := 2.0

## The raster the rock is derived from, and the rock's height: every wall rises to
## `TOP`, and each room's ceiling fills down from it to the room's own height.
const CELL := 0.5
const AUTHORED_TOP := 11.0
## The rock box the rooms are cut out of, in the cave's frame (x/z): every room
## plus at least two metres of rock on every side.
const AUTHORED_BOUNDS := Rect2(-80.0, -180.0, 160.0, 190.0)
## How many cells of rock behind a room's face its own shell draws. Nothing inside
## a room ever sees further into the rock, and a shell that stops here stays local
## to its room, so the renderer's per-object light limit only ever counts the
## lights near that room.
const WALL_CELLS := 4

## What the HUD calls each part of the floor.
const AREAS := {
	"mouth": "THE MOUTH",
	"den": "THE WATCHERS' DEN",
	"gallery": "THE DROWNED GALLERY",
	"ossuary": "THE OSSUARY",
	"garden": "THE PALE GARDEN",
	"mere": "THE BLACK MERE",
	"chapel": "THE BONE CHAPEL",
	"rooted": "THE ROOTED HALL",
	"workings": "THE OLD WORKINGS",
	"lair": "GOREHORN'S LAIR",
}

## The rooms, grouped by the area they belong to. A room with `tunnel` is a way
## between halls (smaller stone, fewer spires). The ways between dens and shafts
## bend on purpose: a den's sight runs down a straight tunnel, and a den that could
## see a landing - or the next den's fight - would wake the moment a party landed.
const AUTHORED_ROOMS := [
	# THE MOUTH: the old landing under the town's own rope, and the ways west and
	# east along the floor's southern rim.
	{"id": "mouth", "area": "mouth", "rect": Rect2(-7.0, -8.0, 14.0, 14.0), "height": 7.0},
	{"id": "first_way", "area": "mouth", "rect": Rect2(-2.5, -15.0, 5.0, 7.0), "height": 4.6, "tunnel": true},
	{"id": "first_bend", "area": "mouth", "rect": Rect2(-2.5, -20.0, 14.0, 5.0), "height": 4.6, "tunnel": true},
	{"id": "mouth_west", "area": "mouth", "rect": Rect2(-15.0, 0.0, 8.0, 4.0), "height": 4.4, "tunnel": true},
	{"id": "west_rise", "area": "mouth", "rect": Rect2(-19.0, -14.0, 4.0, 18.0), "height": 4.6, "tunnel": true},
	{"id": "mouth_east", "area": "mouth", "rect": Rect2(7.0, -6.0, 8.0, 4.0), "height": 4.4, "tunnel": true},
	{"id": "east_sink", "area": "mouth", "rect": Rect2(15.0, -6.0, 4.0, 14.0), "height": 4.6, "tunnel": true},
	# THE WATCHERS' DEN, and the way on from it to the lair's southern door.
	{"id": "first_drop", "area": "den", "rect": Rect2(6.5, -24.0, 5.0, 4.0), "height": 4.6, "tunnel": true},
	{"id": "den", "area": "den", "rect": Rect2(-10.0, -42.0, 22.0, 18.0), "height": 8.0},
	{"id": "den_north", "area": "den", "rect": Rect2(-8.0, -50.0, 4.0, 8.0), "height": 4.6, "tunnel": true},
	# THE DROWNED GALLERY: black water under witch-light, its shaft to the south
	# and its cistern on the way north to the ossuary.
	{"id": "west_reach", "area": "gallery", "rect": Rect2(-42.0, -14.0, 23.0, 4.0), "height": 4.6, "tunnel": true},
	{"id": "gallery", "area": "gallery", "rect": Rect2(-66.0, -24.0, 24.0, 14.0), "height": 7.5},
	{"id": "gallery_deep", "area": "gallery", "rect": Rect2(-66.0, -32.0, 16.0, 8.0), "height": 7.5},
	{"id": "gallery_neck", "area": "gallery", "rect": Rect2(-66.0, -10.0, 4.0, 8.0), "height": 4.6, "tunnel": true},
	{"id": "gallery_shaft", "area": "gallery", "rect": Rect2(-74.0, -2.0, 12.0, 10.0), "height": 6.5},
	{"id": "cistern_way", "area": "gallery", "rect": Rect2(-72.0, -30.0, 6.0, 4.0), "height": 4.4, "tunnel": true},
	{"id": "cistern_turn", "area": "gallery", "rect": Rect2(-76.0, -40.0, 4.0, 14.0), "height": 4.6, "tunnel": true},
	{"id": "cistern", "area": "gallery", "rect": Rect2(-72.0, -50.0, 16.0, 14.0), "height": 6.0},
	{"id": "oss_south_drop", "area": "gallery", "rect": Rect2(-66.0, -60.0, 4.0, 10.0), "height": 4.6, "tunnel": true},
	# THE OSSUARY: the charnel hall west of the lair, its niches in the west wall.
	{"id": "ossuary", "area": "ossuary", "rect": Rect2(-62.0, -100.0, 18.0, 26.0), "height": 8.5},
	{"id": "niche_a", "area": "ossuary", "rect": Rect2(-65.0, -96.0, 3.0, 4.0), "height": 3.4, "tunnel": true},
	{"id": "niche_b", "area": "ossuary", "rect": Rect2(-65.0, -89.0, 3.0, 4.0), "height": 3.4, "tunnel": true},
	{"id": "niche_c", "area": "ossuary", "rect": Rect2(-65.0, -82.0, 3.0, 4.0), "height": 3.4, "tunnel": true},
	{"id": "oss_south", "area": "ossuary", "rect": Rect2(-60.0, -74.0, 4.0, 10.0), "height": 4.6, "tunnel": true},
	{"id": "oss_south_jog", "area": "ossuary", "rect": Rect2(-66.0, -64.0, 10.0, 4.0), "height": 4.6, "tunnel": true},
	{"id": "lair_west_jog", "area": "ossuary", "rect": Rect2(-32.0, -92.0, 4.0, 12.0), "height": 4.6, "tunnel": true},
	{"id": "oss_east", "area": "ossuary", "rect": Rect2(-44.0, -84.0, 12.0, 4.0), "height": 4.6, "tunnel": true},
	{"id": "oss_north", "area": "ossuary", "rect": Rect2(-54.0, -104.0, 4.0, 4.0), "height": 4.6, "tunnel": true},
	# THE PALE GARDEN: a fungus grove on the way up from the ossuary, the garden
	# itself and its glade, and the shaft in its northern rock.
	{"id": "grove_south_jog", "area": "garden", "rect": Rect2(-62.0, -108.0, 12.0, 4.0), "height": 4.6, "tunnel": true},
	{"id": "grove_south", "area": "garden", "rect": Rect2(-62.0, -114.0, 4.0, 6.0), "height": 4.6, "tunnel": true},
	{"id": "grove", "area": "garden", "rect": Rect2(-74.0, -128.0, 16.0, 14.0), "height": 6.0},
	{"id": "grove_north", "area": "garden", "rect": Rect2(-74.0, -138.0, 4.0, 10.0), "height": 4.6, "tunnel": true},
	{"id": "garden", "area": "garden", "rect": Rect2(-74.0, -160.0, 24.0, 22.0), "height": 7.0},
	{"id": "garden_glade", "area": "garden", "rect": Rect2(-50.0, -154.0, 8.0, 12.0), "height": 7.0},
	{"id": "garden_neck", "area": "garden", "rect": Rect2(-66.0, -166.0, 4.0, 6.0), "height": 4.6, "tunnel": true},
	{"id": "garden_shaft", "area": "garden", "rect": Rect2(-72.0, -176.0, 12.0, 10.0), "height": 6.5},
	{"id": "garden_east", "area": "garden", "rect": Rect2(-42.0, -150.0, 6.0, 4.0), "height": 4.6, "tunnel": true},
	# THE BLACK MERE: the great cavern north of the lair round its lake, the shrine
	# on the way down to the lair, and the shaft behind it.
	{"id": "garden_east_jog", "area": "mere", "rect": Rect2(-36.0, -150.0, 4.0, 12.0), "height": 4.6, "tunnel": true},
	{"id": "mere_west", "area": "mere", "rect": Rect2(-32.0, -142.0, 12.0, 4.0), "height": 4.6, "tunnel": true},
	{"id": "mere", "area": "mere", "rect": Rect2(-20.0, -162.0, 38.0, 28.0), "height": 10.0},
	{"id": "mere_neck", "area": "mere", "rect": Rect2(-4.0, -168.0, 4.0, 6.0), "height": 4.6, "tunnel": true},
	{"id": "mere_shaft", "area": "mere", "rect": Rect2(-8.0, -178.0, 12.0, 10.0), "height": 6.5},
	{"id": "shrine_north", "area": "mere", "rect": Rect2(-14.0, -134.0, 4.0, 6.0), "height": 4.6, "tunnel": true},
	{"id": "shrine", "area": "mere", "rect": Rect2(-18.0, -128.0, 16.0, 14.0), "height": 6.0},
	{"id": "mere_east", "area": "mere", "rect": Rect2(18.0, -158.0, 12.0, 4.0), "height": 4.6, "tunnel": true},
	# THE BONE CHAPEL: a nave and its apse, the crypt on the way south to the
	# rooted hall, and the shaft north of the nave.
	{"id": "mere_east_jog", "area": "chapel", "rect": Rect2(30.0, -158.0, 4.0, 14.0), "height": 4.6, "tunnel": true},
	{"id": "chapel_west", "area": "chapel", "rect": Rect2(34.0, -148.0, 10.0, 4.0), "height": 4.6, "tunnel": true},
	{"id": "chapel", "area": "chapel", "rect": Rect2(44.0, -160.0, 18.0, 24.0), "height": 9.0},
	{"id": "apse", "area": "chapel", "rect": Rect2(62.0, -154.0, 6.0, 12.0), "height": 7.0},
	{"id": "chapel_neck", "area": "chapel", "rect": Rect2(52.0, -166.0, 4.0, 6.0), "height": 4.6, "tunnel": true},
	{"id": "chapel_shaft", "area": "chapel", "rect": Rect2(48.0, -176.0, 12.0, 10.0), "height": 6.5},
	{"id": "crypt_north", "area": "chapel", "rect": Rect2(58.0, -136.0, 4.0, 8.0), "height": 4.6, "tunnel": true},
	{"id": "crypt", "area": "chapel", "rect": Rect2(58.0, -128.0, 16.0, 14.0), "height": 6.0},
	# THE ROOTED HALL: east of the lair, under a ceiling of hanging roots.
	{"id": "crypt_south", "area": "rooted", "rect": Rect2(62.0, -114.0, 4.0, 6.0), "height": 4.6, "tunnel": true},
	{"id": "crypt_south_jog", "area": "rooted", "rect": Rect2(54.0, -108.0, 12.0, 4.0), "height": 4.6, "tunnel": true},
	{"id": "rooted_north", "area": "rooted", "rect": Rect2(54.0, -104.0, 4.0, 4.0), "height": 4.6, "tunnel": true},
	{"id": "rooted", "area": "rooted", "rect": Rect2(44.0, -100.0, 20.0, 24.0), "height": 8.0},
	{"id": "lair_east_jog", "area": "rooted", "rect": Rect2(28.0, -94.0, 4.0, 16.0), "height": 4.6, "tunnel": true},
	{"id": "rooted_west", "area": "rooted", "rect": Rect2(32.0, -94.0, 12.0, 4.0), "height": 4.6, "tunnel": true},
	{"id": "rooted_south", "area": "rooted", "rect": Rect2(54.0, -76.0, 4.0, 12.0), "height": 4.6, "tunnel": true},
	# THE OLD WORKINGS: a timbered gallery south of the rooted hall, the old
	# workings themselves and the shaft beside them.
	{"id": "rooted_south_jog", "area": "workings", "rect": Rect2(54.0, -64.0, 12.0, 4.0), "height": 4.6, "tunnel": true},
	{"id": "rooted_drop", "area": "workings", "rect": Rect2(62.0, -60.0, 4.0, 10.0), "height": 4.6, "tunnel": true},
	{"id": "upper", "area": "workings", "rect": Rect2(48.0, -50.0, 18.0, 14.0), "height": 6.0},
	{"id": "upper_way", "area": "workings", "rect": Rect2(50.0, -36.0, 4.0, 12.0), "height": 4.6, "tunnel": true},
	{"id": "upper_jog", "area": "workings", "rect": Rect2(44.0, -24.0, 10.0, 4.0), "height": 4.6, "tunnel": true},
	{"id": "workings_north", "area": "workings", "rect": Rect2(44.0, -20.0, 4.0, 4.0), "height": 4.6, "tunnel": true},
	{"id": "east_reach", "area": "workings", "rect": Rect2(19.0, 4.0, 21.0, 4.0), "height": 4.6, "tunnel": true},
	{"id": "workings", "area": "workings", "rect": Rect2(40.0, -16.0, 22.0, 24.0), "height": 6.5},
	{"id": "workings_neck", "area": "workings", "rect": Rect2(62.0, -8.0, 4.0, 4.0), "height": 4.4, "tunnel": true},
	{"id": "workings_shaft", "area": "workings", "rect": Rect2(66.0, -12.0, 12.0, 14.0), "height": 6.5},
	# GOREHORN'S LAIR, the hub, and its four ways in.
	{"id": "den_jog", "area": "lair", "rect": Rect2(-8.0, -54.0, 14.0, 4.0), "height": 4.6, "tunnel": true},
	{"id": "lair_south", "area": "lair", "rect": Rect2(2.0, -74.0, 4.0, 20.0), "height": 5.0, "tunnel": true},
	{"id": "lair_west", "area": "lair", "rect": Rect2(-28.0, -92.0, 11.0, 4.0), "height": 4.6, "tunnel": true},
	{"id": "lair_east", "area": "lair", "rect": Rect2(17.0, -82.0, 11.0, 4.0), "height": 4.6, "tunnel": true},
	{"id": "lair_north_jog", "area": "lair", "rect": Rect2(-6.0, -114.0, 16.0, 4.0), "height": 4.6, "tunnel": true},
	{"id": "lair_north", "area": "lair", "rect": Rect2(6.0, -110.0, 4.0, 6.0), "height": 4.6, "tunnel": true},
	{"id": "lair", "area": "lair", "rect": Rect2(-17.0, -104.0, 34.0, 30.0), "height": 10.0},
]

## The rooms the floor is built from: `AUTHORED_ROOMS` at `SCALE`.
static var ROOMS: Array = _scaled_rooms(AUTHORED_ROOMS)

## The six shafts. Each is a rope out of a hole in its chamber's roof - the way a
## party comes down and a way up for any party that reaches it - with the landing
## ring in front of it, facing out of the chamber. `centre` stands 5.4 m in front
## of the rope as drawn here (10.8 m at `SCALE` 2), so even the ring's nearest post
## is out of the rope's reach: a body that has just landed is never already
## climbing out.
const AUTHORED_LANDINGS := [
	{"id": "mouth", "area": "mouth", "room": "mouth",
		"rope": Vector3(0.0, 0.0, 3.6), "centre": Vector3(0.0, 0.0, -1.8), "yaw": 0.0},
	{"id": "gallery", "area": "gallery", "room": "gallery_shaft",
		"rope": Vector3(-68.0, 0.0, 6.4), "centre": Vector3(-68.0, 0.0, 1.0), "yaw": 0.0},
	{"id": "workings", "area": "workings", "room": "workings_shaft",
		"rope": Vector3(76.4, 0.0, -5.0), "centre": Vector3(71.0, 0.0, -5.0), "yaw": PI * 0.5},
	{"id": "garden", "area": "garden", "room": "garden_shaft",
		"rope": Vector3(-66.0, 0.0, -174.4), "centre": Vector3(-66.0, 0.0, -169.0), "yaw": PI},
	{"id": "mere", "area": "mere", "room": "mere_shaft",
		"rope": Vector3(-2.0, 0.0, -176.4), "centre": Vector3(-2.0, 0.0, -171.0), "yaw": PI},
	{"id": "chapel", "area": "chapel", "room": "chapel_shaft",
		"rope": Vector3(54.0, 0.0, -174.4), "centre": Vector3(54.0, 0.0, -169.0), "yaw": PI},
]

## The shafts the floor is built from: `AUTHORED_LANDINGS` at `SCALE`.
static var LANDINGS: Array = _scaled_landings(AUTHORED_LANDINGS)

## The dens, as authored. Each body stands its post facing one of its den's doors
## (`face`), so its sight cone is what notices a party coming in; a den with two
## doors watches both. Every den's posts are more than a shout (12 m) from every
## other den's. These are the posts a den was written with; the den fields
## `DEN_CROWD` times as many (`den_members`).
const AUTHORED_DENS := [
	{"id": "den", "label": "The watchers' den wakes.", "room": "den", "members": [
		{"species": "hollow_warden", "at": Vector3(-4.5, 0.0, -35.0), "face": Vector3(9.0, 0.0, -24.0)},
		{"species": "ossuary_stalker", "at": Vector3(4.0, 0.0, -37.5), "face": Vector3(9.0, 0.0, -24.0)},
		{"species": "hollow_warden", "at": Vector3(0.5, 0.0, -31.0), "face": Vector3(-6.0, 0.0, -42.0)},
	]},
	{"id": "cistern", "label": "Something moves in the cistern.", "room": "cistern", "members": [
		{"species": "hollow_warden", "at": Vector3(-64.0, 0.0, -40.0), "face": Vector3(-72.0, 0.0, -38.0)},
		{"species": "ossuary_stalker", "at": Vector3(-60.0, 0.0, -46.5), "face": Vector3(-64.0, 0.0, -50.0)},
	]},
	{"id": "ossuary", "label": "The ossuary stirs.", "room": "ossuary", "members": [
		{"species": "ossuary_stalker", "at": Vector3(-49.0, 0.0, -80.0), "face": Vector3(-44.0, 0.0, -82.0)},
		{"species": "gallowsroot", "at": Vector3(-53.0, 0.0, -88.0), "face": Vector3(-44.0, 0.0, -82.0)},
		{"species": "hollow_warden", "at": Vector3(-56.0, 0.0, -79.0), "face": Vector3(-58.0, 0.0, -74.0)},
		{"species": "ossuary_stalker", "at": Vector3(-50.0, 0.0, -95.0), "face": Vector3(-52.0, 0.0, -100.0)},
	]},
	{"id": "grove", "label": "The grove's sleepers wake.", "room": "grove", "members": [
		{"species": "ossuary_stalker", "at": Vector3(-68.0, 0.0, -121.0), "face": Vector3(-72.0, 0.0, -128.0)},
		{"species": "hollow_warden", "at": Vector3(-63.0, 0.0, -118.0), "face": Vector3(-60.0, 0.0, -114.0)},
	]},
	{"id": "shrine", "label": "The drowned shrine has keepers.", "room": "shrine", "members": [
		{"species": "hollow_warden", "at": Vector3(-10.0, 0.0, -121.0), "face": Vector3(-12.0, 0.0, -128.0)},
		{"species": "gallowsroot", "at": Vector3(-6.0, 0.0, -118.0), "face": Vector3(-4.0, 0.0, -114.0)},
	]},
	{"id": "crypt", "label": "The crypt's dead get up.", "room": "crypt", "members": [
		{"species": "ossuary_stalker", "at": Vector3(65.0, 0.0, -122.0), "face": Vector3(60.0, 0.0, -128.0)},
		{"species": "hollow_warden", "at": Vector3(67.0, 0.0, -118.0), "face": Vector3(64.0, 0.0, -114.0)},
	]},
	{"id": "rooted", "label": "The rooted hall wakes.", "room": "rooted", "members": [
		{"species": "gallowsroot", "at": Vector3(52.0, 0.0, -88.0), "face": Vector3(44.0, 0.0, -92.0)},
		{"species": "hollow_warden", "at": Vector3(49.0, 0.0, -93.0), "face": Vector3(44.0, 0.0, -92.0)},
		{"species": "ossuary_stalker", "at": Vector3(57.0, 0.0, -95.0), "face": Vector3(56.0, 0.0, -100.0)},
		{"species": "hollow_warden", "at": Vector3(57.0, 0.0, -81.0), "face": Vector3(56.0, 0.0, -76.0)},
	]},
	{"id": "upper", "label": "The old workings are not empty.", "room": "upper", "members": [
		{"species": "hollow_warden", "at": Vector3(55.0, 0.0, -42.0), "face": Vector3(52.0, 0.0, -36.0)},
		{"species": "ossuary_stalker", "at": Vector3(61.0, 0.0, -46.0), "face": Vector3(64.0, 0.0, -50.0)},
	]},
]

## The dens the floor is built from: `AUTHORED_DENS` at `SCALE`, every post and
## the door it faces moved out with its room.
static var DENS: Array = _scaled_dens(AUTHORED_DENS)

## The floor is crowded: every den fields `DEN_CROWD` bodies for each post it was
## authored with. The authored posts stand first, exactly as written; the crowd is
## laid across the den's own room, each body on the free spot furthest from every
## body already placed, with the species and the door of the post it repeats.
const DEN_CROWD := 10
## Where a crowd body may stand: `CROWD_WALL` in from the room's rock,
## `CROWD_DOOR` from the middle of any way out (a body in a doorway blocks it, and
## a door is where a sleeper's sight runs furthest), `CROWD_CLEAR` past the
## footprint of every light and prop in the room (the roots hang from the roof and
## stop nobody), and `CROWD_SPACING` from the next body.
const CROWD_WALL := 1.5
const CROWD_DOOR := 3.0
const CROWD_CLEAR := 2.0
const CROWD_SPACING := 1.8
## The lattice the crowd's spots are read from.
const CROWD_STEP := 1.0
const OVERHEAD_PROPS := ["roots"]

## The floor's master, on the blood ring in the middle of the lair, facing the
## southern door.
const MASTER_ROOM := "lair"
const AUTHORED_MASTER_POINT := Vector3(0.0, 0.0, -89.0)
const MASTER_YAW := PI
## The master's ring on the floor the plan is built at: `AUTHORED_MASTER_POINT` at
## `SCALE`.
static var MASTER_POINT: Vector3 = _flat(AUTHORED_MASTER_POINT)

## Every light, by the room it lights. Wall kinds (`sconce`, `witch`, `lantern`,
## `fungus`) name a wall (`n` the room's deep edge, `s` its near edge, `w`, `e`) and
## how far along it, from the edge's low corner, they hang; floor kinds (`fire`,
## `brazier`, `candles`) stand at `at`.
const AUTHORED_LIGHTS := [
	{"kind": "sconce", "room": "mouth", "wall": "w", "along": 0.43},
	{"kind": "sconce", "room": "mouth", "wall": "e", "along": 0.75},
	{"kind": "fire", "room": "mouth", "at": Vector3(-3.6, 0.0, 3.0)},
	{"kind": "sconce", "room": "first_bend", "wall": "n", "along": 0.39},
	{"kind": "sconce", "room": "west_reach", "wall": "s", "along": 0.5},
	{"kind": "sconce", "room": "east_reach", "wall": "n", "along": 0.5},
	{"kind": "sconce", "room": "den", "wall": "w", "along": 0.67},
	{"kind": "sconce", "room": "den", "wall": "e", "along": 0.17},
	{"kind": "fire", "room": "den", "at": Vector3(1.5, 0.0, -36.0)},
	{"kind": "sconce", "room": "lair_south", "wall": "w", "along": 0.7},
	{"kind": "witch", "room": "gallery", "wall": "s", "along": 0.6},
	{"kind": "witch", "room": "gallery", "wall": "e", "along": 0.3},
	{"kind": "fungus", "room": "gallery_deep", "wall": "n", "along": 0.3},
	{"kind": "fungus", "room": "gallery", "wall": "n", "along": 0.85},
	{"kind": "witch", "room": "gallery_shaft", "wall": "w", "along": 0.5},
	{"kind": "witch", "room": "cistern", "wall": "s", "along": 0.7},
	{"kind": "fungus", "room": "cistern", "wall": "e", "along": 0.5},
	{"kind": "sconce", "room": "ossuary", "wall": "w", "along": 0.35},
	{"kind": "sconce", "room": "ossuary", "wall": "e", "along": 0.3},
	{"kind": "fungus", "room": "ossuary", "wall": "n", "along": 0.2},
	{"kind": "fungus", "room": "ossuary", "wall": "s", "along": 0.85},
	{"kind": "sconce", "room": "oss_east", "wall": "n", "along": 0.4},
	{"kind": "fungus", "room": "grove", "wall": "w", "along": 0.6},
	{"kind": "fungus", "room": "grove", "wall": "e", "along": 0.3},
	{"kind": "fungus", "room": "garden", "wall": "w", "along": 0.4},
	{"kind": "fungus", "room": "garden", "wall": "n", "along": 0.7},
	{"kind": "fungus", "room": "garden", "wall": "s", "along": 0.75},
	{"kind": "fungus", "room": "garden_glade", "wall": "e", "along": 0.15},
	{"kind": "sconce", "room": "garden_shaft", "wall": "e", "along": 0.5},
	{"kind": "sconce", "room": "mere_west", "wall": "n", "along": 0.5},
	{"kind": "brazier", "room": "mere", "at": Vector3(-15.0, 0.0, -139.0)},
	{"kind": "brazier", "room": "mere", "at": Vector3(13.0, 0.0, -139.0)},
	{"kind": "brazier", "room": "mere", "at": Vector3(13.0, 0.0, -157.5)},
	{"kind": "fungus", "room": "mere", "wall": "w", "along": 0.25},
	{"kind": "sconce", "room": "mere_shaft", "wall": "w", "along": 0.5},
	{"kind": "candles", "room": "shrine", "at": Vector3(-15.6, 1.0, -121.0)},
	{"kind": "sconce", "room": "chapel", "wall": "w", "along": 0.3},
	{"kind": "sconce", "room": "chapel", "wall": "e", "along": 0.1},
	{"kind": "sconce", "room": "chapel", "wall": "e", "along": 0.85},
	{"kind": "candles", "room": "apse", "at": Vector3(66.0, 1.0, -148.0)},
	{"kind": "sconce", "room": "chapel_west", "wall": "s", "along": 0.5},
	{"kind": "sconce", "room": "chapel_shaft", "wall": "w", "along": 0.5},
	{"kind": "sconce", "room": "crypt", "wall": "n", "along": 0.7},
	{"kind": "sconce", "room": "crypt", "wall": "s", "along": 0.75},
	{"kind": "sconce", "room": "rooted", "wall": "e", "along": 0.5},
	{"kind": "sconce", "room": "rooted", "wall": "w", "along": 0.75},
	{"kind": "fire", "room": "rooted", "at": Vector3(55.0, 0.0, -90.0)},
	{"kind": "lantern", "room": "workings", "wall": "w", "along": 0.3},
	{"kind": "lantern", "room": "workings", "wall": "n", "along": 0.75},
	{"kind": "lantern", "room": "workings", "wall": "e", "along": 0.85},
	{"kind": "lantern", "room": "workings_shaft", "wall": "n", "along": 0.5},
	{"kind": "lantern", "room": "upper", "wall": "s", "along": 0.75},
	{"kind": "lantern", "room": "upper", "wall": "w", "along": 0.5},
	{"kind": "brazier", "room": "lair", "at": Vector3(-12.0, 0.0, -78.0)},
	{"kind": "brazier", "room": "lair", "at": Vector3(13.0, 0.0, -99.0)},
	{"kind": "brazier", "room": "lair", "at": Vector3(-13.0, 0.0, -99.0)},
	{"kind": "brazier", "room": "lair", "at": Vector3(13.0, 0.0, -86.0)},
]

## The lights the floor is built from: `AUTHORED_LIGHTS` at `SCALE`.
static var LIGHTS: Array = _scaled_spots(AUTHORED_LIGHTS)

## What each area is read from. Kinds with a `collider` stop bodies and are on the
## squad's map; everything else is presentation that stands where nobody walks.
const AUTHORED_PROPS := [
	# The watchers' den.
	{"kind": "totem", "room": "den", "at": Vector3(-6.5, 0.0, -40.0), "height": 3.8},
	{"kind": "stakes", "room": "den", "at": Vector3(-6.5, 0.0, -26.5), "yaw": 0.4, "count": 4},
	{"kind": "bones", "room": "den", "at": Vector3(-8.0, 0.0, -33.0), "yaw": 0.8},
	{"kind": "bones", "room": "den", "at": Vector3(9.0, 0.0, -40.5), "yaw": 2.1},
	# The drowned gallery.
	{"kind": "pool", "room": "gallery", "at": Vector3(-55.0, 0.0, -17.0), "size": Vector2(5.5, 3.2)},
	{"kind": "pool", "room": "gallery_deep", "at": Vector3(-58.5, 0.0, -28.0), "size": Vector2(4.5, 2.4)},
	{"kind": "bones", "room": "gallery", "at": Vector3(-46.0, 0.0, -21.0), "yaw": 0.6},
	{"kind": "pool", "room": "cistern", "at": Vector3(-63.0, 0.0, -43.0), "size": Vector2(3.2, 2.2), "square": true},
	{"kind": "bones", "room": "cistern", "at": Vector3(-58.0, 0.0, -38.0), "yaw": 1.4},
	# The ossuary.
	{"kind": "bones", "room": "ossuary", "at": Vector3(-60.0, 0.0, -76.5), "yaw": -18.0},
	{"kind": "bones", "room": "ossuary", "at": Vector3(-46.5, 0.0, -88.0), "yaw": -8.0},
	{"kind": "bones", "room": "ossuary", "at": Vector3(-60.5, 0.0, -90.5), "yaw": -18.0},
	{"kind": "bones", "room": "ossuary", "at": Vector3(-53.0, 0.0, -98.5), "yaw": -16.0},
	{"kind": "bones", "room": "ossuary", "at": Vector3(-47.0, 0.0, -76.0), "yaw": -14.0},
	{"kind": "stakes", "room": "ossuary", "at": Vector3(-50.0, 0.0, -75.5), "yaw": 0.0, "count": 5},
	{"kind": "bones", "room": "niche_a", "at": Vector3(-63.6, 0.0, -94.0), "yaw": 1.6},
	{"kind": "bones", "room": "niche_b", "at": Vector3(-63.6, 0.0, -87.0), "yaw": 1.6},
	{"kind": "bones", "room": "niche_c", "at": Vector3(-63.6, 0.0, -80.0), "yaw": 1.6},
	# The pale garden.
	{"kind": "caps", "room": "grove", "at": Vector3(-70.0, 0.0, -117.0), "count": 5},
	{"kind": "caps", "room": "grove", "at": Vector3(-61.0, 0.0, -125.0), "count": 3},
	{"kind": "bones", "room": "grove", "at": Vector3(-66.0, 0.0, -126.0), "yaw": 0.4},
	{"kind": "caps", "room": "garden", "at": Vector3(-70.0, 0.0, -154.0), "count": 6},
	{"kind": "caps", "room": "garden", "at": Vector3(-57.0, 0.0, -141.5), "count": 4},
	{"kind": "caps", "room": "garden_glade", "at": Vector3(-45.5, 0.0, -151.5), "count": 4},
	{"kind": "column", "room": "garden", "at": Vector3(-61.0, 0.0, -150.0), "radius": 0.9},
	# The black mere.
	{"kind": "pool", "room": "mere", "at": Vector3(-1.0, 0.0, -148.0), "size": Vector2(11.0, 6.5)},
	{"kind": "column", "room": "mere", "at": Vector3(-7.0, 0.0, -147.0), "radius": 1.0},
	{"kind": "column", "room": "mere", "at": Vector3(6.0, 0.0, -150.0), "radius": 0.85},
	{"kind": "bones", "room": "mere", "at": Vector3(14.0, 0.0, -160.0), "yaw": 0.5},
	{"kind": "stakes", "room": "mere", "at": Vector3(10.0, 0.0, -136.5), "yaw": 0.0, "count": 4},
	{"kind": "rubble", "room": "mere", "at": Vector3(-16.5, 0.0, -158.5), "radius": 1.4},
	{"kind": "plinth", "room": "shrine", "at": Vector3(-15.6, 0.0, -121.0), "yaw": PI * 0.5},
	{"kind": "stakes", "room": "shrine", "at": Vector3(-8.0, 0.0, -126.5), "yaw": 0.0, "count": 3},
	{"kind": "bones", "room": "shrine", "at": Vector3(-4.0, 0.0, -125.0), "yaw": 1.0},
	# The bone chapel.
	{"kind": "stakes", "room": "chapel", "at": Vector3(49.0, 0.0, -150.0), "yaw": PI * 0.5, "count": 6},
	{"kind": "stakes", "room": "chapel", "at": Vector3(57.0, 0.0, -150.0), "yaw": PI * 0.5, "count": 6},
	{"kind": "bones", "room": "chapel", "at": Vector3(46.0, 0.0, -158.0), "yaw": 0.3},
	{"kind": "bones", "room": "chapel", "at": Vector3(60.5, 0.0, -138.0), "yaw": 1.2},
	{"kind": "plinth", "room": "apse", "at": Vector3(66.0, 0.0, -148.0), "yaw": PI * 0.5},
	{"kind": "coffin", "room": "crypt", "at": Vector3(71.5, 0.0, -125.0), "yaw": 0.0},
	{"kind": "coffin", "room": "crypt", "at": Vector3(71.5, 0.0, -121.5), "yaw": 0.0},
	{"kind": "coffin", "room": "crypt", "at": Vector3(71.5, 0.0, -118.0), "yaw": 0.0},
	{"kind": "bones", "room": "crypt", "at": Vector3(60.0, 0.0, -116.0), "yaw": 0.7},
	# The rooted hall.
	{"kind": "roots", "room": "rooted", "at": Vector3(54.0, 0.0, -88.0), "size": Vector2(8.0, 10.0)},
	{"kind": "rootpost", "room": "rooted", "at": Vector3(49.5, 0.0, -82.0)},
	{"kind": "rootpost", "room": "rooted", "at": Vector3(60.5, 0.0, -90.0)},
	{"kind": "bones", "room": "rooted", "at": Vector3(61.0, 0.0, -79.0), "yaw": 1.0},
	# The old workings.
	{"kind": "post", "room": "workings", "wall": "w", "along": 0.2},
	{"kind": "post", "room": "workings", "wall": "w", "along": 0.55},
	{"kind": "post", "room": "workings", "wall": "e", "along": 0.15},
	{"kind": "post", "room": "workings", "wall": "e", "along": 0.6},
	{"kind": "cart", "room": "workings", "at": Vector3(49.0, 0.0, -3.0), "yaw": 0.4},
	{"kind": "rubble", "room": "workings", "at": Vector3(57.5, 0.0, -12.5), "radius": 1.5},
	{"kind": "bones", "room": "workings", "at": Vector3(43.0, 0.0, 1.0), "yaw": 0.2},
	{"kind": "frame", "room": "east_reach", "at": Vector3(23.0, 0.0, 6.0), "yaw": PI * 0.5},
	{"kind": "frame", "room": "east_reach", "at": Vector3(29.0, 0.0, 6.0), "yaw": PI * 0.5},
	{"kind": "frame", "room": "east_reach", "at": Vector3(35.0, 0.0, 6.0), "yaw": PI * 0.5},
	{"kind": "frame", "room": "workings_north", "at": Vector3(46.0, 0.0, -18.0), "yaw": 0.0},
	{"kind": "frame", "room": "upper_way", "at": Vector3(52.0, 0.0, -27.0), "yaw": 0.0},
	{"kind": "frame", "room": "upper_way", "at": Vector3(52.0, 0.0, -33.0), "yaw": 0.0},
	{"kind": "frame", "room": "rooted_drop", "at": Vector3(64.0, 0.0, -55.0), "yaw": 0.0},
	{"kind": "post", "room": "upper", "wall": "n", "along": 0.35},
	{"kind": "post", "room": "upper", "wall": "s", "along": 0.4},
	{"kind": "rubble", "room": "upper", "at": Vector3(51.0, 0.0, -47.0), "radius": 1.3},
	{"kind": "cart", "room": "upper", "at": Vector3(60.0, 0.0, -39.0), "yaw": 1.2},
	# Gorehorn's lair.
	{"kind": "altar", "room": "lair", "at": Vector3(0.0, 0.0, -95.0)},
	{"kind": "blood", "room": "lair", "at": Vector3(0.0, 0.0, -89.0), "radius": 3.2},
	{"kind": "stakes", "room": "lair", "at": Vector3(-7.0, 0.0, -83.0), "yaw": 1.1, "count": 5},
	{"kind": "stakes", "room": "lair", "at": Vector3(7.0, 0.0, -83.0), "yaw": -1.1, "count": 5},
	{"kind": "bones", "room": "lair", "at": Vector3(-14.0, 0.0, -81.0), "yaw": -16.0},
	{"kind": "bones", "room": "lair", "at": Vector3(14.0, 0.0, -93.0), "yaw": -18.0},
	{"kind": "bones", "room": "lair", "at": Vector3(-8.0, 0.0, -101.0), "yaw": -20.0},
	{"kind": "bones", "room": "lair", "at": Vector3(9.0, 0.0, -76.5), "yaw": -15.0},
	{"kind": "column", "room": "lair", "at": Vector3(-10.0, 0.0, -86.0), "radius": 1.1},
	{"kind": "column", "room": "lair", "at": Vector3(10.0, 0.0, -97.0), "radius": 1.1},
]

## The props the floor is built from: `AUTHORED_PROPS` at `SCALE`.
static var PROPS: Array = _scaled_spots(AUTHORED_PROPS)

## The rock's height and the box it is cut out of, at `SCALE`.
static var TOP: float = AUTHORED_TOP * SCALE
static var BOUNDS: Rect2 = _flat_rect(AUTHORED_BOUNDS)


# --- the scale ------------------------------------------------------------------

## A plan point on the floor the plan is built at: `SCALE` times as far from the
## origin. Its height is left alone - what a spot's height means is the plinth a
## candle stands on or the footing of a prop, and that is authored at the size of a
## body, not of the floor.
static func _flat(at: Vector3) -> Vector3:
	return Vector3(at.x * SCALE, at.y, at.z * SCALE)


static func _flat_rect(rect: Rect2) -> Rect2:
	return Rect2(rect.position * SCALE, rect.size * SCALE)


## `AUTHORED_ROOMS` at `SCALE`: the footprint moved and grown, the ceiling with it,
## so a room keeps its shape.
static func _scaled_rooms(source: Array) -> Array:
	var out: Array = []
	for row in source:
		var room: Dictionary = row.duplicate()
		room["rect"] = _flat_rect(row["rect"])
		room["height"] = float(row["height"]) * SCALE
		out.append(room)
	return out


## `AUTHORED_LANDINGS` at `SCALE`: the rope and the ring in front of it.
static func _scaled_landings(source: Array) -> Array:
	var out: Array = []
	for row in source:
		var landing: Dictionary = row.duplicate()
		landing["rope"] = _flat(row["rope"])
		landing["centre"] = _flat(row["centre"])
		out.append(landing)
	return out


## `AUTHORED_DENS` at `SCALE`: every post, and the door its body faces, moved out
## with its room.
static func _scaled_dens(source: Array) -> Array:
	var out: Array = []
	for row in source:
		var den: Dictionary = row.duplicate()
		var members: Array = []
		for member in row["members"]:
			members.append({"species": member["species"], "at": _flat(member["at"]),
				"face": _flat(member["face"])})
		den["members"] = members
		out.append(den)
	return out


## `AUTHORED_LIGHTS` / `AUTHORED_PROPS` at `SCALE`: where a piece stands, the ground
## it covers (`size`, `radius`) and the height the plan gives it (the den's totem).
## A wall mount is a fraction of the way along its wall, and a count is a number of
## pieces: neither moves with the floor.
static func _scaled_spots(source: Array) -> Array:
	var out: Array = []
	for row in source:
		var spot: Dictionary = row.duplicate()
		if spot.has("at"):
			spot["at"] = _flat(row["at"])
		if spot.has("size"):
			spot["size"] = (row["size"] as Vector2) * SCALE
		if spot.has("radius"):
			spot["radius"] = float(row["radius"]) * SCALE
		if spot.has("height"):
			spot["height"] = float(row["height"]) * SCALE
		out.append(spot)
	return out


static var _raster := PackedInt32Array()
static var _cols := 0
static var _rows := 0
static var _doors: Array = []
static var _room_doors: Array = []
## `den id -> den_members()`, built on first ask.
static var _crowds: Dictionary = {}


# --- the plan ------------------------------------------------------------------

## The room's index in `ROOMS`, or -1.
static func room_index(room_id: String) -> int:
	for index in ROOMS.size():
		if str(ROOMS[index]["id"]) == room_id:
			return index
	return -1


static func room(room_id: String) -> Dictionary:
	var index := room_index(room_id)
	return ROOMS[index] if index >= 0 else {}


static func landing(landing_id: String) -> Dictionary:
	for entry in LANDINGS:
		if str(entry["id"]) == landing_id:
			return entry
	return {}


static func landing_ids() -> Array[String]:
	var out: Array[String] = []
	for entry in LANDINGS:
		out.append(str(entry["id"]))
	return out


static func area_name(area_id: String) -> String:
	return str(AREAS.get(area_id, ""))


## Every post a den fields, `{species, at, face}`: its authored `members` first,
## then the crowd (`DEN_CROWD`). Pure and cached, so the cave, the dressing that
## keeps the posts clear and a co-op guest's copy all stand the same bodies on the
## same spots.
static func den_members(den: Dictionary) -> Array:
	var den_id := str(den["id"])
	if _crowds.has(den_id):
		return _crowds[den_id]
	var authored: Array = den["members"]
	var out: Array = authored.duplicate()
	var index := room_index(str(den["room"]))
	_crowds[den_id] = out
	if index < 0 or authored.is_empty():
		return out
	var inner := (ROOMS[index]["rect"] as Rect2).grow(-CROWD_WALL)
	var keep_out := _crowd_keep_out(index)
	var spots: Array[Vector2] = []
	var z := inner.position.y
	while z <= inner.end.y + 0.001:
		var x := inner.position.x
		while x <= inner.end.x + 0.001:
			var spot := Vector2(x, z)
			var open := true
			for entry in keep_out:
				if spot.distance_to(entry[0]) < float(entry[1]):
					open = false
					break
			if open:
				spots.append(spot)
			x += CROWD_STEP
		z += CROWD_STEP
	# Each spot's distance to the nearest body placed so far, narrowed as the
	# crowd grows, so every pick is one pass over the spots.
	var gaps := PackedFloat32Array()
	gaps.resize(spots.size())
	gaps.fill(INF)
	for row in authored:
		_narrow(gaps, spots, row["at"])
	var want := authored.size() * DEN_CROWD
	while out.size() < want:
		var best := -1
		for spot_index in spots.size():
			if best < 0 or gaps[spot_index] > gaps[best]:
				best = spot_index
		if best < 0 or gaps[best] < CROWD_SPACING:
			break
		var source: Dictionary = authored[(out.size() - authored.size()) % authored.size()]
		var at := Vector3(spots[best].x, 0.0, spots[best].y)
		out.append({"species": source["species"], "at": at, "face": source["face"]})
		_narrow(gaps, spots, at)
	return out


static func _narrow(gaps: PackedFloat32Array, spots: Array[Vector2], at: Vector3) -> void:
	var flat := Vector2(at.x, at.z)
	for index in spots.size():
		gaps[index] = minf(gaps[index], spots[index].distance_to(flat))


## `[point, radius]` pairs (cave x/z) no crowd body may stand inside in one room:
## its doors, and every light and prop on its floor.
static func _crowd_keep_out(index: int) -> Array:
	var out: Array = []
	var list := doors()
	for door_index in doors_of(index):
		out.append([list[door_index]["mid"], CROWD_DOOR])
	var room_id := str(ROOMS[index]["id"])
	for spec in LIGHTS + PROPS:
		if str(spec["room"]) != room_id or OVERHEAD_PROPS.has(str(spec["kind"])):
			continue
		var at: Vector3 = wall_point(room_id, str(spec["wall"]), float(spec["along"]))["at"] \
			if spec.has("wall") else spec["at"]
		var size: Vector2 = spec.get("size", Vector2.ZERO)
		out.append([Vector2(at.x, at.z), CROWD_CLEAR + float(spec.get("radius", 0.0)) + size.length() * 0.5])
	return out


## A point on one of a room's walls and the way into the room from it: `side` is
## `n` (the deep edge, -Z), `s`, `w` (-X) or `e`; `along` runs from the edge's low
## corner. The point sits 5 cm proud of the rock.
static func wall_point(room_id: String, side: String, along: float) -> Dictionary:
	var rect: Rect2 = room(room_id).get("rect", Rect2())
	match side:
		"n":
			return {"at": Vector3(rect.position.x + rect.size.x * along, 0.0, rect.position.y + 0.05),
				"inward": Vector3(0.0, 0.0, 1.0)}
		"s":
			return {"at": Vector3(rect.position.x + rect.size.x * along, 0.0, rect.end.y - 0.05),
				"inward": Vector3(0.0, 0.0, -1.0)}
		"w":
			return {"at": Vector3(rect.position.x + 0.05, 0.0, rect.position.y + rect.size.y * along),
				"inward": Vector3(1.0, 0.0, 0.0)}
	return {"at": Vector3(rect.end.x - 0.05, 0.0, rect.position.y + rect.size.y * along),
		"inward": Vector3(-1.0, 0.0, 0.0)}


## `count` different shafts for `count` parties, as far apart as the floor allows:
## the first is drawn from `seed_value`, and every next one is the shaft whose
## nearest already-taken shaft is furthest away. Never more than there are shafts.
static func landings_for(count: int, seed_value: int) -> Array[String]:
	var out: Array[String] = []
	if count <= 0 or LANDINGS.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	out.append(str(LANDINGS[rng.randi() % LANDINGS.size()]["id"]))
	while out.size() < mini(count, LANDINGS.size()):
		var pick := ""
		var widest := -1.0
		for entry in LANDINGS:
			if out.has(str(entry["id"])):
				continue
			var gap := INF
			for taken in out:
				gap = minf(gap, (entry["centre"] as Vector3).distance_to(landing(taken)["centre"]))
			if gap > widest:
				widest = gap
				pick = str(entry["id"])
		out.append(pick)
	return out


# --- the raster ------------------------------------------------------------------

## Every half-metre cell of `BOUNDS`, row by row: the index of the room whose floor
## it is, or -1 for rock. Built once from `ROOMS`; every room's edges sit on the
## grid, so a cell is wholly floor or wholly rock.
static func raster() -> PackedInt32Array:
	if not _raster.is_empty():
		return _raster
	_cols = int(ceil(BOUNDS.size.x / CELL))
	_rows = int(ceil(BOUNDS.size.y / CELL))
	_raster.resize(_cols * _rows)
	_raster.fill(-1)
	for index in ROOMS.size():
		var cells := _cells_of(ROOMS[index]["rect"])
		for z in range(cells.position.y, cells.end.y):
			for x in range(cells.position.x, cells.end.x):
				_raster[z * _cols + x] = index
	return _raster


static func columns() -> int:
	raster()
	return _cols


static func rows() -> int:
	raster()
	return _rows


## A room's rectangle in cells, clipped to the raster.
static func _cells_of(rect: Rect2) -> Rect2i:
	var x0 := clampi(int(round((rect.position.x - BOUNDS.position.x) / CELL)), 0, _cols)
	var z0 := clampi(int(round((rect.position.y - BOUNDS.position.y) / CELL)), 0, _rows)
	var x1 := clampi(int(round((rect.end.x - BOUNDS.position.x) / CELL)), 0, _cols)
	var z1 := clampi(int(round((rect.end.y - BOUNDS.position.y) / CELL)), 0, _rows)
	return Rect2i(x0, z0, x1 - x0, z1 - z0)


## A room's rectangle in raster cells.
static func cells_of(rect: Rect2) -> Rect2i:
	raster()
	return _cells_of(rect)


## The room whose floor a raster cell is, or -1 for rock (off the raster is rock).
static func cell_room(x: int, z: int) -> int:
	var grid := raster()
	if x < 0 or z < 0 or x >= _cols or z >= _rows:
		return -1
	return grid[z * _cols + x]


## A raster lattice point - a cell's corner - in the cave's frame (x/z).
static func lattice(x: int, z: int) -> Vector2:
	return Vector2(BOUNDS.position.x + float(x) * CELL, BOUNDS.position.y + float(z) * CELL)


## The index of the room whose floor a cave-local x/z point is on, or -1.
static func room_index_at(point: Vector2) -> int:
	var grid := raster()
	var x := floori((point.x - BOUNDS.position.x) / CELL)
	var z := floori((point.y - BOUNDS.position.y) / CELL)
	if x < 0 or z < 0 or x >= _cols or z >= _rows:
		return -1
	return grid[z * _cols + x]


## Whether a cave-local x/z point is on some room's floor.
static func is_floor(point: Vector2) -> bool:
	return room_index_at(point) >= 0


## The area a cave-local x/z point is in, or "" in the rock.
static func area_at(point: Vector2) -> String:
	var index := room_index_at(point)
	return str(ROOMS[index]["area"]) if index >= 0 else ""


## The rock as rectangles for the colliders: every cell of `BOUNDS` that is not
## floor, merged greedily into the widest, then tallest, run.
static func rock_rects() -> Array[Rect2]:
	var grid := raster()
	var out: Array[Rect2] = []
	var used := PackedByteArray()
	used.resize(_cols * _rows)
	used.fill(0)
	for z in _rows:
		var x := 0
		while x < _cols:
			var index := z * _cols + x
			if grid[index] >= 0 or used[index] != 0:
				x += 1
				continue
			var width := 1
			while x + width < _cols and grid[index + width] < 0 and used[index + width] == 0:
				width += 1
			var depth := 1
			while z + depth < _rows:
				var whole := true
				var row := (z + depth) * _cols + x
				for step in width:
					if grid[row + step] >= 0 or used[row + step] != 0:
						whole = false
						break
				if not whole:
					break
				depth += 1
			for dz in depth:
				var row := (z + dz) * _cols + x
				for dx in width:
					used[row + dx] = 1
			out.append(_cell_rect(x, z, width, depth))
			x += width
	return out


## The rock each room's own shell draws, by room index: every rock cell within
## `WALL_CELLS` of a floor goes to the room it is nearest to (ties to the earlier
## room), merged greedily per room. No cell is drawn twice, so two rooms' walls
## never fight over one face.
static func wall_rects() -> Array:
	var grid := raster()
	var owner := PackedInt32Array()
	owner.resize(_cols * _rows)
	owner.fill(-1)
	var nearest := PackedByteArray()
	nearest.resize(_cols * _rows)
	nearest.fill(255)
	for index in ROOMS.size():
		var cells := _cells_of(ROOMS[index]["rect"])
		var z_from := maxi(cells.position.y - WALL_CELLS, 0)
		var z_to := mini(cells.end.y + WALL_CELLS, _rows)
		var x_from := maxi(cells.position.x - WALL_CELLS, 0)
		var x_to := mini(cells.end.x + WALL_CELLS, _cols)
		for z in range(z_from, z_to):
			var dz := 0
			if z < cells.position.y:
				dz = cells.position.y - z
			elif z >= cells.end.y:
				dz = z - cells.end.y + 1
			for x in range(x_from, x_to):
				var cell := z * _cols + x
				if grid[cell] >= 0:
					continue
				var dx := 0
				if x < cells.position.x:
					dx = cells.position.x - x
				elif x >= cells.end.x:
					dx = x - cells.end.x + 1
				var reach := maxi(dx, dz)
				if reach < nearest[cell]:
					nearest[cell] = reach
					owner[cell] = index
	var out: Array = []
	for _index in ROOMS.size():
		var walls: Array[Rect2] = []
		out.append(walls)
	var used := PackedByteArray()
	used.resize(_cols * _rows)
	used.fill(0)
	for z in _rows:
		var x := 0
		while x < _cols:
			var cell := z * _cols + x
			var label := owner[cell]
			if label < 0 or used[cell] != 0:
				x += 1
				continue
			var width := 1
			while x + width < _cols and owner[cell + width] == label and used[cell + width] == 0:
				width += 1
			var depth := 1
			while z + depth < _rows:
				var whole := true
				var row := (z + depth) * _cols + x
				for step in width:
					if owner[row + step] != label or used[row + step] != 0:
						whole = false
						break
				if not whole:
					break
				depth += 1
			for dz in depth:
				var row := (z + dz) * _cols + x
				for dx in width:
					used[row + dx] = 1
			(out[label] as Array).append(_cell_rect(x, z, width, depth))
			x += width
	return out


static func _cell_rect(x: int, z: int, width: int, depth: int) -> Rect2:
	return Rect2(BOUNDS.position.x + float(x) * CELL, BOUNDS.position.y + float(z) * CELL,
		float(width) * CELL, float(depth) * CELL)


# --- the ways between rooms ------------------------------------------------------

## One entry per pair of rooms that share an edge: `{a, b, mid, width}`, `mid` the
## middle of the opening (cave-local x/z) and `width` its length in metres.
static func doors() -> Array:
	if not _doors.is_empty():
		return _doors
	_room_doors.clear()
	for _index in ROOMS.size():
		_room_doors.append([])
	for a in ROOMS.size():
		for b in range(a + 1, ROOMS.size()):
			var opening := _opening(ROOMS[a]["rect"], ROOMS[b]["rect"])
			if opening.is_empty():
				continue
			opening["a"] = a
			opening["b"] = b
			(_room_doors[a] as Array).append(_doors.size())
			(_room_doors[b] as Array).append(_doors.size())
			_doors.append(opening)
	return _doors


## The doors of one room, as indices into `doors()`.
static func doors_of(index: int) -> Array:
	doors()
	return _room_doors[index] if index >= 0 and index < _room_doors.size() else []


## The shared stretch of two rectangles' edges, or {} when they only meet at a
## corner or not at all.
static func _opening(first: Rect2, second: Rect2) -> Dictionary:
	if is_equal_approx(first.end.x, second.position.x) or is_equal_approx(second.end.x, first.position.x):
		var x := first.end.x if is_equal_approx(first.end.x, second.position.x) else first.position.x
		var low := maxf(first.position.y, second.position.y)
		var high := minf(first.end.y, second.end.y)
		if high - low > 0.01:
			return {"mid": Vector2(x, (low + high) * 0.5), "width": high - low}
	if is_equal_approx(first.end.y, second.position.y) or is_equal_approx(second.end.y, first.position.y):
		var z := first.end.y if is_equal_approx(first.end.y, second.position.y) else first.position.y
		var low := maxf(first.position.x, second.position.x)
		var high := minf(first.end.x, second.end.x)
		if high - low > 0.01:
			return {"mid": Vector2((low + high) * 0.5, z), "width": high - low}
	return {}


## How far a body walks between two cave-local x/z points: straight across a room
## (every room is a convex rectangle) and door to door between rooms. INF when
## either point is in the rock.
static func walk_metres(from: Vector2, to: Vector2) -> float:
	var start := room_index_at(from)
	var goal := room_index_at(to)
	if start < 0 or goal < 0:
		return INF
	if start == goal:
		return from.distance_to(to)
	var reached := door_metres(from)
	var best := INF
	for door_index in doors_of(goal):
		best = minf(best, reached[door_index] + (_doors[door_index]["mid"] as Vector2).distance_to(to))
	return best


## The walk from a cave-local x/z point to every door of the floor (INF for any
## the point cannot reach): Dijkstra over the doors, each room crossed in a line.
static func door_metres(from: Vector2) -> PackedFloat32Array:
	var list := doors()
	var metres := PackedFloat32Array()
	metres.resize(list.size())
	metres.fill(INF)
	var start := room_index_at(from)
	if start < 0:
		return metres
	var settled := PackedByteArray()
	settled.resize(list.size())
	settled.fill(0)
	for door_index in doors_of(start):
		metres[door_index] = from.distance_to(list[door_index]["mid"])
	while true:
		var pick := -1
		for door_index in list.size():
			if settled[door_index] == 0 and is_finite(metres[door_index]) \
					and (pick < 0 or metres[door_index] < metres[pick]):
				pick = door_index
		if pick < 0:
			break
		settled[pick] = 1
		var here: Vector2 = list[pick]["mid"]
		for side in [int(list[pick]["a"]), int(list[pick]["b"])]:
			for next in doors_of(side):
				if settled[next] != 0:
					continue
				var through := metres[pick] + here.distance_to(list[next]["mid"])
				if through < metres[next]:
					metres[next] = through
	return metres


## The rope a body at a cave-local x/z point reaches by the shortest walk:
## `{id, area, metres}`, or {} from inside the rock.
static func nearest_landing(from: Vector2) -> Dictionary:
	var start := room_index_at(from)
	if start < 0:
		return {}
	var reached := door_metres(from)
	var best := {}
	for entry in LANDINGS:
		var rope: Vector3 = entry["rope"]
		var at := Vector2(rope.x, rope.z)
		var goal := room_index(str(entry["room"]))
		var walk := INF
		if goal == start:
			walk = from.distance_to(at)
		else:
			for door_index in doors_of(goal):
				walk = minf(walk, reached[door_index] + (_doors[door_index]["mid"] as Vector2).distance_to(at))
		if is_finite(walk) and (best.is_empty() or walk < float(best["metres"])):
			best = {"id": str(entry["id"]), "area": str(entry["area"]), "metres": walk}
	return best
