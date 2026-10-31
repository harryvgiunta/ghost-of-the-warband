class_name SoldierCages
extends Node3D
## Four of the warband's own, shut in iron cages along the way to town.
##
## The quartermaster's first order points at cages in the wood, and until now
## there were none past the camp: the opening's four latches are the lesson, and
## the road beyond them belonged to the cult. This node is the rest of that line -
## four soldiers the wardens took on the road, caged at four stretches of the
## walk and left there, one per quarter of the lane.
##
## A cage is the camp's own furniture (`camp_clearing.gd::_build_cage`): a slab,
## four corner posts, bars on three sides and a door of bars on the fourth. The
## bars are a wall - three static boxes and the door's own - so the cage is a real
## obstacle a body has to walk round, and the door's collider rises with the bars
## it is drawn on. What is new is what is inside it and what happens when the
## latch goes: the soldier walks out through the lifted door, the warband takes
## his name (`host.note_soldier_freed`, the one call that adds a roster record),
## and the figure fades - over his own warband body standing up in the same spot
## while the field has a place, or over nothing when it is full and he waits in
## the town's reserve.
##
## The two rules the world measures this against are the lane's clearance - the
## wood is walked on a 1.55 m half-band and a post on the centre line stops a body
## dead, so every cage stands 6-9 m out and its nearest post is more than 6 m from
## the worn line - and the reach of a latch: a press is a cut made from the dirt
## at the bars, and bare hands do not cut iron.
##
## The cage owns no input. `interact()` is the world's `G`, exposed for whoever
## takes it (the camp's own latch rule is on the same key and the same press).

const TerrainScript = preload("res://scripts/warband/terrain.gd")
const CampKit = preload("res://scripts/world/camp_kit.gd")
const CampDressing = preload("res://scripts/warband/camp_dressing.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const State = preload("res://scripts/player_state.gd")
const WarbandLooks = preload("res://scripts/warband/warband_looks.gd")
const Archer = preload("res://scripts/archer.gd")
const QuestMarker = preload("res://scripts/warband/quest_marker.gd")
const SfxScript = preload("res://scripts/audio/sfx.gd")

## Where on the way each cage stands, as a fraction of the lane's own length.
## Four stretches, spread far enough apart that a body meets the first one before
## it has walked a third of the road and the last one near the town.
const CAGE_FRACTIONS := [0.34, 0.52, 0.68, 0.86]
## Alternating sides, so walking the road passes a cage on the left, then the
## right: the line reads as a road the wardens work, not a row of a pen.
const CAGE_SIDES := [1.0, -1.0, 1.0, -1.0]
## Metres off the lane's centre line. The band the wood keeps clear is
## `RunForestScript.CLEAR_HALF` (1.55 m), and a cage's own footprint reaches
## 1.25 m back toward the road from its centre - so at 7.6-8.6 m out no post is
## ever inside 6 m of the worn line, and the walk is untouched.
const CAGE_OFFSETS := [7.9, 8.6, 7.6, 8.3]
## Along the lane, tried in order, until the cage's footprint clears every solid
## trunk. The near tree rows stand 11 m apart, so a few metres either way always
## finds a gap between them.
const CAGE_NUDGES := [0.0, -2.0, 2.0, -4.0, 4.0, -5.5, 5.5]
const CAGE_LATERAL_MIN := 6.0
const CAGE_LATERAL_MAX := 9.0
## The cage's footprint (a 2.5 m square) and half of it: a latch is worked through
## the bars or from the dirt in front of them, so reach is measured from the
## cage's edge.
const CAGE_SIZE := 2.5
const CAGE_HALF := 1.25
const LATCH_REACH := 2.2
## The door's lift, and how long it takes. Slow enough to read as iron moving.
const CAGE_BAR_LIFT := 2.6
const DOOR_SECONDS := 1.2
## How far a freed soldier walks out of the bars, and how long that takes.
const WALK_METRES := 1.8
const WALK_SECONDS := 1.4
const FADE_SECONDS := 0.6
## The same 12 cm every body in this world is spawned clear of its ground by.
const SPAWN_LIFT := 0.12
## The marker's poll: the cage nearest the player's body is re-read four times a
## second, which is faster than a body walks out of one cage's reach.
const MARKER_POLL := 0.35
## Where the gold arrow hangs: above the bars, which are 2.9 m to the post caps,
## so the word reads over the cage rather than through it.
const MARKER_HEIGHT := 3.45
const MARKER_LABEL := "FREE HIM"

## The four names the roll takes, in cage order. One per cage, never offered
## twice: a freed soldier is a name on the warband, not a respawn.
const SOLDIER_NAMES := ["Bren", "Hask", "Ilse", "Torvin"]
## The looks the caged figures wear. A look is a pure function of an id
## (`WarbandLooks.profile_for`), so a prisoner is given one of his own: he is a
## body to look at behind the bars, and the man the roll fields when the latch
## opens is dressed from the id the roster hands him.
const SOLDIER_LOOKS := [13, 19, 26, 31]
## Prisoners, not soldiers: the makeshift set where a rag survived the taking and
## bare skin everywhere else, and nothing at all in either hand.
const SOLDIER_RAGS := [
	["legs", "feet"], ["chest"], ["legs"], ["chest", "hands"],
]
const RAG_SET := "makeshift"

## The world this node is built into.
var host: Node3D = null

## One entry per cage, in `CAGE_FRACTIONS` order: `{node, door, soldier, name,
## shut, freed}`. `shut` goes false the frame the latch is cut; `freed` goes true
## when the name reaches the roll, so the two are not the same fact.
var _cages: Array[Dictionary] = []
var _marker: QuestMarker = null
var _poll := 0.0
var _wood: Material = null
var _iron: Material = null


## Build the four cages into `world`. The node parents itself under the world if
## the caller has not done it yet: a cage's global position is what the marker and
## the tests read, and a setup that silently produced four orphans would be worse
## than a little adoption.
func setup(world: Node3D) -> void:
	if not is_instance_valid(world):
		push_error("SoldierCages.setup() needs the world")
		return
	host = world
	_poll = 0.0
	if not is_inside_tree() and world.is_inside_tree():
		world.add_child(self)
	_clear()
	_resolve_materials()
	_build_cages()
	_build_marker()
	_update_marker()


func _process(delta: float) -> void:
	if _marker == null:
		return
	_poll += delta
	if _poll < MARKER_POLL:
		return
	_poll = fmod(_poll, MARKER_POLL)
	_update_marker()


# --- reading ---------------------------------------------------------------

## The cage nodes, in cage order.
func cages() -> Array:
	var out: Array = []
	for cage in _cages:
		out.append(cage["node"])
	return out


## Whether each cage's latch has been cut, in cage order.
func open_cages() -> Array[bool]:
	var out: Array[bool] = []
	for cage in _cages:
		out.append(not bool(cage["shut"]))
	return out


## Cages still shut. This is what the quartermaster's count is short by.
func remaining() -> int:
	var count := 0
	for cage in _cages:
		if bool(cage["shut"]):
			count += 1
	return count


## Soldiers who have walked out and taken a name on the roll.
func freed() -> int:
	var count := 0
	for cage in _cages:
		if bool(cage["freed"]):
			count += 1
	return count


## Where every cage still shut stands, for the map: a marker at the dirt, not at
## the arrow's own height.
func marker_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for cage in _cages:
		if not bool(cage["shut"]):
			continue
		var node: Node3D = cage["node"]
		if is_instance_valid(node):
			out.append(node.global_position)
	return out


# --- the latches -----------------------------------------------------------

## The world's `G`, as far as a cage is concerned. True when the press was the
## cage line's - a latch cut, or a body standing at a shut cage with nothing to
## cut it with and told so. False hands the press on to the counters and the
## floor, exactly as the camp's own latch does.
func interact(actor) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var index := latch_target(actor)
	if index < 0:
		return false
	if not holds_blade(actor):
		_set_status("Nothing to cut the latch with.", 2.5)
		return true
	return open_latch(index)


## The nearest still-shut cage whose edge the body can reach, or -1. Reach is
## measured from the cage's own footprint, so a body at the bars and a body a step
## back are both at the padlock.
func latch_target(actor) -> int:
	if actor == null or not is_instance_valid(actor) or _cages.is_empty():
		return -1
	var at: Vector3 = actor.global_position
	var best := -1
	var best_gap := LATCH_REACH
	for index in _cages.size():
		var cage: Dictionary = _cages[index]
		if not bool(cage["shut"]):
			continue
		var node: Node3D = cage["node"]
		if not is_instance_valid(node):
			continue
		var post := node.global_position
		var gap := maxf(0.0, Vector2(at.x - post.x, at.z - post.z).length() - CAGE_HALF)
		if gap <= best_gap:
			best_gap = gap
			best = index
	return best


## Whether the body has a blade in its hands to cut a latch with: the rig's main
## hand, or a second weapon in the off hand. A fist, a shield or a bow is not a
## knife - the camp's own rule (`cage_escape.gd::holds_blade`), because a latch
## that opened to a bow would teach the wrong thing twice.
func holds_blade(actor) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var rig = actor.get("rig")
	if rig == null or not is_instance_valid(rig):
		return false
	if str(rig.weapon) in ["sword", "dagger", "dual"]:
		return true
	return bool(rig.off_weapon_active) and str(rig.off_weapon_kind) in ["sword", "dagger"]


## One latch, cut: the door lifts, the soldier walks out, the roll takes his name.
## False only when the cage is already open or does not exist - the press was not
## consumed, so a second press on an open cage does nothing at all.
func open_latch(index: int) -> bool:
	if index < 0 or index >= _cages.size():
		return false
	var cage: Dictionary = _cages[index]
	if not bool(cage["shut"]):
		return false
	cage["shut"] = false
	var node: Node3D = cage["node"]
	SfxScript.play("cage_latch", node.global_position + Vector3.UP * 1.1)
	_set_status("Latch cut. %d of %d cages open." % [_cages.size() - remaining(), _cages.size()], 2.5)
	var door: Node3D = cage["door"]
	if not is_instance_valid(door):
		_finish(index)
		return true
	var tween := create_tween()
	tween.tween_property(door, "position:y", CAGE_BAR_LIFT, DOOR_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_walk_out.bind(index))
	return true


## The door is up: the soldier steps out through it. The walk is short and ends
## past the bars, so the frame the name goes on the roll is a body standing in the
## open rather than a figure fading inside its own cage.
func _walk_out(index: int) -> void:
	var cage: Dictionary = _cages[index]
	var soldier = cage["soldier"]
	if soldier == null or not is_instance_valid(soldier):
		_finish(index)
		return
	var target: Vector3 = (soldier as Node3D).position + Vector3(0.0, 0.0, -WALK_METRES)
	var tween := create_tween()
	tween.tween_property(soldier, "position", target, WALK_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_finish.bind(index))


## He is out: the one call that puts him on the roll, then the figure goes. With
## a place on the field his warband body stands up where the figure stood - the
## figure fades over it - and past a full field he waits in the reserve and the
## figure fades with nobody in its place.
## A guest calls nothing - the host owns the roster and the ledger, and a guest
## writing a rescue of its own would count the same soldier twice.
func _finish(index: int) -> void:
	var cage: Dictionary = _cages[index]
	if bool(cage["freed"]):
		return
	cage["freed"] = true
	if not _is_guest() and host != null and host.has_method("note_soldier_freed"):
		var soldier = cage["soldier"]
		var node: Node3D = cage["node"]
		var at: Vector3 = (soldier as Node3D).global_position \
			if soldier != null and is_instance_valid(soldier) else node.global_position
		host.note_soldier_freed(str(cage["name"]), at)
	_fade(index)


## The figure dissolves rather than vanishing: the roll has his name now, and a
## body that blinked out of the dirt beside an open cage reads as a bug.
func _fade(index: int) -> void:
	var cage: Dictionary = _cages[index]
	var soldier = cage["soldier"]
	if soldier == null or not is_instance_valid(soldier):
		_discard(index)
		return
	var meshes := _geometry_under(soldier)
	if meshes.is_empty():
		_discard(index)
		return
	var tween := create_tween().set_parallel(true)
	for mesh in meshes:
		tween.tween_property(mesh, "transparency", 1.0, FADE_SECONDS)
	tween.chain().tween_callback(_discard.bind(index))


func _discard(index: int) -> void:
	var cage: Dictionary = _cages[index]
	var soldier = cage["soldier"]
	cage["soldier"] = null
	if is_instance_valid(soldier):
		(soldier as Node).queue_free()


# --- the arrow -------------------------------------------------------------

## The gold arrow points at the nearest shut cage while the quartermaster's first
## order is on the roll, and at nothing otherwise: a marker over a cage nobody has
## been asked to open is furniture.
func _update_marker() -> void:
	if _marker == null:
		return
	var quests = _quests()
	if quests == null or not quests.is_active("free_the_soldiers"):
		_hide_marker()
		return
	var body = _player_body()
	if body == null:
		_hide_marker()
		return
	var index := _nearest_shut(body.global_position)
	if index < 0:
		_hide_marker()
		return
	var node: Node3D = _cages[index]["node"]
	if not is_instance_valid(node):
		_hide_marker()
		return
	if _marker.target() != node:
		_marker.attach_to(node, MARKER_HEIGHT)
	_marker.visible = true


func _hide_marker() -> void:
	if _marker == null:
		return
	_marker.visible = false
	_marker.detach()


func _nearest_shut(point: Vector3) -> int:
	var best := -1
	var best_distance := INF
	for index in _cages.size():
		var cage: Dictionary = _cages[index]
		if not bool(cage["shut"]):
			continue
		var node: Node3D = cage["node"]
		if not is_instance_valid(node):
			continue
		var distance := Vector2(point.x - node.global_position.x,
			point.z - node.global_position.z).length()
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


# --- the build -------------------------------------------------------------

func _resolve_materials() -> void:
	var mats: Dictionary = CampKit.materials()
	_wood = mats.get("drift_dark")
	var fittings: Dictionary = CampDressing.metal()
	_iron = fittings.get("iron")


func _build_cages() -> void:
	var path = _path()
	if path == null:
		push_error("SoldierCages: the world has no lane to stand the cages along")
		return
	var trunks: Array = _trunks()
	for index in CAGE_FRACTIONS.size():
		var post := _post(path, index, trunks)
		var cage := Node3D.new()
		cage.name = "SoldierCage%d" % (index + 1)
		cage.position = post["at"]
		cage.rotation.y = float(post["yaw"])
		add_child(cage)
		var door := _build_cage(cage)
		var soldier := _build_soldier(cage, index)
		_cages.append({
			"node": cage, "door": door, "soldier": soldier,
			"name": str(SOLDIER_NAMES[index]), "shut": true, "freed": false,
		})


## One cage's ground and facing. The door faces the lane, so a body walking the
## road sees the bars it has to cut rather than a blank back; the post is nudged
## along the lane until the footprint clears every solid trunk.
func _post(path, index: int, trunks: Array) -> Dictionary:
	var base: float = path.total * float(CAGE_FRACTIONS[index])
	var side := float(CAGE_SIDES[index])
	var offset := float(CAGE_OFFSETS[index])
	var fallback := {}
	for nudge in CAGE_NUDGES:
		var frame: Dictionary = path.sample(base + float(nudge))
		var right: Vector3 = frame["right"]
		var at: Vector3 = (frame["position"] as Vector3) + right * side * offset
		at = TerrainScript.grounded(Vector3(at.x, 0.0, at.z))
		var toward: Vector3 = -right * side
		var candidate := {"at": at, "yaw": atan2(-toward.x, -toward.z)}
		if fallback.is_empty():
			fallback = candidate
		if _clear_of_wood(path, at, trunks):
			return candidate
	return fallback


## The cage's own square clears every trunk a body could walk into, and the whole
## of it stands inside the 6-9 m band: either half of that rule broken moves the
## cage, not the line.
func _clear_of_wood(path, at: Vector3, trunks: Array) -> bool:
	var lateral: float = path.distance_to(Vector2(at.x, at.z))
	if lateral < CAGE_LATERAL_MIN or lateral > CAGE_LATERAL_MAX:
		return false
	for trunk in trunks:
		var flat: Vector2 = trunk.get("at", Vector2.ZERO)
		var radius := float(trunk.get("radius", 0.0))
		if Vector2(at.x - flat.x, at.z - flat.y).length() < radius + CAGE_HALF + 0.3:
			return false
	return true


## The camp's cage, one for one: a slab, four posts, bars on three sides and a
## door of bars on the lane side. The bars are collision - three walls and the
## door's own body, which rises with the door - because a cage a body can walk
## through is a picture of a cage.
##
## The iron is merged into two meshes rather than drawn bar by bar: four cages of
## twenty-eight separate cylinders is a hundred draws for furniture standing in
## the dark. One surface per material keeps the cage's look and the camp's rule
## that a structure is a mesh, not a mesh per nail.
func _build_cage(cage: Node3D) -> Node3D:
	var frame := CampKit.Merged.new()
	CampKit.add_box(frame, Vector3(CAGE_SIZE, 0.1, CAGE_SIZE), Vector3(0, -0.03, 0), _wood)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			CampKit.add_box(frame, Vector3(0.17, 2.9, 0.17),
				Vector3(sx * 1.15, 1.45, sz * 1.15), _iron)
	for step in 5:
		var offset := -0.8 + step * 0.4
		CampKit.add_cyl_disc(frame, 0.05, 2.7, Vector3(offset, 1.4, 1.15), _iron, 6)
		CampKit.add_cyl_disc(frame, 0.05, 2.7, Vector3(-1.15, 1.4, offset), _iron, 6)
		CampKit.add_cyl_disc(frame, 0.05, 2.7, Vector3(1.15, 1.4, offset), _iron, 6)
	CampKit.add_box(frame, Vector3(CAGE_SIZE, 0.12, 0.12), Vector3(0, 2.78, -1.15), _iron)
	frame.commit(cage, "CageFrame")
	var door := Node3D.new()
	door.name = "Door"
	door.position = Vector3(0, 0, -1.15)
	cage.add_child(door)
	var gate := CampKit.Merged.new()
	for step in 6:
		CampKit.add_cyl_disc(gate, 0.045, 2.7, Vector3(-1.0 + step * 0.4, 1.4, 0), _iron, 6)
	CampKit.add_box(gate, Vector3(2.4, 0.1, 0.1), Vector3(0, 1.1, 0), _iron)
	gate.commit(door, "DoorFrame")
	var bars := _collision_body(cage, "CageBars")
	_collision_box(bars, Vector3(0.12, 2.7, CAGE_SIZE), Vector3(-1.15, 1.35, 0.0))
	_collision_box(bars, Vector3(0.12, 2.7, CAGE_SIZE), Vector3(1.15, 1.35, 0.0))
	_collision_box(bars, Vector3(CAGE_SIZE, 2.7, 0.12), Vector3(0.0, 1.35, 1.15))
	# The door is its own body for the reason the camp's is: a cut latch opens the
	# front of the cage, not just the picture of it.
	var door_bars := _collision_body(door, "DoorBars")
	_collision_box(door_bars, Vector3(2.4, 2.7, 0.12), Vector3(0.0, 1.35, 0.0))
	return door


## The prisoner: the same rig the band wears, dressed out of the rags that
## survived his taking, standing where the cage clamp would hold him.
func _build_soldier(cage: Node3D, index: int) -> Node3D:
	var rig := Archer.new()
	rig.appearance = WarbandLooks.profile_for(int(SOLDIER_LOOKS[index]))
	rig.position = Vector3(0.0, SPAWN_LIFT, 0.10)
	cage.add_child(rig)
	# `_ready` names the rig "Archer"; the cage's own name is what the world and
	# the tests look the prisoner up by.
	rig.name = "CagedSoldier"
	# `_ready` built the body and measured the look; the kit goes on afterwards,
	# exactly as the paperdoll and the possession controller dress a live rig.
	rig.apply_loadout(State.build_loadout("", "", _rags(index)))
	return rig


## A prisoner's kit: the makeshift set on the slots his rags still cover, and
## nothing on the rest - which on this rig is bare skin.
func _rags(index: int) -> Dictionary:
	var pieces := {}
	for slot in ArmorData.SLOTS:
		pieces[slot] = ArmorData.NONE
	var set_index: int = ArmorData.SET_IDS.find(RAG_SET)
	for slot in SOLDIER_RAGS[index]:
		pieces[str(slot)] = set_index
	return pieces


func _build_marker() -> void:
	_marker = QuestMarker.new()
	_marker.name = "FreeHimMarker"
	add_child(_marker)
	_marker.set_label(MARKER_LABEL)
	_marker.visible = false


## A second setup replaces the line rather than stacking two on the same road.
func _clear() -> void:
	for cage in _cages:
		var node = cage.get("node")
		if is_instance_valid(node):
			(node as Node).queue_free()
	_cages.clear()
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null


# --- the world -------------------------------------------------------------

func _path():
	if host == null:
		return null
	var trail = host.get("trail")
	if trail == null:
		return null
	var forest = trail.get("forest")
	if not (forest is Dictionary):
		return null
	return (forest as Dictionary).get("path")


## Every trunk a body can walk into, as the lane itself published them.
func _trunks() -> Array:
	if host == null:
		return []
	var trail = host.get("trail")
	if trail == null:
		return []
	var forest = trail.get("forest")
	if not (forest is Dictionary):
		return []
	var listed = (forest as Dictionary).get("trunks")
	return listed if listed is Array else []


func _quests():
	if host == null:
		return null
	var warband = host.get("warband")
	if warband == null:
		return null
	return warband.get("quests")


func _player_body():
	if host == null:
		return null
	var controller = host.get("controller")
	if controller == null or not controller.has_method("active_body"):
		return null
	return controller.active_body(1)


func _is_guest() -> bool:
	return host != null and bool(host.get("_client"))


func _set_status(text: String, seconds: float) -> void:
	if host == null:
		return
	var hud = host.get("hud")
	if hud != null and hud.has_method("set_status"):
		hud.set_status(text, seconds)


static func _collision_body(parent: Node3D, node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	return body


static func _collision_box(parent: Node3D, size: Vector3, at: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	parent.add_child(shape)


## Every drawn surface under a figure, for the one fade. A rig is a skeleton with
## a mesh per body region and the kit bolted on top, so the fade walks the tree.
static func _geometry_under(node: Node) -> Array:
	var out: Array = []
	if node is GeometryInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_geometry_under(child))
	return out
