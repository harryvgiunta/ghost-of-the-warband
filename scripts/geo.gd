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
