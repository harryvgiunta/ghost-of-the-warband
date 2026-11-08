class_name SignKit
extends RefCounted
## The world's signage: boards, plates and tablets whose words are in the surface.
##
## A sign is one baked face - `assets/world/textures/sign_<id>.png` and its `_n`,
## authored by `tools/world_textures.py` - laid on carved stone or painted timber.
## Nothing here draws text at run time. The words are paint on a board or a cut in
## a plate, so they take the world's light, weather with it and sit in a frame
## instead of hanging in the air as a label would.
##
## `SIGNS` mirrors `SIGN_SPECS` in that tool: same id, same words, same face size
## in metres at 320 px/m. `tests/warband_art_regression.gd` checks every baked face
## against this table, so a board that has been resized is a red test and never
## stretched paint.

const TextureLibrary = preload("res://scripts/world/texture_library.gd")
const VillageKit = preload("res://scripts/world/village_kit.gd")
const Geo = preload("res://scripts/geo.gd")

## One row per sign: the words it carries and the size of the painted or carved
## face in metres. `cut` is how the words are in it - "plank" paint on oak,
## "stone" letters chiselled into dark stone.
const SIGNS := {
	"wood_road": {"text": "THE WOOD ROAD", "size": Vector2(2.40, 0.55), "cut": "plank"},
	"square": {"text": "THE SQUARE", "size": Vector2(2.30, 1.00), "cut": "plank"},
	"altar_board": {"text": "THE ALTAR", "size": Vector2(1.50, 0.25), "cut": "plank"},
	"keepers": {"text": "THE KEEPERS", "size": Vector2(1.50, 0.25), "cut": "plank"},
	"delve": {"text": "THE DELVE", "size": Vector2(1.50, 0.25), "cut": "plank"},
	"weeping_hollow": {"text": "THE WEEPING HOLLOW", "size": Vector2(2.20, 0.45),
		"cut": "plank"},
	"way_up": {"text": "THE WAY UP", "size": Vector2(1.10, 0.35), "cut": "stone"},
	"town": {"text": "TOWN", "size": Vector2(1.30, 0.50), "cut": "plank"},
	"arena": {"text": "THE ARENA", "size": Vector2(2.60, 0.50), "cut": "stone"},
	"altar": {"text": "THE ALTAR", "size": Vector2(0.60, 0.30), "cut": "stone"},
}

## Pixels per metre the faces are baked at, exactly as `SIGN_PPM` in
## `tools/world_textures.py`. The art regression compares every baked file against
## this, so the tool's scale and the game's cannot drift apart.
const PIXELS_PER_METRE := 320.0

## The face sits this far proud of the board behind it: enough that the plate's own
## chamfer catches a highlight instead of z-fighting the timber.
const FACE_LIFT := 0.004
## The board a plank sign is painted on, and the plate a stone sign is cut into.
const BOARD_THICKNESS := 0.05
const PLATE_THICKNESS := 0.07
## A free-standing tablet is set into the ground this far, and leaned back by this
## much, because a slab stood dead upright on a cave floor reads as a fence post.
const TABLET_BURY := 0.05
const TABLET_TILT := -0.12

static var _mats: Dictionary = {}
static var _faces: Dictionary = {}


## One sign's row, or a loud error and a usable stand-in: a missing sign must be
## visible as a plain board with a wrong-sized face, never as a silent no-op.
static func spec_of(id: String) -> Dictionary:
	var spec: Dictionary = SIGNS.get(id, {})
	if spec.is_empty():
		push_error("SignKit: no such sign '%s' in SIGNS." % id)
		return {"text": id, "size": Vector2(1.0, 0.30), "cut": "plank"}
	return spec


static func size_of(id: String) -> Vector2:
	return spec_of(id)["size"]


static func text_of(id: String) -> String:
	return String(spec_of(id)["text"])


## The palette a sign is made of, cached once: the village's own timber, the
## wardens' ochre, the altar's dark wet stone and their iron.
static func materials() -> Dictionary:
	if not _mats.is_empty():
		return _mats
	var m: Dictionary = {}
	m["plank"] = TextureLibrary.building_material("wood", Color("9a8a6e"))
	m["ochre"] = Geo.material(Color("5e2418"), 0.05, 0.9)
	m["stone"] = TextureLibrary.granite_material(Color("5d5450"))
	m["stone_dark"] = TextureLibrary.granite_material(Color("433b38"))
	m["iron"] = Geo.material(Color("3b3937"), 0.72, 0.48)
	_mats = m
	return m


## The face itself: one quad at the sign's own aspect, so the baked letters land
## on it undistorted. Cached per size, because two signs of one size share a mesh.
static func face_mesh(id: String) -> QuadMesh:
	var size := size_of(id)
	var key := "%.3f,%.3f" % [size.x, size.y]
	var cached: QuadMesh = _faces.get(key)
	if cached != null:
		return cached
	var mesh := QuadMesh.new()
	mesh.size = size
	_faces[key] = mesh
	return mesh


## Merge a sign's face into a kit mesh: the board's body and its paint become one
## node with one surface per material, which is how every other prop in the world
## is built. `at` is the face's centre in the merged mesh's frame; the face looks
## along +Z unless `yaw` turns it.
static func add_face(m: VillageKit.Merged, id: String, at: Vector3,
		yaw: float = 0.0) -> void:
	m.add(face_mesh(id), Transform3D(Basis(Vector3.UP, yaw), at),
		TextureLibrary.sign_material(id))


## A face as its own instance, for a board whose body is already standing.
static func face_node(parent: Node3D, id: String, at: Vector3,
		yaw: float = 0.0) -> MeshInstance3D:
	var face := MeshInstance3D.new()
	face.name = "SignFace"
	face.mesh = face_mesh(id)
	face.material_override = TextureLibrary.sign_material(id)
	face.position = at
	face.rotation.y = yaw
	parent.add_child(face)
	return face


## A plank board: the words painted on timber with an ochre rule top and bottom,
## the fingerpost's style at any size. Painted on both faces by default - a board
## hung over a gate is read coming in and going out - with the edges of the board
## showing between them. The caller hangs it, posts it or lashes it, because only
## the caller knows what carries it.
static func plank_board(host: Node3D, id: String, at: Vector3, yaw: float = 0.0,
		label: String = "SignBoard", two_sided: bool = true) -> Node3D:
	var size := size_of(id)
	var mats := materials()
	var node := _node(host, label, at, yaw)
	var m := VillageKit.Merged.new()
	var board := size + Vector2(0.12, 0.16)
	VillageKit.add_box(m, Vector3(board.x, board.y, BOARD_THICKNESS),
		Vector3(0.0, 0.0, -BOARD_THICKNESS * 0.5 - FACE_LIFT), mats["plank"])
	for edge in [-1.0, 1.0]:
		VillageKit.add_box(m, Vector3(board.x + 0.05, 0.045, BOARD_THICKNESS + 0.03),
			Vector3(0.0, edge * board.y * 0.5, -0.02), mats["ochre"])
	add_face(m, id, Vector3.ZERO)
	if two_sided:
		add_face(m, id, Vector3(0.0, 0.0, -BOARD_THICKNESS - 2.0 * FACE_LIFT), PI)
	m.commit(node, "Board")
	return node


## A stone plate with the words cut into it: set on a stone lintel, a stele or a
## wall, sunk into whatever it is mounted on.
static func plaque(host: Node3D, id: String, at: Vector3, yaw: float = 0.0,
		label: String = "SignPlaque") -> Node3D:
	var size := size_of(id)
	var mats := materials()
	var node := _node(host, label, at, yaw)
	var m := VillageKit.Merged.new()
	var plate := size + Vector2(0.16, 0.16)
	VillageKit.add_box(m, Vector3(plate.x, plate.y, PLATE_THICKNESS),
		Vector3(0.0, 0.0, -PLATE_THICKNESS * 0.5 - FACE_LIFT), mats["stone"])
	add_face(m, id, Vector3.ZERO)
	m.commit(node, "Plate")
	return node


## A free-standing marker: a cut stone set into a footing on the ground, so a
## waymark can stand where there is no wall to carry it.
static func tablet(host: Node3D, id: String, at: Vector3, yaw: float = 0.0,
		label: String = "SignTablet") -> Node3D:
	var size := size_of(id)
	var mats := materials()
	var node := _node(host, label, at, yaw)
	var m := VillageKit.Merged.new()
	var board := size + Vector2(0.16, 0.20)
	var lift := size.y * 0.5 + 0.05
	var previous := m.push(Transform3D(Basis(Vector3.RIGHT, TABLET_TILT),
		Vector3(0.0, lift - TABLET_BURY, 0.0)))
	VillageKit.add_box(m, Vector3(board.x, board.y, 0.10),
		Vector3(0.0, 0.0, -0.055 - FACE_LIFT), mats["stone"])
	add_face(m, id, Vector3.ZERO)
	m.group = previous
	# The footing it is packed into, and the stones that keep it there.
	VillageKit.add_box(m, Vector3(board.x + 0.10, 0.18, 0.34),
		Vector3(0.0, 0.07, -0.03), mats["stone_dark"], 0.0, 0.0, 0.02)
	VillageKit.add_box(m, Vector3(0.20, 0.14, 0.22),
		Vector3(-board.x * 0.5, 0.05, 0.04), mats["stone_dark"], 0.4, 0.0, 0.10)
	VillageKit.add_box(m, Vector3(0.17, 0.12, 0.20),
		Vector3(board.x * 0.5, 0.04, 0.05), mats["stone_dark"], -0.3, 0.0, -0.12)
	m.commit(node, "Tablet")
	return node


## The two forged eyes a hung board hangs from: an iron pin through the frame over
## it and the hanger that reaches down to the board's top rule. `offsets` are metres
## either side of the board's centre, clamped inside its own frame.
static func hangers(host: Node3D, id: String, from_y: float, to_y: float,
		offsets: Array = [-0.7, 0.7], z: float = 0.0) -> void:
	var mats := materials()
	var half := maxf(0.0, size_of(id).x * 0.5 - 0.16)
	for offset in offsets:
		var at := clampf(float(offset), -half, half)
		Geo.beam(host, Vector3(at, from_y, z), Vector3(at, to_y, z), 0.016,
			mats["iron"], 5)
		Geo.sphere(host, 0.035, Vector3(at, from_y, z), mats["iron"],
			Vector3(1.0, 0.6, 1.0))


static func _node(host: Node3D, label: String, at: Vector3, yaw: float) -> Node3D:
	var node := Node3D.new()
	node.name = label
	node.position = at
	node.rotation.y = yaw
	host.add_child(node)
	return node
