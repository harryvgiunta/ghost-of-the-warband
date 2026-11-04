extends RefCounted
## Death effects for a body a blade took apart.
##
## Two cuts, one file, because they share the wound:
## - **down** (`horizontal`): a two-handed side chop opens the body a third of the
##   way down. The bones above the cut own the upper piece, the corpse keeps its
##   lower half with those bones collapsed onto the cut, and the top falls away.
## - **apart** (`vertical`): a two-handed overhead slices the body in two down the
##   blade's own plane. Both halves are cut out of the rig, every layer the corpse
##   was drawing is hidden behind them, and the two fall apart.
##
## Rigged, upright bodies only: a cut only means something on a body tall enough
## to have a third of it, and a wolf is as long as it is tall. Presentation only -
## nothing here owns damage, loot or authority, and the host and every replica
## cut the same body from the same death cause.

const SeveredHead = preload("res://scripts/severed_head.gd")
const CorpsePhysics = preload("res://scripts/corpse_physics.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")
const Geo = preload("res://scripts/geo.gd")

const WORLD_MASK := 1
## Where the sideways cut sits between the feet and the head.
const CUT_SHARE := 0.62
## A cut only means something on a body tall enough to have a third of it.
const MIN_HEIGHT := 1.2
const TOPPLE_DEGREES := 82.0
## The cut is a place, not a throw: the pieces tip over where they stand.
const COILS := 5
const LUMPS := 4

const KIND_DOWN := "horizontal"
const KIND_APART := "vertical"


## Cuts `visual` in two. `force` is the shove of the blow (the blade's travel);
## `kind` is `down` for a side chop and `apart` for an overhead. Returns the
## node the pieces hang from, or null when the body cannot be cut.
static func split(visual: Node3D, force: Vector3, damage: float,
		kind: String = KIND_DOWN) -> Node3D:
	if not is_instance_valid(visual):
		return null
	var skeleton := CorpsePhysics.skeleton_in(visual)
	if skeleton == null:
		return null
	var root := skeleton.get_global_transform().origin
	var head := _head_of(visual, skeleton)
	if head.y - root.y < MIN_HEIGHT:
		return null
	var push := Vector3(force.x, 0.0, force.z)
	if push.length_squared() < 0.001:
		push = Vector3.FORWARD
	push = push.normalized()
	if kind == KIND_APART:
		return _apart(visual, skeleton, root, push, damage)
	return _down(visual, skeleton, root, head, push, damage)


## The side chop: everything above a third down leaves as one piece.
static func _down(visual: Node3D, skeleton: Skeleton3D, root: Vector3, head: Vector3,
		push: Vector3, damage: float) -> Node3D:
	var cut := Vector3(root.x, lerpf(root.y, head.y, CUT_SHARE), root.z)
	var owned := _upper_bones(skeleton, cut.y)
	if owned.is_empty():
		return null
	var frame := Transform3D(skeleton.get_global_transform().basis.orthonormalized(), cut)
	var piece := SeveredHead.build_piece(visual, skeleton, frame, owned,
		"cut:" + _tag(skeleton, owned))
	if piece == null or piece.mesh == null or piece.mesh.get_surface_count() == 0:
		return null
	var holder := _holder(visual, frame)
	holder.add_child(piece)
	# The corpse keeps the lower two thirds and nothing above the cut, and the
	# collapse happens before the ragdoll is built from the lethal pose.
	_stump(skeleton, owned, cut)
	_wound(visual, cut, push, damage)
	_fall(holder, frame, piece, push, TOPPLE_DEGREES, 0.0, 0.0)
	return holder


## The overhead: the blade's own plane takes the body in two and both halves fall
## apart. The corpse draws nothing afterwards, because a vertical cut cannot be
## drawn with a bone: the halves are the body now.
static func _apart(visual: Node3D, skeleton: Skeleton3D, root: Vector3,
		push: Vector3, damage: float) -> Node3D:
	var normal := Vector3.UP.cross(push)
	if normal.length_squared() < 0.001:
		normal = Vector3.RIGHT
	normal = normal.normalized()
	var middle := Vector3(root.x, root.y + 1.0, root.z)
	var frame := Transform3D(skeleton.get_global_transform().basis.orthonormalized(),
		middle)
	var halves := SeveredHead.build_sides(visual, skeleton, frame, normal,
		normal.dot(frame.affine_inverse() * root))
	if halves[0] == null and halves[1] == null:
		return null
	# Every layer the corpse was drawing goes - the skinned body, the static one
	# under it, the props - or a whole head would stand beside the cut pieces.
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).visible = false
	var holder := _holder(visual, frame)
	for half in 2:
		var piece: MeshInstance3D = halves[half]
		if piece == null:
			continue
		var side := normal if half == 0 else -normal
		# The cut is a wound, not a parting: a face of meat closes the open side
		# of each half, or the two of them read as two whole bodies lying near each
		# other instead of one opened down the middle.
		_section(piece, frame, side)
		var arm := Node3D.new()
		arm.name = "BodyHalf"
		holder.add_child(arm)
		arm.top_level = true
		arm.global_transform = frame
		arm.add_child(piece)
		# Two halves, two falls: the cut holds for a breath, then each half goes
		# over its own base and lands flat, the far one a heartbeat later. A body
		# cut in two falls; it does not keep standing there in two pieces.
		_fall(arm, frame, piece, side,
			93.0 if half == 0 else 87.0, 0.12 if half == 0 else 0.19,
			-0.06 if half == 0 else 0.05)
	_wound(visual, middle, push, damage)
	return holder


## The cut face of one half: the meat the blade went through, filled in the plane
## from where the piece's own triangles meet it - the outline of the section, not
## a box around the half, or the face is a billboard where the body used to be.
static func _section(piece: MeshInstance3D, frame: Transform3D, side: Vector3) -> void:
	var local := frame.basis.inverse() * side
	if local.length_squared() < 0.001:
		return
	local = local.normalized()
	var points := PackedVector3Array()
	var mesh := piece.mesh
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices = arrays[Mesh.ARRAY_VERTEX]
		if vertices == null:
			continue
		var count: int = vertices.size()
		var triangles: PackedInt32Array
		var indices = arrays[Mesh.ARRAY_INDEX]
		if indices == null:
			triangles.resize(count)
			for vertex in count:
				triangles[vertex] = vertex
		else:
			triangles = indices
		for corner in range(0, triangles.size() - 2, 3):
			var a: Vector3 = vertices[triangles[corner]]
			var b: Vector3 = vertices[triangles[corner + 1]]
			var c: Vector3 = vertices[triangles[corner + 2]]
			var da := local.dot(a)
			var db := local.dot(b)
			var dc := local.dot(c)
			if (da > 0.0 and db > 0.0 and dc > 0.0) \
					or (da < 0.0 and db < 0.0 and dc < 0.0):
				continue
			# The two edges this triangle loses to the blade, in the plane.
			for pair in [[a, da, b, db], [b, db, c, dc], [c, dc, a, da]]:
				var p0: Vector3 = pair[0]
				var d0: float = pair[1]
				var p1: Vector3 = pair[2]
				var d1: float = pair[3]
				if (d0 > 0.0 and d1 > 0.0) or (d0 < 0.0 and d1 < 0.0) or is_equal_approx(d0, d1):
					continue
				points.append(p0.lerp(p1, d0 / (d0 - d1)))
	if points.size() < 3:
		return
	# Order the crossings around the middle of the section and fill it with a fan.
	var centre := Vector3.ZERO
	for point in points:
		centre += point
	centre /= float(points.size())
	centre -= local * local.dot(centre)
	var axis_a := Vector3.UP
	var axis_b := local.cross(axis_a)
	if axis_b.length_squared() < 0.001:
		axis_b = Vector3.RIGHT
	axis_b = axis_b.normalized()
	var ordered: Array = Array(points)
	ordered.sort_custom(func(left, right):
		var la := atan2(left.dot(axis_a), left.dot(axis_b))
		var ra := atan2(right.dot(axis_a), right.dot(axis_b))
		return la < ra)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in ordered.size():
		var next: Vector3 = ordered[(index + 1) % ordered.size()]
		for vertex in [centre, ordered[index] as Vector3, next]:
			tool.set_normal(local)
			tool.add_vertex(vertex - local * 0.02)
	var meat := StandardMaterial3D.new()
	meat.albedo_color = Color("3a1214")
	meat.roughness = 0.5
	meat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var slab := MeshInstance3D.new()
	slab.name = "CutFace"
	slab.mesh = tool.commit()
	slab.material_override = meat
	piece.add_child(slab)


static func _holder(visual: Node3D, frame: Transform3D) -> Node3D:
	var holder := Node3D.new()
	holder.name = "SplitBody"
	visual.add_child(holder)
	holder.top_level = true
	holder.global_transform = frame
	return holder


## A piece turning over where it stands: it tips about its own base - the point
## of it already on the floor - so its feet never swing through the other half and
## the piece never lifts off the ground. Gravity does the first half of the turn
## and the weight of it the rest, and the last step is it rocking back a degree as
## it settles.
static func _fall(holder: Node3D, frame: Transform3D, piece: MeshInstance3D,
		force: Vector3, degrees: float, delay: float, lean: float) -> void:
	var push := Vector3(force.x, 0.0, force.z)
	if push.length_squared() < 0.001:
		push = Vector3.FORWARD
	push = push.normalized()
	var axis := Vector3.UP.cross(push)
	if axis.length_squared() < 0.001:
		axis = Vector3.RIGHT
	axis = (Basis(push, lean) * axis.normalized()).normalized()
	# The base: the lowest point of the piece at the death pose, on the floor.
	var base := frame * _lowest_point(piece)
	var ground := _ground_at(holder, base)
	var full := deg_to_rad(degrees)
	var tween := holder.create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_method(_turn.bind(holder, piece, frame, axis, base, ground),
		0.0, full * 0.45, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_method(_turn.bind(holder, piece, frame, axis, base, ground),
		full * 0.45, full, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_method(_turn.bind(holder, piece, frame, axis, base, ground),
		full, full * 0.96, 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


static func _turn(angle: float, holder: Node3D, piece: MeshInstance3D,
		frame: Transform3D, axis: Vector3, base: Vector3, ground: float) -> void:
	if not is_instance_valid(holder) or not is_instance_valid(piece):
		return
	var hinge := Transform3D(Basis(axis, angle), base) \
		* Transform3D(Basis.IDENTITY, -base) * frame
	# The lowest point is held on the floor through the whole turn: a piece of
	# corpse tips over its own edge, it does not hover while it swings.
	var lowest := _lowest_world(piece, hinge)
	holder.global_transform = Transform3D(hinge.basis,
		hinge.origin + Vector3.UP * (ground - lowest))


## The piece's lowest vertex in its own frame - where it touches the floor.
static func _lowest_point(piece: MeshInstance3D) -> Vector3:
	var lowest := Vector3.ZERO
	var found := false
	var mesh := piece.mesh
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices = arrays[Mesh.ARRAY_VERTEX]
		if vertices == null:
			continue
		for vertex in vertices.size():
			var point: Vector3 = vertices[vertex]
			if not found or point.y < lowest.y:
				lowest = point
				found = true
	return lowest


## The lowest point of the piece under a whole transform, in world space.
static func _lowest_world(piece: MeshInstance3D, xform: Transform3D) -> float:
	var lowest := INF
	var mesh := piece.mesh
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices = arrays[Mesh.ARRAY_VERTEX]
		if vertices == null:
			continue
		for vertex in vertices.size():
			lowest = minf(lowest, (xform * (vertices[vertex] as Vector3)).y)
	return lowest if lowest < INF else 0.0


## The bones that own everything above the cut: every bone whose origin is above
## it, plus everything hanging off those bones (a jaw, a hand, a slung club).
static func _upper_bones(skeleton: Skeleton3D, cut_y: float) -> Dictionary:
	var owned := {}
	for index in skeleton.get_bone_count():
		var origin: Vector3 = (skeleton.get_global_transform()
			* skeleton.get_bone_global_pose(index)).origin
		if origin.y > cut_y:
			owned[index] = true
	var changed := true
	while changed:
		changed = false
		for index in skeleton.get_bone_count():
			if owned.has(index):
				continue
			var parent := skeleton.get_bone_parent(index)
			if parent >= 0 and owned.has(parent):
				owned[index] = true
				changed = true
	return owned


static func _tag(skeleton: Skeleton3D, owned: Dictionary) -> String:
	var names: Array[String] = []
	for index in owned:
		names.append(skeleton.get_bone_name(int(index)))
	names.sort()
	return ",".join(names)


## The corpse's stump: every bone the piece took collapses onto the cut, so the
## body ends there and nothing above it is drawn.
static func _stump(skeleton: Skeleton3D, owned: Dictionary, cut: Vector3) -> void:
	var bones := PackedInt32Array()
	for index in owned:
		bones.append(int(index))
	var point := skeleton.get_global_transform().affine_inverse() * cut
	var stump := SeveredHead.Stump.new()
	stump.name = "BodyStump"
	stump.bones = bones
	stump.point = point
	skeleton.add_child(stump)
	stump.enforce()


## A body opened through the middle is the wettest thing in the game after a
## head: a fountain at the cut, and the guts on the floor under it.
static func _wound(visual: Node3D, at: Vector3, push: Vector3, damage: float) -> void:
	BloodFx.arterial(visual, at, push, maxf(damage, 30.0), 1.3)
	_spill(visual, at, push, maxf(damage, 30.0))


## The floor under a point in the body's own world, or a body's own drop when the
## ray finds nothing (a scene with no ground under it).
static func _ground_at(visual: Node3D, point: Vector3) -> float:
	if not is_instance_valid(visual) or not visual.is_inside_tree():
		return point.y - 0.9
	var query := PhysicsRayQueryParameters3D.new()
	query.from = point + Vector3.UP * 1.4
	query.to = point - Vector3.UP * 3.0
	query.collision_mask = WORLD_MASK
	var hit := visual.get_world_3d().direct_space_state.intersect_ray(query)
	return (hit.position as Vector3).y if not hit.is_empty() else point.y - 0.9


## The head the body carries, or a human's worth above it when the rig does not
## say (the primitive rigs have no bones to ask).
static func _head_of(visual: Node3D, skeleton: Skeleton3D) -> Vector3:
	var head := skeleton.get_global_transform().origin + Vector3.UP * 1.6
	if visual.has_method("head_hitbox_center"):
		var point: Variant = visual.call("head_hitbox_center")
		if point is Vector3 and (point as Vector3).is_finite():
			head = point
	return head


## The guts: a heap of dark coils and offal on the floor under the cut, soaked,
## with the blood already pooled around it.
static func _spill(visual: Node3D, cut: Vector3, force: Vector3, damage: float) -> void:
	var pile := Node3D.new()
	pile.name = "Entrails"
	visual.add_child(pile)
	pile.top_level = true
	var ground := _ground_at(visual, cut)
	pile.global_position = Vector3(cut.x, ground + 0.02, cut.z)
	# Old blood and tallow, not a butcher's window: near-black maroon, wet.
	var meat := Geo.material(Color("2b0c0d"), 0.0, 0.38)
	var gut := Geo.material(Color("391012"), 0.0, 0.32)
	var tallow := Geo.material(Color("452a22"), 0.0, 0.55)
	var push := Vector3(force.x, 0.0, force.z)
	if push.length_squared() < 0.001:
		push = Vector3.FORWARD
	push = push.normalized()
	var spread := push.cross(Vector3.UP).normalized()
	# Coils: a few loops of gut lying over each other, squashed and uneven.
	for index in COILS:
		var coil := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.024 + 0.009 * float(index)
		torus.outer_radius = 0.062 + 0.015 * float(index)
		torus.rings = 12
		torus.ring_segments = 7
		coil.mesh = torus
		coil.material_override = gut if index % 2 == 0 else tallow
		coil.scale = Vector3(1.0, 0.55 + 0.1 * float(index), 0.8)
		coil.position = spread * (0.045 * float(index) - 0.06) \
			+ push * (0.07 * float(index % 2)) + Vector3.UP * (0.03 + 0.015 * float(index))
		coil.rotation = Vector3(PI * 0.5 + 0.3 * float(index), 0.9 * float(index),
			0.35 + 0.2 * float(index))
		pile.add_child(coil)
	# Offal: liver, kidney, heart - dark lumps under the loops.
	for index in LUMPS:
		var lump := Geo.sphere(pile, 0.07 - 0.014 * float(index),
			spread * (0.09 - 0.08 * float(index)) + push * (0.05 * float(index))
				+ Vector3.UP * 0.04,
			meat, Vector3(1.0, 0.5, 1.15))
		lump.rotation = Vector3(0.4 * float(index), 1.3 * float(index), 0.3)
	# A rope of gut trailing out of the heap into the pool.
	for index in 2:
		var start := spread * (-0.14 + 0.26 * float(index)) + Vector3.UP * 0.04
		var finish := start + push * (0.24 + 0.09 * float(index)) \
			+ spread * (0.10 - 0.20 * float(index))
		finish.y = 0.02
		Geo.beam(pile, start, finish, 0.016, gut, 6)
	BloodFx.stain_projectile(pile, damage)
