class_name WorldScatter
extends RefCounted
## Packs instances into one MultiMesh per XZ chunk.
##
## Keeping each chunk's instances in a single MultiMesh gives cheap culling,
## visibility ranges tied to a local AABB, and instance colours for per-tree/
## per-clump tinting. Nodes are deterministically named and ordered so rebuilt
## worlds are byte-stable, and empty chunks produce no node at all.
##
## `instances` entries are `{"transform": Transform3D, "color": Color}` (colour
## optional, defaults to white).

const _DEFAULT_CHUNK := 16.0


static func batch(parent: Node3D, label: String, mesh: Mesh, material: Material,
		instances: Array[Dictionary], chunk_size: float, options: Dictionary = {}) -> int:
	if parent == null or mesh == null or instances.is_empty():
		return 0
	var chunk := maxf(0.25, chunk_size if chunk_size > 0.0 else _DEFAULT_CHUNK)
	var visible_end := float(options.get("visible_end", 0.0))
	var visible_margin := float(options.get("visible_margin", 0.0))
	var cast_shadow := bool(options.get("cast_shadow", true))
	var sort_instances := bool(options.get("sort", true))

	# Copy before ordering so callers keep their array untouched.
	var ordered: Array[Dictionary] = instances.duplicate()
	if sort_instances:
		ordered.sort_custom(_instance_before)

	var chunks: Dictionary = {}
	for entry in ordered:
		var transform_value = entry.get("transform")
		if not (transform_value is Transform3D):
			continue
		var origin: Vector3 = (transform_value as Transform3D).origin
		if not origin.is_finite():
			continue
		var key := Vector2i(floori(origin.x / chunk), floori(origin.z / chunk))
		if not chunks.has(key):
			chunks[key] = [] as Array[Dictionary]
		(chunks[key] as Array[Dictionary]).append(entry)
	if chunks.is_empty():
		return 0

	var keys: Array[Vector2i] = []
	for key in chunks.keys():
		keys.append(key)
	keys.sort_custom(_chunk_before)

	var safe_label := label if not label.is_empty() else "Scatter"
	var built := 0
	for key in keys:
		var entries: Array[Dictionary] = chunks[key] as Array[Dictionary]
		if entries.is_empty():
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = mesh
		multimesh.instance_count = entries.size()
		var bounds: AABB = AABB()
		var has_bounds := false
		for index in range(entries.size()):
			var entry: Dictionary = entries[index]
			var transform_value: Transform3D = entry["transform"]
			multimesh.set_instance_transform(index, transform_value)
			multimesh.set_instance_color(index, entry.get("color", Color.WHITE))
			# Cover every instance in the chunk; the mesh AABB is transformed, so
			# scaled/rotated instances cannot be frustum-culled early.
			var instance_bounds: AABB = transform_value * mesh.get_aabb()
			if has_bounds:
				bounds = bounds.merge(instance_bounds)
			else:
				bounds = instance_bounds
				has_bounds = true
		if has_bounds:
			multimesh.custom_aabb = bounds.grow(0.05)

		var node := MultiMeshInstance3D.new()
		node.name = "%s_%d_%d" % [safe_label, key.x, key.y]
		node.multimesh = multimesh
		node.material_override = material
		if visible_end > 0.0:
			node.visibility_range_end = visible_end
			node.visibility_range_end_margin = maxf(0.0, visible_margin)
		if not cast_shadow:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)
		built += 1
	return built


static func _instance_before(a: Dictionary, b: Dictionary) -> bool:
	var pa: Vector3 = (a["transform"] as Transform3D).origin
	var pb: Vector3 = (b["transform"] as Transform3D).origin
	if pa.x != pb.x:
		return pa.x < pb.x
	if pa.z != pb.z:
		return pa.z < pb.z
	if pa.y != pb.y:
		return pa.y < pb.y
	# Stable tie-breaker for instances sharing an origin (e.g. stacked cards).
	var ca: Color = a.get("color", Color.WHITE)
	var cb: Color = b.get("color", Color.WHITE)
	return ca.to_rgba32() < cb.to_rgba32()


static func _chunk_before(a: Vector2i, b: Vector2i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y
