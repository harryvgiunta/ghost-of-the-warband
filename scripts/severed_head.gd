extends Node3D
## Death effect: the head an arrow took off.
##
## A killing headshot is spent on the head. A rigged body keeps its skeleton: the
## head bone collapses into the neck it left, and the head itself is skinned once
## into a mesh of its own - only the triangles that head owns, at the pose it
## died in - so the corpse is left a stump and the head becomes a piece in the
## world. A procedural body hands its head node over whole. The head then lives
## as its own small body: the arrow's momentum throws it, gravity drops it, the
## ground stops it, and it rolls to a rest with the shaft still buried in it.
##
## Presentation only: nothing here owns damage, loot or authority. The host and
## every replica throw a head from the same death cause, so a guest sees the
## decapitation the host does.

const Bow = preload("res://scripts/bow.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")
const CorpsePhysics = preload("res://scripts/corpse_physics.gd")

const WORLD_MASK := 1
const GRAVITY := 17.0
## The share of the arrow's speed the head takes, and its floor and ceiling: a
## 55 m/s shaft would fling a skull clean out of the fight, a slow one would drop
## it at the corpse's feet.
const SPEED_SHARE := 0.16
const MIN_SPEED := 3.2
const MAX_SPEED := 7.5
## The upward kick that makes the head arc instead of sliding down the shot's
## own line.
const LIFT := 1.7
const RESTITUTION := 0.26
## How much of the head's tangential speed the ground keeps on a bounce, and the
## friction it bleeds every frame it is rolling.
const GROUND_GRIP := 0.62
const GROUND_FRICTION := 2.2
const TUMBLE := 6.5
const REST_SPEED := 0.22
const REST_FRAMES := 3
## A head that has left its neck is a point, not a head: the corpse's bone keeps
## its joint and loses its volume.
const STUMP_SCALE := 0.001
## A triangle belongs to the head when its corners average at least this much of
## it. The ring the neck keeps is drawn with the head, so the piece carries a torn
## edge instead of a clean cut through the skin, while a body triangle that only
## grazes the head at one corner stays on the corpse.
const HEAD_SHARE := 0.5
const MIN_RADIUS := 0.09
const MAX_RADIUS := 0.30

var _position := Vector3.ZERO
var _velocity := Vector3.ZERO
var _radius := 0.18
var _base := Basis.IDENTITY
var _spin := Basis.IDENTITY
var _tumble := Vector3.ZERO
var _rest_frames := 0
var _query := PhysicsRayQueryParameters3D.new()
## Head triangles solved per mesh surface (`_head_faces`): the split is a property
## of the bind, not of the pose, so every beheading after the first one of a rig
## reuses it instead of walking the whole body again.
static var _faces := {}


## The guarantee that a piece of body is gone: the collapse runs last in the
## frame, after every writer a rig has (a clip solve, a ragdoll bake, a script
## posing the bone), so no pose pipeline can draw it back onto the corpse. With
## `point` set, the bones collapse onto one place in the skeleton instead of onto
## their own joints - a body taken off at a cut keeps a stump where the cut was.
class Stump extends Node:
	const COLLAPSE := 0.001
	var bones := PackedInt32Array()
	## Skeleton-space collapse point; `INF` collapses each bone on its own origin.
	var point := Vector3.INF
	var _skeleton: Skeleton3D

	func _ready() -> void:
		process_priority = 1000
		_skeleton = get_parent() as Skeleton3D

	func _process(_delta: float) -> void:
		enforce()

	## Collapses the bones again if a pose write gave them volume back.
	## Idempotent, and the one place the removal can be checked from.
	func enforce() -> void:
		if _skeleton == null:
			return
		var count := _skeleton.get_bone_count()
		for bone in bones:
			if bone < 0 or bone >= count:
				continue
			var pose := _skeleton.get_bone_pose(bone)
			if pose.basis.get_scale().x < 0.01:
				continue
			if point.is_finite():
				var parent := _skeleton.get_bone_parent(bone)
				var parent_pose := Transform3D.IDENTITY if parent < 0 \
					else _skeleton.get_bone_global_pose(parent)
				_skeleton.set_bone_pose(bone, parent_pose.affine_inverse() \
					* Transform3D(Basis().scaled(Vector3.ONE * COLLAPSE), point))
			else:
				_skeleton.set_bone_pose(bone,
					Transform3D(pose.basis.scaled(Vector3.ONE * COLLAPSE), pose.origin))


## Throws the head of `visual` off along `shot` - the arrow's velocity - and
## leaves a stump behind. Returns the flying head, or null when this body has no
## head to give.
static func sever(visual: Node3D, shot: Vector3, damage: float) -> Node3D:
	if not is_instance_valid(visual) or shot.length_squared() < 0.0001:
		return null
	var skeleton := CorpsePhysics.skeleton_in(visual)
	var bone := head_bone(skeleton)
	var head: Node3D = null
	if bone < 0 and visual.has_method("sever_head"):
		var cut: Variant = visual.call("sever_head")
		if cut is Node3D and is_instance_valid(cut):
			head = cut
			skeleton = null
	if bone < 0 and head == null:
		return null
	# The head's own frame: its bone (or node) handed over whole, spun about the
	# point a shot actually lands on rather than about the neck joint it hung
	# from, so the skull turns over on itself as it goes.
	var origin := Transform3D.IDENTITY
	if head != null:
		origin = head.global_transform
	else:
		origin = skeleton.get_global_transform() * skeleton.get_bone_global_pose(bone)
	var center := origin.origin
	if visual.has_method("head_hitbox_center"):
		var point: Variant = visual.call("head_hitbox_center")
		if point is Vector3 and (point as Vector3).is_finite():
			center = point
	var frame := Transform3D(origin.basis, center)
	var radius := MIN_RADIUS
	if visual.has_method("head_hit_profile"):
		var profile: Vector2 = visual.call("head_hit_profile")
		if profile.y > 0.0:
			var grown: float = maxf(visual.global_transform.basis.get_scale().y, 0.1)
			radius = clampf(profile.y * 1.35 * grown, MIN_RADIUS, MAX_RADIUS)
	var flight = new()
	flight.name = "SeveredHead"
	visual.add_child(flight)
	flight.top_level = true
	flight.setup(visual, shot, frame, frame.affine_inverse() * origin, radius,
		skeleton, bone, head, damage)
	_stump(visual, skeleton, bone, center, shot, damage)
	if bone >= 0:
		_spurt(flight, visual, skeleton, bone, shot, damage)
	return flight


## The deforming head bone. The rigs name it `Head` (the five devils, the ranger)
## or `head` (the Cinder devil, the forest mobs, the wolf), and the capitalised
## rigs carry an empty `head` helper below it, so the outer one is the head.
static func head_bone(skeleton: Skeleton3D) -> int:
	if skeleton == null:
		return -1
	var found := -1
	for index in skeleton.get_bone_count():
		if skeleton.get_bone_name(index).to_lower() != "head":
			continue
		if found < 0 or _is_ancestor_of(skeleton, index, found):
			found = index
	return found


static func _is_ancestor_of(skeleton: Skeleton3D, ancestor: int, bone: int) -> bool:
	var parent := skeleton.get_bone_parent(bone)
	while parent >= 0:
		if parent == ancestor:
			return true
		parent = skeleton.get_bone_parent(parent)
	return false


## What the corpse keeps: the head bone loses its volume where it hangs - so the
## stump stays welded to the neck and falls with the body - and the neck takes a
## fresh soak.
static func _stump(visual: Node3D, skeleton: Skeleton3D, bone: int,
		center: Vector3, shot: Vector3, damage: float) -> void:
	if skeleton != null and bone >= 0:
		# The frame the head leaves: shrink now, and keep it shrunk through the
		# modifier so no later pose solve can give the corpse its head back.
		var pose := skeleton.get_bone_pose(bone)
		skeleton.set_bone_pose(bone,
			Transform3D(pose.basis.scaled(Vector3.ONE * STUMP_SCALE), pose.origin))
		skeleton.force_update_all_bone_transforms()
		if skeleton.find_child("HeadStump", false, false) == null:
			var stump := Stump.new()
			stump.name = "HeadStump"
			stump.bones = PackedInt32Array([bone])
			skeleton.add_child(stump)
	var amount: float = maxf(damage, 10.0)
	if visual.has_method("blood_anchor"):
		var rig: Node3D = visual.call("blood_anchor")
		if is_instance_valid(rig):
			BloodFx.wound(visual, rig, center, amount, true, true)
	# The neck's own fountain, not a contact spray: a head coming off is the one
	# death in the game that should be read in blood from across the room.
	BloodFx.arterial(visual, center, shot, amount, 1.0)


## A decapitated body does not bleed once: three more jets leave the stump as the
## corpse goes down, each read from the neck as it is at that moment.
static func _spurt(flight: Node3D, visual: Node3D, skeleton: Skeleton3D, bone: int,
		shot: Vector3, damage: float) -> void:
	if not is_instance_valid(flight) or skeleton == null or bone < 0:
		return
	var tween := flight.create_tween()
	var times := [0.14, 0.30, 0.52]
	var shares := [0.62, 0.46, 0.34]
	var previous := 0.0
	for index in times.size():
		tween.tween_interval(float(times[index]) - previous)
		previous = float(times[index])
		tween.tween_callback(_pulse.bind(visual, skeleton, bone, shot,
			damage * float(shares[index])))


static func _pulse(visual: Node3D, skeleton: Skeleton3D, bone: int, shot: Vector3,
		damage: float) -> void:
	if not is_instance_valid(visual) or not is_instance_valid(skeleton):
		return
	if not skeleton.is_inside_tree():
		return
	var at: Vector3 = (skeleton.get_global_transform()
		* skeleton.get_bone_global_pose(bone)).origin
	BloodFx.arterial(visual, at, shot, maxf(damage, 8.0), 0.8)


func setup(visual: Node3D, shot: Vector3, frame: Transform3D, offset: Transform3D,
		radius: float, skeleton: Skeleton3D, bone: int, head: Node3D,
		damage: float) -> void:
	_base = frame.basis
	_position = frame.origin
	_radius = radius
	if head != null:
		var holder := head.get_parent()
		if holder != null:
			holder.remove_child(head)
		head.top_level = false
		add_child(head)
		head.transform = offset
		head.visible = true
	elif skeleton != null and bone >= 0:
		var piece := _build_head(visual, skeleton, bone, frame)
		if is_instance_valid(piece):
			add_child(piece)
			# The piece comes out of a wound: it is wet before it is thrown.
			BloodFx.stain_projectile(piece, maxf(damage, 10.0))
	var direction := shot.normalized()
	var speed: float = clampf(shot.length() * SPEED_SHARE, MIN_SPEED, MAX_SPEED)
	_velocity = direction * speed + Vector3.UP * LIFT
	# Rolling axis for a head moving along the shot, plus the tumble a head takes
	# in the air; the ground hands it the first and takes the second.
	var axis := Vector3.UP.cross(direction)
	if axis.length_squared() < 0.001:
		axis = Vector3.RIGHT
	_tumble = (axis.normalized() * 0.55 - _base.z.normalized() * 0.85).normalized() * TUMBLE
	_apply()
	_place_shaft(shot, maxf(damage, 10.0))


## The head as a mesh of its own: every skinned surface that draws on this rig is
## posed once at the lethal frame and only the triangles that head owns are kept,
## so the piece carries the rig's own skin, materials and normals and nothing of
## the body it left. The vertices are written in the head's frame, so the flight
## moves them rigidly and the corpse's own skin is never dragged along.
##
## Every mesh that skins to the skeleton is read, not only the body's own: a
## ranger's hood, coif or helm is a separate skinned mesh bound to the same bones,
## so it is part of the head and leaves with it. A mesh that is not drawn right
## now (the armour sets the body is not wearing) is never cut in.
func _build_head(visual: Node3D, skeleton: Skeleton3D, bone: int,
		frame: Transform3D) -> MeshInstance3D:
	var owned := {bone: true}
	for index in skeleton.get_bone_count():
		if _is_ancestor_of(skeleton, bone, index):
			owned[index] = true
	return build_piece(visual, skeleton, frame, owned, skeleton.get_bone_name(bone))


## Every body piece this file cuts is the same operation: the rig's own skinned
## surfaces, posed once at the death frame, reduced to the triangles that belong
## to `owned` (a set of bone indices) and written in `frame`'s space. `tag` names
## the split in the cache, because the triangle set depends on which bones own it.
static func build_piece(visual: Node3D, skeleton: Skeleton3D, frame: Transform3D,
		owned: Dictionary, tag: String) -> MeshInstance3D:
	var into_frame := frame.affine_inverse() * skeleton.get_global_transform()
	var mesh := ArrayMesh.new()
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if not instance.visible or not skins_to(instance, skeleton):
			continue
		var skin := instance.skin
		for surface in instance.mesh.get_surface_count():
			var faces := faces_for(instance.mesh, skin, surface, skeleton, owned, tag)
			if faces.is_empty():
				continue
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices = arrays[Mesh.ARRAY_VERTEX]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			if vertices == null or bones == null or weights == null:
				continue
			var per: int = bones.size() / vertices.size()
			var raw_normal = arrays[Mesh.ARRAY_NORMAL]
			var raw_uv = arrays[Mesh.ARRAY_TEX_UV]
			var raw_uv2 = arrays[Mesh.ARRAY_TEX_UV2]
			var raw_color = arrays[Mesh.ARRAY_COLOR]
			var raw_tangent = arrays[Mesh.ARRAY_TANGENT]
			var posed := {}
			var order: Array = []
			for vertex in faces:
				var id := int(vertex)
				if posed.has(id):
					continue
				posed[id] = order.size()
				order.append(pose_vertex(skin, skeleton, bones, weights, per,
					vertices, raw_normal, raw_uv, raw_uv2, raw_color,
					raw_tangent, id, into_frame))
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			for entry in order:
				var data: Array = entry
				if raw_normal != null:
					tool.set_normal(data[1])
				if raw_uv != null:
					tool.set_uv(data[2])
				if raw_uv2 != null:
					tool.set_uv2(data[3])
				if raw_color != null:
					tool.set_color(data[4])
				if raw_tangent != null:
					tool.set_tangent(data[5])
				tool.add_vertex(data[0])
			# The piece is a small mesh with a lot of shared corners, so the
			# indices go in after the vertices: the tool pays per attribute set,
			# and a corner does not need posing three times.
			for vertex in faces:
				tool.add_index(int(posed[int(vertex)]))
			mesh = tool.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1,
				instance.get_active_material(surface))
	var piece := MeshInstance3D.new()
	piece.name = "GorePiece"
	piece.mesh = mesh
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return piece


## Every vertex of one surface, posed the way `pose_vertex` poses one, in three
## packed arrays. The bind's limb and its posed transform are resolved once per
## bind and reused across the surface: a body's ninety-five thousand vertices
## read the same thirty-odd bones, and asking the skin for each of them per corner
## is what a two-handed kill used to spend its whole frame on.
static func _posed_surface(skinned: bool, skin: Skin, skeleton: Skeleton3D,
		arrays: Array, count: int, per: int, into: Transform3D) -> Dictionary:
	var vertices = arrays[Mesh.ARRAY_VERTEX]
	var raw_normal = arrays[Mesh.ARRAY_NORMAL]
	var raw_tangent = arrays[Mesh.ARRAY_TANGENT]
	var basis := into.basis
	var points := PackedVector3Array()
	points.resize(count)
	var normals := PackedVector3Array()
	normals.resize(count)
	var tangents := PackedVector3Array()
	tangents.resize(count)
	if skinned:
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		var limbs := {}
		var xforms := {}
		for vertex in count:
			var point := Vector3.ZERO
			var normal := Vector3.ZERO
			var tangent := Vector3.ZERO
			var corner := vertex * 4
			var at: Vector3 = vertices[vertex]
			for influence in per:
				var slot := vertex * per + influence
				var weight: float = weights[slot]
				if weight <= 0.0001:
					continue
				var bind := int(bones[slot])
				var limb: int = limbs.get(bind, -2)
				if limb == -2:
					limb = bind_bone(skin, skeleton, bind)
					limbs[bind] = limb
				if limb < 0:
					continue
				var limb_pose: Transform3D
				if xforms.has(bind):
					limb_pose = xforms[bind]
				else:
					limb_pose = skeleton.get_bone_global_pose(limb) * skin.get_bind_pose(bind)
					xforms[bind] = limb_pose
				point += (limb_pose * at) * weight
				if raw_normal != null:
					normal += (limb_pose.basis * (raw_normal[vertex] as Vector3)) * weight
				if raw_tangent != null:
					tangent += Vector3(raw_tangent[corner], raw_tangent[corner + 1],
						raw_tangent[corner + 2]) * weight
			points[vertex] = into * point
			normals[vertex] = (basis * normal).normalized() if raw_normal != null else Vector3.UP
			tangents[vertex] = (basis * tangent).normalized() if raw_tangent != null else Vector3.RIGHT
	else:
		for vertex in count:
			points[vertex] = into * (vertices[vertex] as Vector3)
			normals[vertex] = (basis * (raw_normal[vertex] as Vector3)).normalized() \
				if raw_normal != null else Vector3.UP
			if raw_tangent != null:
				var corner := vertex * 4
				tangents[vertex] = (basis * Vector3(raw_tangent[corner],
					raw_tangent[corner + 1], raw_tangent[corner + 2])).normalized()
			else:
				tangents[vertex] = Vector3.RIGHT
	return {"points": points, "normals": normals, "tangents": tangents}


## A corner this close to the blade's plane is written on it: a crossing found
## inside a tenth of a millimetre is a corner of the cut, not a sliver of face.
const PLANE_EPSILON := 0.0001


## One half of one surface while it is built: only the corners its own triangles
## use, and one corner per edge the blade crossed, shared by both triangles that
## meet on it - so a cut ring is one ring and a corner is written once per half.
## The posed arrays are read in place; nothing here copies the body's pose.
class HalfPiece:
	## A triangle the clip has squeezed onto a line is no triangle.
	const FLAT := 0.000000000001
	var posed_points := PackedVector3Array()
	var posed_normals := PackedVector3Array()
	var posed_tangents := PackedVector3Array()
	var handedness := PackedFloat32Array()
	var raw_uvs = null
	var raw_uv2s = null
	var raw_colors = null
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedVector3Array()
	var handed := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var faces := PackedInt32Array()
	var _whole := {}
	var _seam := {}

	## A corner the posed body already has.
	func whole(id: int) -> int:
		var slot: int = _whole.get(id, -1)
		if slot < 0:
			slot = _add(id, posed_points[id], posed_normals[id], posed_tangents[id],
				_uv(id, id, 0.0), _uv2(id, id, 0.0), _color(id, id, 0.0))
			_whole[id] = slot
		return slot

	## Where the edge `a`-`b` meets the blade, `along` the way from `a` to `b`: the
	## corner the cut ring is made of, at the pose the two corners were solved to.
	func seam(a: int, b: int, along: float) -> int:
		var key := Vector2i(mini(a, b), maxi(a, b))
		var slot: int = _seam.get(key, -1)
		if slot >= 0:
			return slot
		var forwards := a <= b
		var from := a if forwards else b
		var to := b if forwards else a
		var t := along if forwards else 1.0 - along
		var normal := posed_normals[from].lerp(posed_normals[to], t)
		var tangent := posed_tangents[from].lerp(posed_tangents[to], t)
		if normal.length_squared() > 0.000001:
			normal = normal.normalized()
		else:
			normal = posed_normals[from]
		if tangent.length_squared() > 0.000001:
			tangent = tangent.normalized()
		else:
			tangent = posed_tangents[from]
		slot = _add(from, posed_points[from].lerp(posed_points[to], t), normal,
			tangent, _uv(from, to, t), _uv2(from, to, t), _color(from, to, t))
		_seam[key] = slot
		return slot

	## One triangle of the half. A crossing that has left it flat is dropped, so a
	## cut never leaves a degenerate face or a normal solved out of nothing.
	func face(a: int, b: int, c: int) -> void:
		if (points[b] - points[a]).cross(points[c] - points[a]).length_squared() < FLAT:
			return
		faces.append(a)
		faces.append(b)
		faces.append(c)

	func _add(source: int, point: Vector3, normal: Vector3, tangent: Vector3,
			uv: Vector2, uv2: Vector2, color: Color) -> int:
		points.append(point)
		normals.append(normal)
		tangents.append(tangent)
		handed.append(handedness[source])
		uvs.append(uv)
		uv2s.append(uv2)
		colors.append(color)
		return points.size() - 1

	func _uv(from: int, to: int, along: float) -> Vector2:
		if raw_uvs == null:
			return Vector2.ZERO
		var first: Vector2 = raw_uvs[from]
		var second: Vector2 = raw_uvs[to]
		return first.lerp(second, along)

	func _uv2(from: int, to: int, along: float) -> Vector2:
		if raw_uv2s == null:
			return Vector2.ZERO
		var first: Vector2 = raw_uv2s[from]
		var second: Vector2 = raw_uv2s[to]
		return first.lerp(second, along)

	func _color(from: int, to: int, along: float) -> Color:
		if raw_colors == null:
			return Color.WHITE
		var first: Color = raw_colors[from]
		var second: Color = raw_colors[to]
		return first.lerp(second, along)


## A body cut clean through by a plane into two halves. Every surface the body is
## drawn with is posed once at the death frame, and every triangle of it is clipped
## against the plane through the frame's own origin along `normal`: what lies on a
## half's side is that half's, what straddles is cut on the plane and each half
## keeps its own part of it, and what lies beyond is dropped - so the two halves
## together are the body exactly once, and the blade's plane is the only place a
## corner of it is in both. Returns `[positive, negative]` meshes, either of which
## may be empty. The vertices are written in `frame`, so each half can be turned
## over rigidly on its own.
static func build_sides(visual: Node3D, skeleton: Skeleton3D, frame: Transform3D,
		normal: Vector3) -> Array:
	var to_frame := frame.affine_inverse()
	var into_frame := to_frame * skeleton.get_global_transform()
	# The blade's plane, in the frame the corners are written in: the body is cut
	# along its own middle, not along a world axis it may have been turned off.
	var plane := (to_frame.basis * normal).normalized()
	var meshes: Array = [ArrayMesh.new(), ArrayMesh.new()]
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if not instance.visible or instance.mesh == null:
			continue
		# Blood laid on the body is a decal, not a layer of it: cutting a soak in
		# two would paint the same stain onto both halves.
		if instance.has_meta("blood_stain"):
			continue
		# A body can be drawn by more than the skinned skeleton: a baked static
		# layer (the ranger's own body under a creature's skin) is cut too, in its
		# own space, or it would stand whole beside the halves as a second antler.
		var skinned := skins_to(instance, skeleton)
		if not skinned and instance.skin != null:
			continue
		var skin := instance.skin
		var into_static := to_frame * instance.global_transform
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			# A surface that answers no vertex array draws nothing to cut: a
			# primitive proxy or an unset mesh contributes no triangles to either
			# half instead of erroring the whole cut.
			if arrays.is_empty():
				continue
			var vertices = arrays[Mesh.ARRAY_VERTEX]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			if vertices == null or vertices.size() < 3:
				continue
			if skinned and (bones == null or weights == null
					or bones.is_empty() or weights.is_empty()):
				continue
			var count: int = vertices.size()
			var per: int = 0
			if skinned:
				per = bones.size() / maxi(count, 1)
			var raw_normal = arrays[Mesh.ARRAY_NORMAL]
			var raw_uv = arrays[Mesh.ARRAY_TEX_UV]
			var raw_uv2 = arrays[Mesh.ARRAY_TEX_UV2]
			var raw_color = arrays[Mesh.ARRAY_COLOR]
			var raw_tangent = arrays[Mesh.ARRAY_TANGENT]
			# Every vertex of the body is posed once, on the frame of a kill: the
			# pass is the whole cost of a cut, so it keeps the two things a vertex
			# loop otherwise pays for every corner twice - the bind's limb and its
			# posed transform - and holds the result in packed arrays instead of a
			# dictionary of six-element arrays.
			var posed := _posed_surface(skinned, skin, skeleton, arrays, count, per,
				into_frame if skinned else into_static)
			var points: PackedVector3Array = posed["points"]
			var normals: PackedVector3Array = posed["normals"]
			var tangents: PackedVector3Array = posed["tangents"]
			# One pass prepares both halves: the side of the blade each corner sits
			# on, and the handedness its tangent arrives with.
			var across := PackedFloat32Array()
			across.resize(count)
			var handedness := PackedFloat32Array()
			handedness.resize(count)
			for vertex in count:
				across[vertex] = plane.dot(points[vertex])
				handedness[vertex] = float(raw_tangent[vertex * 4 + 3]) \
					if raw_tangent != null else 1.0
			var order := PackedInt32Array()
			var indices = arrays[Mesh.ARRAY_INDEX]
			if indices == null:
				order.resize(count)
				for vertex in count:
					order[vertex] = vertex
			else:
				order = indices
			for half in 2:
				var keep := 1.0 if half == 0 else -1.0
				var half_piece := HalfPiece.new()
				half_piece.posed_points = points
				half_piece.posed_normals = normals
				half_piece.posed_tangents = tangents
				half_piece.handedness = handedness
				half_piece.raw_uvs = raw_uv
				half_piece.raw_uv2s = raw_uv2
				half_piece.raw_colors = raw_color
				for corner in range(0, order.size() - 2, 3):
					var a := int(order[corner])
					var b := int(order[corner + 1])
					var c := int(order[corner + 2])
					var da: float = keep * across[a]
					var db: float = keep * across[b]
					var dc: float = keep * across[c]
					var lowest: float = minf(da, minf(db, dc))
					var highest: float = maxf(da, maxf(db, dc))
					# Flat in the blade's plane: that is the cut, not a half of it.
					if lowest >= -PLANE_EPSILON and highest <= PLANE_EPSILON:
						continue
					if lowest >= 0.0:
						half_piece.face(half_piece.whole(a), half_piece.whole(b),
							half_piece.whole(c))
						continue
					if highest <= 0.0:
						continue
					# The blade crossed this triangle: each half keeps the part on
					# its own side, closed by a fresh edge lying in the plane.
					var cut := PackedInt32Array()
					var ids := [a, b, c]
					var sides := [da, db, dc]
					for edge in 3:
						var next: int = (edge + 1) % 3
						var here: float = sides[edge]
						var there: float = sides[next]
						if here >= 0.0:
							cut.append(half_piece.whole(int(ids[edge])))
						if (here > 0.0 and there < 0.0) or (here < 0.0 and there > 0.0):
							cut.append(half_piece.seam(int(ids[edge]), int(ids[next]),
								here / (here - there)))
					for fan in range(1, cut.size() - 1):
						half_piece.face(cut[0], cut[fan], cut[fan + 1])
				if half_piece.faces.is_empty():
					continue
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				for slot in half_piece.points.size():
					if raw_normal != null:
						tool.set_normal(half_piece.normals[slot])
					if raw_uv != null:
						tool.set_uv(half_piece.uvs[slot])
					if raw_uv2 != null:
						tool.set_uv2(half_piece.uv2s[slot])
					if raw_color != null:
						tool.set_color(half_piece.colors[slot])
					if raw_tangent != null:
						var tangent: Vector3 = half_piece.tangents[slot]
						tool.set_tangent(Plane(tangent.x, tangent.y, tangent.z,
							half_piece.handed[slot]))
					tool.add_vertex(half_piece.points[slot])
				for index in half_piece.faces:
					tool.add_index(index)
				var target: ArrayMesh = meshes[half]
				target = tool.commit(target)
				target.surface_set_material(target.get_surface_count() - 1,
					instance.get_active_material(surface))
				meshes[half] = target
	var pieces: Array = []
	for index in 2:
		var mesh: ArrayMesh = meshes[index]
		if mesh.get_surface_count() == 0:
			pieces.append(null)
			continue
		var piece := MeshInstance3D.new()
		piece.name = "GoreHalf"
		piece.mesh = mesh
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		pieces.append(piece)
	return pieces


## The triangles of one surface that belong to the head. Which triangles those
## are does not depend on the pose, only on the bind, so the split is solved once
## per mesh and reused: a ranger's body is ninety-five thousand vertices, and
## walking them again on every beheading is a frame a kill cannot pay for.
static func faces_for(mesh: ArrayMesh, skin: Skin, surface: int,
		skeleton: Skeleton3D, owned: Dictionary, tag: String) -> PackedInt32Array:
	var key := "%d:%d:%s" % [mesh.get_instance_id(), surface, tag]
	if _faces.has(key):
		return _faces[key]
	var arrays := mesh.surface_get_arrays(surface)
	if arrays.is_empty():
		return PackedInt32Array()
	var vertices = arrays[Mesh.ARRAY_VERTEX]
	var bones = arrays[Mesh.ARRAY_BONES]
	var weights = arrays[Mesh.ARRAY_WEIGHTS]
	if vertices == null or bones == null or weights == null:
		return PackedInt32Array()
	var count: int = vertices.size()
	var per: int = bones.size() / maxi(count, 1)
	var share := PackedFloat32Array()
	share.resize(count)
	for vertex in count:
		var total := 0.0
		for influence in per:
			var slot := vertex * per + influence
			var weight: float = weights[slot]
			if weight <= 0.0001:
				continue
			if owned.has(bind_bone(skin, skeleton, int(bones[slot]))):
				total += weight
		share[vertex] = total
	var order := PackedInt32Array()
	var indices = arrays[Mesh.ARRAY_INDEX]
	if indices == null:
		order.resize(count)
		for vertex in count:
			order[vertex] = vertex
	else:
		order = indices
	var faces := PackedInt32Array()
	for corner in range(0, order.size() - 2, 3):
		var a := int(order[corner])
		var b := int(order[corner + 1])
		var c := int(order[corner + 2])
		# A triangle belongs to the head when most of it does: the seam ring the
		# neck keeps comes with it, and a body triangle that only grazes the head
		# at one corner stays behind.
		if share[a] + share[b] + share[c] < HEAD_SHARE * 3.0:
			continue
		faces.append(a)
		faces.append(b)
		faces.append(c)
	if _faces.size() > 96:
		_faces.clear()
	_faces[key] = faces
	return faces


## One vertex of the head, skinned at the lethal pose and written in the head's
## frame: position, normal, uv, uv2, colour and tangent.
static func pose_vertex(skin: Skin, skeleton: Skeleton3D, bones, weights, per: int,
		vertices, raw_normal, raw_uv, raw_uv2, raw_color, raw_tangent,
		vertex: int, into_frame: Transform3D) -> Array:
	var point := Vector3.ZERO
	var normal := Vector3.ZERO
	var tangent := Vector3.ZERO
	# Tangents arrive as four floats each: x, y, z and the handedness.
	var corner := vertex * 4
	var handedness := 1.0
	if raw_tangent != null:
		handedness = raw_tangent[corner + 3]
	for influence in per:
		var slot := vertex * per + influence
		var weight: float = weights[slot]
		if weight <= 0.0001:
			continue
		var bind := int(bones[slot])
		var limb := bind_bone(skin, skeleton, bind)
		if limb < 0:
			continue
		var skinning := skeleton.get_bone_global_pose(limb) * skin.get_bind_pose(bind)
		point += (skinning * (vertices[vertex] as Vector3)) * weight
		if raw_normal != null:
			normal += (skinning.basis * (raw_normal[vertex] as Vector3)) * weight
		if raw_tangent != null:
			tangent += Vector3(raw_tangent[corner], raw_tangent[corner + 1],
				raw_tangent[corner + 2]) * weight
	var basis := into_frame.basis
	var out_point := into_frame * point
	var out_normal := (basis * normal).normalized() if raw_normal != null else Vector3.UP
	var out_tangent := (basis * tangent).normalized() if raw_tangent != null else Vector3.RIGHT
	return [
		out_point,
		out_normal,
		(raw_uv[vertex] as Vector2) if raw_uv != null else Vector2.ZERO,
		(raw_uv2[vertex] as Vector2) if raw_uv2 != null else Vector2.ZERO,
		(raw_color[vertex] as Color) if raw_color != null else Color.WHITE,
		Plane(out_tangent.x, out_tangent.y, out_tangent.z, handedness),
	]


static func bind_bone(skin: Skin, skeleton: Skeleton3D, bind: int) -> int:
	var limb := skin.get_bind_bone(bind)
	if limb >= 0:
		return limb
	var name := skin.get_bind_name(bind)
	return skeleton.find_bone(name) if name != StringName() else -1


## True when this mesh instance is skinned to `skeleton`: the imported rigs name
## it with a NodePath, and a mesh that names nothing is checked against a bind
## name, so a prop that merely sits near the body is never cut into.
static func skins_to(instance: MeshInstance3D, skeleton: Skeleton3D) -> bool:
	if instance.mesh == null or instance.skin == null or skeleton == null:
		return false
	if instance.skeleton != NodePath():
		var bound := instance.get_node_or_null(instance.skeleton)
		if bound != null:
			return bound == skeleton
	var skin := instance.skin
	return skin.get_bind_count() > 0 \
		and skeleton.find_bone(skin.get_bind_name(0)) >= 0


## The shaft stays where it landed: its tip inside the head, the rest of it out
## the back the way the shot was going.
func _place_shaft(shot: Vector3, damage: float) -> void:
	var direction := shot.normalized()
	var basis := Basis.looking_at(direction, Vector3.UP)
	var shaft := Bow.create_arrow_visual()
	add_child(shaft)
	# The arrow's modelled tip sits ARROW_LENGTH along its own -Z, so an origin
	# this far behind the head's centre puts the head on the arrow.
	var world := Transform3D(basis, _position + basis.z * Bow.ARROW_LENGTH)
	shaft.transform = global_transform.affine_inverse() * world
	BloodFx.stain_projectile(shaft, damage)


func _physics_process(delta: float) -> void:
	_position += _velocity * delta
	_velocity.y -= GRAVITY * delta
	_query.from = _position
	_query.to = _position - Vector3.UP * (_radius + 0.75)
	_query.collision_mask = WORLD_MASK
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	var rolling := false
	if not hit.is_empty():
		var normal: Vector3 = hit.normal
		var bottom: Vector3 = (hit.position as Vector3) + normal * _radius
		if _position.y <= bottom.y + 0.02:
			_position = bottom
			var falling := _velocity.dot(normal)
			var along := _velocity - normal * falling
			if falling < -1.4:
				_velocity = normal * (-falling * RESTITUTION) + along * GROUND_GRIP
			else:
				_velocity = along * GROUND_GRIP
			_velocity *= maxf(0.0, 1.0 - GROUND_FRICTION * delta)
			rolling = true
	if rolling:
		var travel := Vector3(_velocity.x, 0.0, _velocity.z)
		var speed := travel.length()
		if speed > 0.001:
			# A head rolling on the ground turns as fast as its radius says.
			_spin = Basis(Vector3.UP.cross(travel / speed),
				speed / maxf(_radius, 0.02) * delta) * _spin
		if speed < REST_SPEED:
			_rest_frames += 1
			if _rest_frames >= REST_FRAMES:
				_apply()
				set_physics_process(false)
				return
		else:
			_rest_frames = 0
	elif _tumble.length_squared() > 0.0001:
		_spin = Basis(_tumble.normalized(), _tumble.length() * delta) * _spin
		_rest_frames = 0
	_apply()
	if _position.y < -30.0:
		queue_free()


func _apply() -> void:
	global_transform = Transform3D(_spin * _base, _position)
