extends RefCounted
## Small shared mesh helpers. All geometry uses meters and Godot's Y-up convention.

static func material(color: Color, metallic: float = 0.0, roughness: float = 0.8) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = metallic
	result.roughness = roughness
	return result

static func mesh_node(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	parent.add_child(node)
	return node

static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh_node(parent, mesh, mat, pos)

static func sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material, stretch: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var node := mesh_node(parent, mesh, mat, pos)
	node.scale = stretch
	return node

static func cylinder(parent: Node3D, bottom: float, top: float, height: float, pos: Vector3, mat: Material, sides: int = 12) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = sides
	return mesh_node(parent, mesh, mat, pos)

static func beam(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material, sides: int = 8) -> MeshInstance3D:
	var node := cylinder(parent, radius, radius, 1.0, Vector3.ZERO, mat, sides)
	place_beam(node, a, b)
	return node

static func place_beam(node: Node3D, a: Vector3, b: Vector3) -> void:
	var delta := b - a
	var length := maxf(delta.length(), 0.0001)
	var up := delta / length
	var side := Vector3.RIGHT
	if absf(up.dot(side)) > 0.95:
		side = Vector3.FORWARD
	var right := side.cross(up).normalized()
	var back := right.cross(up).normalized()
	node.transform = Transform3D(Basis(right, up * length, back), (a + b) * 0.5)

## Bake every mesh under `host` into one instance, one surface per material, and
## free the parts. A held weapon is a dozen little primitives - a branch is
## thirteen - and each `MeshInstance3D` is a draw call: thirteen draws for one
## length of wood is most of what a crowd of armed bodies costs the renderer.
##
## The parts' own transforms are baked, so what is drawn is exactly what stood
## there; only the number of draws changes. Nothing that keeps a handle on its
## parts may be baked (the bow's segments rotate as the string is drawn, the
## shield's fittings swap by variant), which is why this is called by the melee
## weapons and not by every prop. Returns the merged node, or null if `host` had
## no meshes under it.
static func bake_parts(host: Node3D) -> MeshInstance3D:
	var merged := ArrayMesh.new()
	var tools := {}
	var order: Array[Material] = []
	var stack: Array = [[host, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var node: Node3D = entry[0]
		var base: Transform3D = entry[1]
		for child in node.get_children():
			var part := child as Node3D
			if part == null:
				continue
			var local: Transform3D = base * part.transform
			var mesh_instance := part as MeshInstance3D
			if mesh_instance == null or mesh_instance.mesh == null:
				stack.append([part, local])
				continue
			var material: Material = mesh_instance.material_override
			if material == null and mesh_instance.mesh.get_surface_count() > 0:
				material = mesh_instance.mesh.surface_get_material(0)
			var tool: SurfaceTool = tools.get(material)
			if tool == null:
				tool = SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[material] = tool
				order.append(material)
			for surface in mesh_instance.mesh.get_surface_count():
				tool.append_from(mesh_instance.mesh, surface, local)
	for material in order:
		var tool: SurfaceTool = tools[material]
		tool.set_material(material)
		tool.commit(merged)
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()
	if merged.get_surface_count() == 0:
		return null
	var node := MeshInstance3D.new()
	node.name = "Model"
	node.mesh = merged
	host.add_child(node)
	return node
