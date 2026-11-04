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
	# A presentation that re-poses its own bones (the ranger rig's clips write the
	# head back every solve) has to be told the head is gone, or the corpse grows
	# a face again on the next frame.
	if head == null and visual.has_method("head_taken"):
		visual.call("head_taken")
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
	# A presentation that re-poses its own bones keeps the stump itself
	# (`head_taken`): shrinking here as well would only compound its scale.
	if skeleton != null and bone >= 0 and not visual.has_method("head_taken"):
		var pose := skeleton.get_bone_pose(bone)
		skeleton.set_bone_pose(bone,
			Transform3D(pose.basis.scaled(Vector3.ONE * STUMP_SCALE), pose.origin))
		skeleton.force_update_all_bone_transforms()
	var amount: float = maxf(damage, 10.0)
	if visual.has_method("blood_anchor"):
		var rig: Node3D = visual.call("blood_anchor")
		if is_instance_valid(rig):
			BloodFx.wound(visual, rig, center, amount, true, true)
	BloodFx.impact(visual, center, shot, amount, true)


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
		_build_head(visual, skeleton, bone, frame)
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
		frame: Transform3D) -> void:
	var owned := {bone: true}
	for index in skeleton.get_bone_count():
		if _is_ancestor_of(skeleton, bone, index):
			owned[index] = true
	var into_frame := frame.affine_inverse() * skeleton.get_global_transform()
	var mesh := ArrayMesh.new()
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if not instance.visible or not _skins_to(instance, skeleton):
			continue
		var skin := instance.skin
		for surface in instance.mesh.get_surface_count():
			var faces := _head_faces(instance.mesh, skin, surface, skeleton, bone, owned)
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
				order.append(_pose_vertex(skin, skeleton, bones, weights, per,
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
	piece.name = "HeadPiece"
	piece.mesh = mesh
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(piece)


## The triangles of one surface that belong to the head. Which triangles those
## are does not depend on the pose, only on the bind, so the split is solved once
## per mesh and reused: a ranger's body is ninety-five thousand vertices, and
## walking them again on every beheading is a frame a kill cannot pay for.
static func _head_faces(mesh: ArrayMesh, skin: Skin, surface: int,
		skeleton: Skeleton3D, bone: int, owned: Dictionary) -> PackedInt32Array:
	var key := "%d:%d:%s" % [mesh.get_instance_id(), surface,
		skeleton.get_bone_name(bone)]
	if _faces.has(key):
		return _faces[key]
	var arrays := mesh.surface_get_arrays(surface)
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
			if owned.has(_bind_bone(skin, skeleton, int(bones[slot]))):
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
static func _pose_vertex(skin: Skin, skeleton: Skeleton3D, bones, weights, per: int,
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
		var limb := _bind_bone(skin, skeleton, bind)
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


static func _bind_bone(skin: Skin, skeleton: Skeleton3D, bind: int) -> int:
	var limb := skin.get_bind_bone(bind)
	if limb >= 0:
		return limb
	var name := skin.get_bind_name(bind)
	return skeleton.find_bone(name) if name != StringName() else -1


## True when this mesh instance is skinned to `skeleton`: the imported rigs name
## it with a NodePath, and a mesh that names nothing is checked against a bind
## name, so a prop that merely sits near the body is never cut into.
static func _skins_to(instance: MeshInstance3D, skeleton: Skeleton3D) -> bool:
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
