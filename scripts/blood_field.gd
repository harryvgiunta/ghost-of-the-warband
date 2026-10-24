extends Node3D
## Owns every blood stain in one scene: surface patches, body and weapon
## coatings, and the short-lived spray bursts. Stains live for 60 seconds,
## fade over the last three, and are recycled oldest-first when a busy fight
## exceeds the render budget. Created lazily by `BloodFx.field_for`.

const BloodFx = preload("res://scripts/blood_fx.gd")

const PATCH_SEGMENTS := 12
const PATCH_RINGS := 2
const MAX_BURSTS := 10
const MAX_BODY_STAINS := 10
const MAX_WEAPON_STAINS := 8
const GROUND_MASK := 1
const PATCH_LIFT := 0.012

var max_surface_stains := 160
var lifetime := BloodFx.LIFETIME
var _stains: Array[Dictionary] = []
var _bursts: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _query := PhysicsRayQueryParameters3D.new()

func _ready() -> void:
	_rng.seed = 0xB100D
	set_process(true)

func _process(delta: float) -> void:
	advance(delta)

# --- public field API ------------------------------------------------------

## Directional spray at a real blade/projectile contact plus a splat when the
## blow stops against nearby scenery. Body blood comes from `wound`.
func impact(at: Vector3, direction: Vector3, amount: float, headshot: bool) -> void:
	var dir := direction
	if dir.length_squared() < 0.000001:
		dir = Vector3.UP
	dir = dir.normalized()
	_spawn_burst(at, dir, amount, 1.0)
	var hit := _ray(at - dir * 0.02, at + dir * 0.55, GROUND_MASK)
	if hit.is_empty():
		return
	var normal: Vector3 = hit.normal
	if absf(normal.y) < 0.72:
		_spawn_patch(hit.position, normal, 0.20 + minf(amount, 50.0) * 0.006, false)

## Damage that actually landed: body coating, floor spatter, and the death
## pool. `rig` may be null for a target with no visible body.
func wound(rig: Node3D, at: Vector3, amount: float, headshot: bool,
		lethal: bool, scale: float) -> void:
	var size_scale := clampf(scale, 0.35, 2.5)
	if is_instance_valid(rig):
		_stain_body(rig, at, amount, headshot, lethal, size_scale)
	var radius := clampf(0.14 + amount * 0.0075, 0.16, 0.62) * size_scale
	_ground_splat(at, radius)
	if lethal:
		_spawn_pool(at, size_scale)
		_spawn_burst(at + Vector3(0.0, 0.12 * size_scale, 0.0), Vector3.UP,
			maxf(amount, 24.0) * 1.6, size_scale * 1.25, 0.55)

## Wet coating on the blade that dealt the blow. Parented to the weapon node so
## it tracks every swing and socket change.
func stain_weapon(anchor: Node3D, amount: float, scale: float) -> void:
	if not is_instance_valid(anchor):
		return
	var box := _anchor_bounds(anchor)
	if box.size.length_squared() < 0.000001:
		return
	var center := box.get_center()
	var axis := 2
	if box.size.x >= box.size.y and box.size.x >= box.size.z:
		axis = 0
	elif box.size.y >= box.size.z:
		axis = 1
	var tip := Vector3.ZERO
	var component: float = center[axis]
	tip[axis] = -1.0 if component < 0.0 else 1.0
	var thin := 0
	for candidate in 3:
		if candidate == axis:
			continue
		if thin == axis or box.size[candidate] < box.size[thin]:
			thin = candidate
	var wide := 3 - axis - thin
	var thin_axis := Vector3.ZERO
	thin_axis[thin] = 1.0
	var wide_axis := Vector3.ZERO
	wide_axis[wide] = 1.0
	var blade_length: float = box.size[axis]
	var blade_value = anchor.get("blade_length") if "blade_length" in anchor else null
	if blade_value != null:
		blade_length = maxf(float(blade_value), 0.05)
	# Blade-sized droplets rather than whole-hilt AABB fractions.
	var droplet := clampf(blade_length * 0.026, 0.009, 0.024) * scale
	var lateral := clampf(blade_length * 0.045, 0.012, 0.055)
	# Half-thickness of the blade plus the flattened blob's own half-thickness:
	# the coating must sit proud of the steel, not inside it.
	var surface := clampf(blade_length * 0.030, 0.012, 0.026)
	var droplet_count := 3
	if amount >= 22.0:
		droplet_count += 1
	if amount >= 42.0:
		droplet_count += 1
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in droplet_count:
		var side := 1.0 if index % 2 == 0 else -1.0
		var normal := thin_axis * side
		var radius := droplet * _rng.randf_range(0.7, 1.3)
		var side_offset := (1.0 if _rng.randf() < 0.5 else -1.0) \
			* _rng.randf_range(0.35, 0.85)
		var position := tip * blade_length * _rng.randf_range(0.14, 0.46) \
			+ wide_axis * side_offset * lateral \
			+ normal * surface
		var size := Vector3(radius, radius * 0.22, radius * _rng.randf_range(0.8, 1.5))
		tool.append_from(BloodFx.blot_mesh(), 0,
			Transform3D(_basis_from_y(normal) * Basis.from_scale(size), position))
	# One elongated smear on the blade's flat reads as a dragged cut.
	var smear_length := blade_length * _rng.randf_range(0.26, 0.46)
	var smear_width := lateral * _rng.randf_range(1.4, 2.2)
	var smear_side := 1.0 if _rng.randf() < 0.5 else -1.0
	var smear_normal := thin_axis * smear_side
	var smear := Transform3D(
		_basis_yz(smear_normal, tip) * Basis.from_scale(
			Vector3(smear_width, 0.004, smear_length)),
		tip * blade_length * _rng.randf_range(0.16, 0.34) \
			+ wide_axis * _rng.randf_range(0.15, 0.5) * lateral * smear_side \
			+ smear_normal * surface)
	tool.append_from(BloodFx.blot_mesh(), 0, smear)
	var mesh := tool.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var node := MeshInstance3D.new()
	node.name = "BloodCoating"
	node.set_meta("blood_stain", "coating")
	node.mesh = mesh
	node.material_override = BloodFx.blot_material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	anchor.add_child(node)
	node.position = center
	_register_stain(node, anchor, "group", MAX_WEAPON_STAINS)

func surface_stain_count() -> int:
	var count := 0
	for stain in _stains:
		if stain.owner == null and is_instance_valid(stain.node):
			count += 1
	return count

func stain_count() -> int:
	return _stains.size()

func burst_count() -> int:
	return _bursts.size()

func clear_all() -> void:
	for stain in _stains:
		if is_instance_valid(stain.node):
			(stain.node as Node).queue_free()
	for burst in _bursts:
		if is_instance_valid(burst.node):
			(burst.node as Node).queue_free()
	_stains.clear()
	_bursts.clear()

# --- lifetime --------------------------------------------------------------

func advance(delta: float) -> void:
	for index in range(_stains.size() - 1, -1, -1):
		var stain: Dictionary = _stains[index]
		var node = stain.node
		if not is_instance_valid(node):
			_stains.remove_at(index)
			continue
		stain.age = float(stain.age) + delta
		var remaining := float(stain.life) - float(stain.age)
		if remaining <= BloodFx.FADE_SECONDS:
			_apply_fade(stain, clampf(remaining / BloodFx.FADE_SECONDS, 0.0, 1.0))
		if remaining <= 0.0:
			(node as Node).queue_free()
			_stains.remove_at(index)
	for index in range(_bursts.size() - 1, -1, -1):
		var burst: Dictionary = _bursts[index]
		burst.age = float(burst.age) + delta
		if not is_instance_valid(burst.node) or float(burst.age) >= float(burst.life):
			if is_instance_valid(burst.node):
				(burst.node as Node).queue_free()
			_bursts.remove_at(index)

func _apply_fade(stain: Dictionary, factor: float) -> void:
	var node = stain.node
	if not is_instance_valid(node):
		return
	if str(stain.kind) == "patch":
		(node as GeometryInstance3D).transparency = 1.0 - factor
	else:
		(node as Node3D).scale = (stain.scale as Vector3) * maxf(factor, 0.001)

func _register_stain(node: Node, stain_owner: Node, kind: String, cap: int) -> void:
	var entry := {"node": node, "owner": stain_owner, "kind": kind, "age": 0.0,
		"life": lifetime, "scale": (node as Node3D).scale if node is Node3D else Vector3.ONE}
	_stains.append(entry)
	_enforce_cap(stain_owner, cap)

func _enforce_cap(stain_owner: Node, cap: int) -> void:
	var count := 0
	for stain in _stains:
		if stain.owner == stain_owner and is_instance_valid(stain.node):
			count += 1
	var excess := count - cap
	var index := 0
	while excess > 0 and index < _stains.size():
		var stain: Dictionary = _stains[index]
		if stain.owner != stain_owner:
			index += 1
			continue
		if is_instance_valid(stain.node):
			(stain.node as Node).queue_free()
		_stains.remove_at(index)
		excess -= 1

# --- body and weapon stains ------------------------------------------------

func _stain_body(rig: Node3D, at: Vector3, amount: float, headshot: bool,
		lethal: bool, scale: float) -> void:
	var anchor := _attach_point(rig, at)
	var anchor_node := anchor.parent as Node3D
	var anchor_xform: Transform3D = anchor.world
	var root_origin: Vector3 = anchor.local
	var count := 2
	if amount >= 20.0:
		count += 2
	if headshot:
		count += 2
	if lethal:
		count += 4
	var base_radius := clampf(0.014 + amount * 0.0014, 0.016, 0.062) * scale
	# Place the wet blotches on the body's outer shell. A raycast would return
	# the physics capsule, which is wider than the devil and narrower than the
	# sentinel; the scale-derived shell tracks every rig type.
	var shell := 0.23 * scale
	var to_local := anchor_xform.basis.inverse()
	var down_local := (to_local * Vector3.DOWN).normalized()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var first_local := Vector3.ZERO
	for index in count:
		var direction := Vector3(_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-0.3, 0.9) if headshot else _rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0))
		if direction.length_squared() < 0.0001:
			direction = Vector3.UP
		direction = direction.normalized()
		var point := at + direction * shell * _rng.randf_range(0.78, 1.2)
		var local_point := anchor_xform.affine_inverse() * point
		var local_normal := (to_local * direction).normalized()
		if index == 0:
			first_local = local_point
		var radius := base_radius * _rng.randf_range(0.55, 1.2)
		var size := Vector3(radius, radius * 0.45, radius * _rng.randf_range(0.8, 1.4))
		var blob := Transform3D(_basis_from_y(local_normal) * Basis.from_scale(size),
			local_point - root_origin + local_normal * 0.003)
		tool.append_from(BloodFx.blot_mesh(), 0, blob)
	if scale >= 0.7 and (amount >= 12.0 or lethal):
		var length := base_radius * _rng.randf_range(2.4, 5.4)
		var drip := Transform3D(_basis_from_y(down_local),
			first_local - root_origin + down_local * length * 0.5)
		drip.basis = drip.basis * Basis.from_scale(
			Vector3(base_radius * 0.32, length, base_radius * 0.32))
		tool.append_from(BloodFx.drip_mesh(), 0, drip)
	var mesh := tool.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var node := MeshInstance3D.new()
	node.name = "BloodWound"
	node.set_meta("blood_stain", "wound")
	node.mesh = mesh
	node.material_override = BloodFx.blot_material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	anchor_node.add_child(node)
	node.position = root_origin
	_register_stain(node, rig, "group", MAX_BODY_STAINS)

func _attach_point(rig: Node3D, at: Vector3) -> Dictionary:
	var skeleton := _find_skeleton(rig)
	if skeleton != null:
		var best := -1
		var best_distance := INF
		for index in skeleton.get_bone_count():
			var bone_origin: Vector3 = skeleton.get_bone_global_pose(index).origin
			var distance := (skeleton.global_transform * bone_origin).distance_squared_to(at)
			if distance < best_distance:
				best_distance = distance
				best = index
		if best >= 0 and best_distance < 9.0:
			var bone_world: Transform3D = skeleton.global_transform \
				* skeleton.get_bone_global_pose(best)
			var attachment := BoneAttachment3D.new()
			attachment.name = "BloodBone"
			attachment.bone_name = skeleton.get_bone_name(best)
			skeleton.add_child(attachment)
			return {"parent": attachment,
				"local": bone_world.affine_inverse() * at, "world": bone_world}
	return {"parent": rig, "local": rig.to_local(at), "world": rig.global_transform}

func _find_skeleton(rig: Node3D) -> Skeleton3D:
	if rig is Skeleton3D:
		return rig as Skeleton3D
	var found := rig.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	return found[0] as Skeleton3D

func _anchor_bounds(anchor: Node3D) -> AABB:
	var combined := AABB()
	var first := true
	for node in anchor.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var local: AABB = anchor.global_transform.affine_inverse() \
			* mesh_node.global_transform * mesh_node.get_aabb()
		if first:
			combined = local
			first = false
		else:
			combined = combined.merge(local)
	return combined

func _basis_from_y(up: Vector3) -> Basis:
	var y := up.normalized()
	if y.length_squared() < 0.0001:
		y = Vector3.UP
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

func _basis_yz(y_dir: Vector3, z_dir: Vector3) -> Basis:
	var y := y_dir.normalized()
	if y.length_squared() < 0.0001:
		y = Vector3.UP
	var z := z_dir - y * z_dir.dot(y)
	if z.length_squared() < 0.0001:
		z = y.cross(Vector3.RIGHT)
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)

# --- floor patches ---------------------------------------------------------

func _ground_splat(at: Vector3, radius: float) -> void:
	var offset := Vector3(_rng.randf_range(-0.20, 0.20), 0.0,
		_rng.randf_range(-0.20, 0.20))
	var hit := _ray(at + Vector3(0.0, 0.8, 0.0) + offset,
		at + Vector3(0.0, -3.0, 0.0) + offset, GROUND_MASK)
	if hit.is_empty():
		return
	var normal: Vector3 = hit.normal
	if normal.y < 0.42:
		return
	_spawn_patch(hit.position, normal, radius, false)

func _spawn_pool(at: Vector3, scale: float) -> void:
	var hit := _ray(at + Vector3(0.0, 0.6, 0.0), at + Vector3(0.0, -3.0, 0.0),
		GROUND_MASK)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.35:
		return
	var pool := _spawn_patch(hit.position, hit.normal, 0.46 * scale, true)
	pool.scale = Vector3.ONE * 0.30
	var tween := pool.create_tween()
	tween.tween_property(pool, "scale", Vector3.ONE, 0.95) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _spawn_patch(center: Vector3, normal: Vector3, radius: float,
		pool: bool) -> MeshInstance3D:
	var variant := _rng.randi() % BloodFx.SPLAT_VARIANTS
	var mesh := _conform_patch(center, normal, radius, variant * 37 + _rng.randi() % 97)
	var patch := MeshInstance3D.new()
	patch.name = "BloodPool" if pool else "BloodSplat"
	patch.set_meta("blood_stain", "pool" if pool else "splat")
	patch.mesh = mesh
	patch.material_override = BloodFx.pool_material() if pool \
		else BloodFx.patch_material(variant)
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	patch.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	patch.position = center
	add_child(patch)
	_register_stain(patch, null, "patch", max_surface_stains)
	return patch

## Builds a small radial patch whose vertices are dropped onto the real surface
## so blood follows slopes and steps instead of clipping through the ground.
func _conform_patch(center: Vector3, normal: Vector3, radius: float,
		phase_seed: int) -> ArrayMesh:
	var up := normal.normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length_squared() < 0.001:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	var back := side.cross(up).normalized()
	var phase := float(phase_seed % 628) * 0.01
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.append(Vector3.ZERO)
	normals.append(up)
	uvs.append(Vector2(0.5, 0.5))
	var ring_starts: Array[int] = []
	for ring in range(1, PATCH_RINGS + 1):
		var fraction := float(ring) / float(PATCH_RINGS)
		ring_starts.append(vertices.size())
		for segment in PATCH_SEGMENTS:
			var angle := TAU * float(segment) / float(PATCH_SEGMENTS) + phase
			var tangent := side * cos(angle) + back * sin(angle)
			var target := center + tangent * radius * fraction
			var hit := _ray(target + up * 0.9, target - up * 0.75, GROUND_MASK)
			var point := target
			if not hit.is_empty():
				point = (hit.position as Vector3) + up * PATCH_LIFT
			else:
				point += up * PATCH_LIFT
			vertices.append(point - center)
			normals.append(up)
			uvs.append(Vector2(0.5, 0.5) + Vector2(cos(angle), sin(angle)) * 0.5 * fraction)
	var first_ring := ring_starts[0]
	for segment in PATCH_SEGMENTS:
		indices.append(0)
		indices.append(first_ring + segment)
		indices.append(first_ring + (segment + 1) % PATCH_SEGMENTS)
	for ring in range(1, PATCH_RINGS):
		var inner := ring_starts[ring - 1]
		var outer := ring_starts[ring]
		for segment in PATCH_SEGMENTS:
			var next := (segment + 1) % PATCH_SEGMENTS
			indices.append(inner + segment)
			indices.append(outer + segment)
			indices.append(inner + next)
			indices.append(inner + next)
			indices.append(outer + segment)
			indices.append(outer + next)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	if not is_inside_tree():
		return {}
	_query.from = from
	_query.to = to
	_query.collision_mask = mask
	_query.exclude = []
	return get_world_3d().direct_space_state.intersect_ray(_query)

# --- spray -----------------------------------------------------------------

func _spawn_burst(at: Vector3, direction: Vector3, amount: float, scale: float,
		up_bias: float = 0.0) -> void:
	while _bursts.size() >= MAX_BURSTS:
		var oldest: Dictionary = _bursts.pop_front()
		if is_instance_valid(oldest.node):
			(oldest.node as Node).queue_free()
	var burst := CPUParticles3D.new()
	burst.name = "BloodSpray"
	burst.one_shot = true
	burst.amount = clampi(int(round(8.0 + amount * 0.8)), 10, 56)
	burst.lifetime = _rng.randf_range(0.34, 0.62)
	burst.explosiveness = 0.95
	burst.direction = (direction + Vector3.UP * up_bias).normalized()
	burst.spread = 48.0
	burst.initial_velocity_min = 1.2 * scale
	burst.initial_velocity_max = 4.4 * scale
	burst.gravity = Vector3(0.0, -9.8, 0.0)
	burst.scale_amount_min = 0.006 * scale
	burst.scale_amount_max = 0.016 * scale
	burst.mesh = BloodFx.drop_mesh()
	burst.material_override = BloodFx.drop_material()
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst.color = Color(1.0, 1.0, 1.0, 1.0)
	burst.local_coords = false
	burst.position = at
	add_child(burst)
	burst.emitting = true
	_bursts.append({"node": burst, "age": 0.0, "life": burst.lifetime + 0.6})
