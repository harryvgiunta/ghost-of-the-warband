extends RefCounted
## Worn trinket presentation: one procedural necklace and two rings the
## equipment paperdoll can show on the character.
##
## The world rig keeps its stat-only trinkets (the wire carries ids, not art),
## but the equipment preview and the item-screenshot studio build the same
## pieces from this table so an icon shows exactly what the paperdoll shows.
## Nothing here mutates PlayerState or touches combat.

## One row per catalog trinket: band metal, optional stone and its shape.
## `glow` is an emissive tint for the story pieces (ember, lodestone).
const RING_STYLES := {
	"ring_copper": {"metal":"b0703f", "rough":0.45},
	"ring_silver": {"metal":"c7d2d2", "rough":0.30, "gem":"9fc4c6", "shape":"sphere", "size":0.0045},
	"ring_blood": {"metal":"c89b4a", "rough":0.35, "gem":"6d1420", "shape":"sphere", "size":0.007},
	"ring_dash": {"metal":"4d5a60", "rough":0.30, "gem":"72cbb6", "shape":"box", "size":0.006, "glow":"2f7f74"},
	"ring_health": {"metal":"c89b4a", "rough":0.32, "gem":"a32434", "shape":"sphere", "size":0.0065},
	"ring_ranged": {"metal":"6b5138", "rough":0.55, "gem":"2b2f36", "shape":"box", "size":0.0065},
	"ring_melee": {"metal":"5b6066", "rough":0.38, "gem":"8a8f96", "shape":"box", "size":0.006},
	"ring_swift": {"metal":"c7d2d2", "rough":0.26, "gem":"d7f2ee", "shape":"sphere", "size":0.0035},
	"ring_haste": {"metal":"d1a552", "rough":0.30, "gem":"e7b95f", "shape":"box", "size":0.006, "glow":"5a3c12"},
	"ring_vigor": {"metal":"8a6a3e", "rough":0.48, "gem":"6f9b57", "shape":"sphere", "size":0.0055},
	"ring_tide": {"metal":"3f7c6d", "rough":0.40},
	"ring_ward": {"metal":"2e3338", "rough":0.36, "gem":"7fb3c9", "shape":"sphere", "size":0.005, "glow":"1c3a48"},
	"ring_bounty": {"metal":"b58f42", "rough":0.34, "gem":"d8b96a", "shape":"disc", "size":0.0065},
	"ring_thrower": {"metal":"8a6236", "rough":0.40, "gem":"6aa9a0", "shape":"sphere", "size":0.005},
	"ring_echo": {"metal":"8d9494", "rough":0.28, "gem":"bcd8d4", "shape":"sphere", "size":0.004, "thin":0.55},
	"ring_ironhide": {"metal":"4a4d52", "rough":0.50},
	"ring_grit": {"metal":"5a4130", "rough":0.70},
}

const NECK_STYLES := {
	"neck_ember": {"cord":"3c2b20", "metal":"c88742", "gem":"ff8a45", "shape":"bead", "glow":"ff6a2a"},
	"neck_bone": {"cord":"4a382a", "metal":"cdbd93", "gem":"d8cfad", "shape":"knuckle"},
	"neck_shield": {"cord":"6d5834", "metal":"d8b45c", "gem":"e9d47f", "shape":"lodestone", "glow":"a07a1c"},
}


## Build the worn kit on a skeleton. Existing `TrinketArt_*` attachments are
## removed first, so calling this after every equip is a clean redraw.
static func apply(skeleton: Skeleton3D, kit: Dictionary) -> void:
	if skeleton == null:
		return
	clear(skeleton)
	var neck := str(kit.get("neck",""))
	if not neck.is_empty():
		_attach(skeleton,"neck_01","TrinketArt_Neck",_necklace(neck,_front_local(skeleton,"neck_01")))
	var ring1 := str(kit.get("ring1",""))
	if not ring1.is_empty():
		_attach(skeleton,"hand_l","TrinketArt_Ring1",_ring(ring1,_outward_local(skeleton,"hand_l",-1.0)))
	var ring2 := str(kit.get("ring2",""))
	if not ring2.is_empty():
		_attach(skeleton,"hand_r","TrinketArt_Ring2",_ring(ring2,_outward_local(skeleton,"hand_r",1.0)))


## A free-standing copy of one worn piece, for its item screenshot. The
## geometry is the same the paperdoll builds; only the attachment differs.
static func display(item_id: String, slot: String) -> Node3D:
	if slot == "neck":
		var neck := _necklace(item_id,Vector3(0.0,0.0,-1.0))
		if neck != null:
			# Stand the loop up so the cord and the pendant read from the front,
			# like a necklace laid out on its card.
			neck.position = Vector3.ZERO
			neck.rotation_degrees = Vector3(-78.0,22.0,0.0)
		return neck
	var ring := _ring(item_id,Vector3.RIGHT)
	if ring != null:
		ring.position = Vector3.ZERO
		ring.rotation_degrees = Vector3(62.0,0.0,18.0)
	return ring


## Remove the procedural pieces. Safe to call on a bare skeleton.
static func clear(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	for child in skeleton.get_children():
		if str(child.name).begins_with("TrinketArt_"):
			skeleton.remove_child(child)
			child.queue_free()


static func _attach(skeleton: Skeleton3D, bone: String, label: String, art: Node3D) -> void:
	if skeleton.find_bone(bone) < 0 or art == null:
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = label
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	attachment.add_child(art)


## Character front in a bone's own space, so a pendant hangs on the chest
## whatever the authored bone axes are.
static func _front_local(skeleton: Skeleton3D, bone: String) -> Vector3:
	var index := skeleton.find_bone(bone)
	if index < 0:
		return Vector3(0.0,0.0,-1.0)
	var basis := (skeleton.global_transform * skeleton.get_bone_global_pose(index)).basis
	return (basis.inverse() * Vector3(0.0,0.0,-1.0)).normalized()


## Outward side of a hand in its own space: +1 for the right hand's world +X,
## -1 for the left.
static func _outward_local(skeleton: Skeleton3D, bone: String, sign: float) -> Vector3:
	var index := skeleton.find_bone(bone)
	if index < 0:
		return Vector3(sign,0.0,0.0)
	var basis := (skeleton.global_transform * skeleton.get_bone_global_pose(index)).basis
	return (basis.inverse() * Vector3(sign,0.0,0.0)).normalized()


static func _ring(item_id: String, outward: Vector3) -> Node3D:
	var style: Dictionary = RING_STYLES.get(item_id, {})
	if style.is_empty():
		return null
	var root := Node3D.new()
	root.name = "RingArt"
	# Sit the band past the wrist on the hand bone's own Y axis.
	root.position = Vector3(0.0,0.058,0.0)
	var metal := Color(str(style.get("metal","b0703f")))
	var thin := float(style.get("thin",1.0))
	var band := TorusMesh.new()
	band.inner_radius = 0.0085
	band.outer_radius = 0.0085+0.0042*thin
	band.rings = 24
	band.ring_segments = 8
	var band_node := MeshInstance3D.new()
	band_node.mesh = band
	band_node.material_override = _material(metal,0.85,float(style.get("rough",0.35)))
	root.add_child(band_node)
	if style.has("gem"):
		var gem := _gem(str(style.get("shape","sphere")),float(style.get("size",0.006)),
			Color(str(style.get("gem","ffffff"))),str(style.get("glow","")))
		if gem != null:
			gem.position = outward * 0.016
			root.add_child(gem)
	return root


static func _necklace(item_id: String, front: Vector3) -> Node3D:
	var style: Dictionary = NECK_STYLES.get(item_id, {})
	if style.is_empty():
		return null
	var root := Node3D.new()
	root.name = "NeckArt"
	root.position = Vector3(0.0,0.045,0.0)
	var cord := TorusMesh.new()
	cord.inner_radius = 0.057
	cord.outer_radius = 0.0605
	cord.rings = 32
	cord.ring_segments = 8
	var cord_node := MeshInstance3D.new()
	cord_node.mesh = cord
	cord_node.material_override = _material(Color(str(style.get("cord","3c2b20"))),0.05,0.80)
	root.add_child(cord_node)
	var pendant := _gem(str(style.get("shape","bead")),0.018,
		Color(str(style.get("gem","ffffff"))),str(style.get("glow","")))
	if pendant != null:
		pendant.position = front * 0.068 + Vector3(0.0,-0.026,0.0)
		root.add_child(pendant)
	return root


static func _gem(shape: String, size: float, color: Color, glow: String) -> MeshInstance3D:
	var mesh: Mesh
	match shape:
		"box":
			var box := BoxMesh.new()
			box.size = Vector3(size,size,size)
			mesh = box
		"disc":
			var disc := CylinderMesh.new()
			disc.top_radius = size
			disc.bottom_radius = size
			disc.height = size*0.45
			disc.radial_segments = 16
			mesh = disc
		"knuckle":
			var knuckle := SphereMesh.new()
			knuckle.radius = size
			knuckle.height = size*1.7
			knuckle.radial_segments = 8
			knuckle.rings = 5
			mesh = knuckle
		"lodestone":
			var stone := CylinderMesh.new()
			stone.top_radius = size*0.72
			stone.bottom_radius = size*0.58
			stone.height = size*0.42
			stone.radial_segments = 12
			mesh = stone
		_:
			var sphere := SphereMesh.new()
			sphere.radius = size
			sphere.height = size*2.0
			sphere.radial_segments = 12
			sphere.rings = 6
			mesh = sphere
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(color,0.35 if shape in ["knuckle","lodestone"] else 0.65,
		0.22 if glow.is_empty() else 0.30,glow)
	return node


static func _material(color: Color, metallic: float, roughness: float, glow: String = "") -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if not glow.is_empty():
		material.emission_enabled = true
		material.emission = Color(glow)
		material.emission_energy_multiplier = 1.6
	return material
