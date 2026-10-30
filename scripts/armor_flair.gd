extends RefCounted
## One body's armour flair, on its rig: the livery dyed into its cloth, its device
## sewn or painted on its chest and back, a border along every open edge, its
## leather stained, its steel finished, its fittings re-cast, its bone treated,
## and its trophies hung on the pieces it wears.
##
## `Archer` makes one of these for a body whose look carries a `flair`
## (`WarbandFlair.profile_for`) and calls `dress()` whenever its kit changes. A
## body without one - the frontier ranger, an arena fighter, a clone, a keeper's
## item icon - never meets this file.
##
## How a surface takes a flair:
## - Each worn armour mesh is swapped, once per session per mesh, for a copy that
##   carries its skeleton rest-space positions in CUSTOM0 (`rest_mesh`). The
##   shader draws the livery in that space, so a design stays where it was put
##   while the skin deforms.
## - Each authored material in `ROLES` gets a per-body `ShaderMaterial` of
##   `armor_flair.gdshader` that mirrors the authored one and adds the flair.
##   Anything not in `ROLES` (skin, the naked shirt and shorts the look tints) is
##   left exactly as it was.
## - Each trophy is a merged mesh on a `BoneAttachment3D`, placed on the measured
##   outer surface of whatever is drawn at its anchor, and shown only while its
##   slot wears a real piece: trophies are part of the kit, not the man.

const ArmorData = preload("res://scripts/armor_data.gd")
const Trophies = preload("res://scripts/armor_trophies.gd")
const WarbandFlair = preload("res://scripts/warband/warband_flair.gd")
const SHADER = preload("res://scripts/world/shaders/armor_flair.gdshader")

## Surface roles, numbered as the shader numbers them.
const ROLE_CLOTH := 1
const ROLE_LINING := 2
const ROLE_OUTFIT := 3
const ROLE_LEATHER := 4
const ROLE_HIDE := 5
const ROLE_PLATE := 6
const ROLE_MAIL := 7
const ROLE_STEEL := 8
const ROLE_FITTINGS := 9
const ROLE_BONE := 10

## Which authored materials take a flair, and as what. `shade` darkens a role's
## darker cut so a dark strap stays darker than the leather beside it.
const ROLES := {
	# the imported ranger outfit is one atlas: green cloth, brown leather, metal
	"MI_Ranger": {"role": ROLE_OUTFIT},
	"MI_Ranger.001": {"role": ROLE_OUTFIT},
	"M_Armor_Cloth": {"role": ROLE_CLOTH},
	"M_Armor_Cloth_Dark": {"role": ROLE_LINING},
	"M_Armor_Leather": {"role": ROLE_LEATHER},
	"M_Armor_Leather_Dark": {"role": ROLE_LEATHER, "shade": 0.62},
	"M_Armor_Mail": {"role": ROLE_MAIL},
	"M_Armor_Plate": {"role": ROLE_PLATE},
	"M_Armor_Plate_Dark": {"role": ROLE_PLATE},
	"M_Armor_Steel_Edge": {"role": ROLE_STEEL},
	"M_Armor_Brass": {"role": ROLE_FITTINGS},
	"M_Armor_Trim": {"role": ROLE_FITTINGS},
	"Makeshift_Leather": {"role": ROLE_HIDE},
	"Makeshift_Bone": {"role": ROLE_BONE},
	"Makeshift_Antler": {"role": ROLE_BONE},
}
const PIECES := {"head": 0, "chest": 1, "hands": 2, "legs": 3, "feet": 4}
## The sets a surcoat goes over.
const SURCOAT_SETS := ["mail", "plate"]
const CHANNELS := [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1),
	Vector4(0.299, 0.587, 0.114, 0.0)]
const NO_EDGE := -10.0

## Where trophies hang, in the skeleton's rest space (metres, +Y up, the body
## faces +Z, its left is +X; arms out in a T at y 1.456). Only the left of a pair
## is written down: `_r` is its mirror. Every anchor names the slot whose piece
## carries it, the bone it rides, and the slots whose drawn surface it must sit
## outside.
##   point: from `at`, the outermost vertex within `reach` of the ray along `dir`
##          is the surface; the trophy sits `clear` past it, facing `out`, `up` up
##   ring:  round `axis` through the centre, the widest vertex within `half` of
##          the plane and inside `cap` is the surface; `edge` slides the centre
##          to the piece's own cuff or boot top
const ANCHORS := {
	"crown": {"type": "point", "slot": "head", "bone": "Head", "at": Vector3(0.0, 1.70, -0.025),
		"dir": Vector3(0.0, 1.0, 0.0), "reach": 0.045, "clear": -0.004,
		"out": Vector3(0.0, 0.0, 1.0), "up": Vector3(0.0, 1.0, 0.0), "surfaces": ["head"]},
	# feathers rise from a band at the temple: the frame is upside down so a
	# trophy that hangs from its knot stands up from it instead
	"temple_l": {"type": "point", "slot": "head", "bone": "Head", "at": Vector3(0.0, 1.73, -0.035),
		"dir": Vector3(0.94, 0.10, -0.32), "reach": 0.03, "clear": 0.002,
		"out": Vector3(0.94, 0.0, -0.32), "up": Vector3(0.0, -1.0, 0.38), "surfaces": ["head"]},
	"hip_l": {"type": "point", "slot": "chest", "bone": "pelvis", "at": Vector3(0.0, 1.0, -0.02),
		"dir": Vector3(0.93, 0.0, 0.36), "reach": 0.03, "clear": 0.004,
		"out": Vector3(0.93, 0.0, 0.36), "up": Vector3(0.0, 1.0, 0.0), "surfaces": ["chest", "legs"]},
	"shoulder_l": {"type": "point", "slot": "chest", "bone": "upperarm_l", "at": Vector3(0.25, 1.40, -0.065),
		"dir": Vector3(0.0, 1.0, 0.0), "reach": 0.03, "clear": 0.0,
		"out": Vector3(1.0, 0.0, 0.0), "up": Vector3(0.0, 1.0, 0.0), "surfaces": ["chest", "head"]},
	"thigh_l": {"type": "point", "slot": "legs", "bone": "thigh_l", "at": Vector3(0.09, 0.72, -0.036),
		"dir": Vector3(0.96, 0.0, 0.28), "reach": 0.03, "clear": 0.004,
		"out": Vector3(0.96, 0.0, 0.28), "up": Vector3(0.0, 1.0, 0.0), "surfaces": ["legs", "chest"]},
	"neck": {"type": "ring", "slot": "chest", "bone": "spine_03", "at": Vector3(0.0, 1.46, -0.02),
		"axis": Vector3(0.0, 1.0, 0.4), "half": 0.02, "cap": 0.17, "clear": 0.008,
		"out": Vector3(0.0, 0.0, 1.0), "surfaces": ["chest", "head"]},
	"wrist_l": {"type": "ring", "slot": "hands", "bone": "lowerarm_l", "at": Vector3(0.0, 1.456, -0.07),
		"axis": Vector3(1.0, 0.0, 0.0), "half": 0.015, "cap": 0.11, "clear": 0.004, "edge": "inner",
		"out": Vector3(0.0, 0.0, 1.0), "surfaces": ["hands", "chest"]},
	"ankle_l": {"type": "ring", "slot": "feet", "bone": "calf_l", "at": Vector3(0.09, 0.0, -0.036),
		"axis": Vector3(0.0, 1.0, 0.0), "half": 0.015, "cap": 0.13, "clear": 0.004, "edge": "top",
		"out": Vector3(0.0, 0.0, 1.0), "surfaces": ["feet", "legs"]},
}

## Rest-space copies of the shared armour meshes, keyed by source mesh.
static var _rest_meshes: Dictionary = {}
## Rest-space vertex positions per armour mesh name (every rig shares them).
static var _points: Dictionary = {}
## Per authored material: the mean luminance its role re-colours.
static var _stats: Dictionary = {}
## Per set and slot: the piece's open edges (`edges` in the shader).
static var _edges: Dictionary = {}
## Per mesh and anchor: how far out its surface is.
static var _reaches: Dictionary = {}

var _skeleton: Skeleton3D
var _armor_meshes: Dictionary
var _flair: Dictionary
var _trophy_mats: Dictionary
var _materials: Dictionary = {}
var _dressed: Dictionary = {}
var _trophies: Array = []
var _placed_for: Variant = null


func _init(skeleton: Skeleton3D, armor_meshes: Dictionary, flair: Dictionary) -> void:
	_skeleton = skeleton
	_armor_meshes = armor_meshes
	_flair = flair
	_trophy_mats = Trophies.materials(flair)
	_build_trophies()


## Bring the body's flair up to the kit it now wears. Called by the rig after
## every armour change, once the slot visibility is already applied.
func dress(pieces: Dictionary) -> void:
	for slot: String in ArmorData.SLOTS:
		var worn := int(pieces.get(slot, ArmorData.NONE))
		if _real_set(slot, worn):
			_dress_piece(slot, worn)
	if _placed_for != null and (_placed_for as Dictionary) == pieces:
		return
	_placed_for = pieces.duplicate()
	_place_trophies(pieces)


## The trophies currently hung, as `{anchor, kind, visible}` rows.
func trophies() -> Array:
	var out: Array = []
	for trophy: Dictionary in _trophies:
		out.append({"anchor": trophy["name"], "kind": trophy["kind"],
			"visible": (trophy["attachment"] as Node3D).visible, "node": trophy["attachment"]})
	return out


func _real_set(slot: String, set_index: int) -> bool:
	if set_index < 0 or set_index >= ArmorData.SET_IDS.size():
		return false
	if ArmorData.SET_IDS[set_index] == "naked":
		return false
	return not (_armor_meshes.get(slot, {}).get(set_index, []) as Array).is_empty()


# --- surfaces ---------------------------------------------------------------

func _dress_piece(slot: String, set_index: int) -> void:
	var key := "%s:%d" % [slot, set_index]
	if _dressed.has(key):
		return
	_dressed[key] = true
	for node: MeshInstance3D in _armor_meshes[slot][set_index]:
		var source := node.mesh
		if source == null:
			continue
		var count := source.get_surface_count()
		var actives: Array[Material] = []
		var overrides: Array[Material] = []
		for surface in count:
			actives.append(node.get_active_material(surface))
			overrides.append(node.get_surface_override_material(surface))
		node.mesh = rest_mesh(node)
		for surface in count:
			var authored := actives[surface] as BaseMaterial3D
			var spec: Dictionary = ROLES.get(str(authored.resource_name), {}) if authored != null else {}
			if spec.is_empty():
				node.set_surface_override_material(surface, overrides[surface])
				continue
			node.set_surface_override_material(surface, _material(authored, spec, slot, set_index))


## A copy of a skinned armour mesh that also carries each vertex's rest-space
## position in CUSTOM0. Built once per mesh and shared by every body.
static func rest_mesh(node: MeshInstance3D) -> ArrayMesh:
	var source := node.mesh
	if source.has_meta("flair_rest"):
		return source as ArrayMesh
	var key := source.get_instance_id()
	if _rest_meshes.has(key):
		return _rest_meshes[key]
	var out := ArrayMesh.new()
	out.resource_name = source.resource_name
	out.set_meta("flair_rest", true)
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var rest := PackedFloat32Array()
		rest.resize(vertices.size() * 3)
		for index in vertices.size():
			var at := node.transform * vertices[index]
			rest[index * 3] = at.x
			rest[index * 3 + 1] = at.y
			rest[index * 3 + 2] = at.z
		arrays[Mesh.ARRAY_CUSTOM0] = rest
		var flags := Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		if source.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS:
			flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, [], {}, flags)
		out.surface_set_material(surface, source.surface_get_material(surface))
		out.surface_set_name(surface, source.surface_get_name(surface))
	_rest_meshes[key] = out
	return out


func _material(authored: BaseMaterial3D, spec: Dictionary, slot: String, set_index: int) -> ShaderMaterial:
	var key := "%d:%s:%d" % [authored.get_instance_id(), slot, set_index]
	if _materials.has(key):
		return _materials[key]
	var role := int(spec["role"])
	var stats := material_stats(authored, role)
	var finish: Dictionary = WarbandFlair.FINISHES[clampi(int(_flair.get("finish", 0)), 0,
		WarbandFlair.FINISHES.size() - 1)]
	var material := ShaderMaterial.new()
	material.resource_name = "Flair_" + str(authored.resource_name)
	material.shader = SHADER
	material.set_shader_parameter("albedo", authored.albedo_color)
	material.set_shader_parameter("albedo_texture", authored.albedo_texture)
	material.set_shader_parameter("roughness", authored.roughness)
	material.set_shader_parameter("roughness_texture", authored.roughness_texture)
	material.set_shader_parameter("roughness_channel", CHANNELS[authored.roughness_texture_channel])
	material.set_shader_parameter("metallic", authored.metallic)
	material.set_shader_parameter("metallic_texture", authored.metallic_texture)
	material.set_shader_parameter("metallic_channel", CHANNELS[authored.metallic_texture_channel])
	material.set_shader_parameter("normal_enabled", authored.normal_enabled and authored.normal_texture != null)
	material.set_shader_parameter("normal_texture", authored.normal_texture)
	material.set_shader_parameter("normal_scale", authored.normal_scale)
	material.set_shader_parameter("role", role)
	material.set_shader_parameter("shade", float(spec.get("shade", 1.0)))
	material.set_shader_parameter("veil", float(stats["veil"]))
	material.set_shader_parameter("veil_alt", float(stats["veil_alt"]))
	material.set_shader_parameter("piece", int(PIECES[slot]))
	material.set_shader_parameter("edges", piece_edges(_armor_meshes, slot, set_index))
	material.set_shader_parameter("surcoat", bool(_flair.get("surcoat", false)) and slot == "chest"
		and ArmorData.SET_IDS[set_index] in SURCOAT_SETS)
	material.set_shader_parameter("field_color", _tone("field"))
	material.set_shader_parameter("charge_color", _tone("charge"))
	material.set_shader_parameter("thread_color", _tone("thread"))
	material.set_shader_parameter("thread_metal", float(_flair.get("thread_metal", 0.0)))
	material.set_shader_parameter("stain_color", _tone("leather"))
	material.set_shader_parameter("fittings_color", _tone("fittings"))
	material.set_shader_parameter("bone_color", _tone("bone"))
	material.set_shader_parameter("finish_tint", Color(str(finish["tint"])))
	material.set_shader_parameter("finish_rough", float(finish["rough"]))
	material.set_shader_parameter("finish_metal", float(finish["metal"]))
	material.set_shader_parameter("paint_color", _paint_for(role, stats, finish))
	material.set_shader_parameter("design", int(_flair.get("design", 0)))
	material.set_shader_parameter("motif", int(_flair.get("motif", 0)))
	material.set_shader_parameter("hem", int(_flair.get("hem", 0)))
	material.set_shader_parameter("seed", float(_flair.get("seed", 0.0)))
	_materials[key] = material
	return material


func _tone(key: String) -> Color:
	return Color(str(_flair.get(key, "#ffffff")))


## Paint has to read on what it is painted on: of the livery's colours, the
## charge if it stands off the surface, otherwise whichever stands off most.
func _paint_for(role: int, stats: Dictionary, finish: Dictionary) -> Color:
	var under := _tone("leather").get_luminance() if role == ROLE_HIDE \
		else float(stats["veil"]) * Color(str(finish["tint"])).get_luminance()
	var best := _tone("charge")
	if absf(best.get_luminance() - under) >= 0.3:
		return best
	var best_gap := -1.0
	for key in ["charge", "thread", "field"]:
		var tone := _tone(key)
		var gap := absf(tone.get_luminance() - under)
		if gap > best_gap:
			best_gap = gap
			best = tone
	return best


## The mean luminance of the texels a role re-colours (`veil`), and for the
## outfit atlas the same for its leather (`veil_alt`). Dividing the authored map
## by it keeps the weave and the grime and leaves the colour to the flair. The
## outfit is split by hue exactly as the shader splits it.
##
## Measured on the stored texel values, untouched: the Compatibility renderer
## hands the shader a texture, a material colour and a uniform in the same space
## (a 0.5 grey comes out 0.5 down all three), so the veil has to be in it too.
static func material_stats(authored: BaseMaterial3D, role: int) -> Dictionary:
	var key := "%d:%d" % [authored.get_instance_id(), role]
	if _stats.has(key):
		return _stats[key]
	var tint := authored.albedo_color
	var flat := maxf(_luma(tint), 0.0005)
	var result := {"veil": flat, "veil_alt": flat}
	var image := _image_of(authored.albedo_texture)
	if image != null:
		var metal_image: Image = null
		if role == ROLE_OUTFIT:
			metal_image = _image_of(authored.metallic_texture)
		var step := maxi(1, image.get_width() / 64)
		var sums := [0.0, 0.0, 0.0]
		var weights := [0.0, 0.0, 0.0]
		for y in range(0, image.get_height(), step):
			for x in range(0, image.get_width(), step):
				var c := image.get_pixel(x, y) * tint
				var lum := _luma(c)
				# the black between an atlas's islands is no texel of anything
				if lum < 0.02:
					continue
				if role != ROLE_OUTFIT:
					sums[0] += lum
					weights[0] += 1.0
					continue
				var metal := authored.metallic
				if metal_image != null:
					var texel := metal_image.get_pixel(x * metal_image.get_width() / image.get_width(),
						y * metal_image.get_height() / image.get_height())
					metal *= _channel(texel, authored.metallic_texture_channel)
				var bare := 1.0 - smoothstep(0.3, 0.6, metal)
				var green := smoothstep(0.16, 0.21, c.h) * (1.0 - smoothstep(0.46, 0.52, c.h)) \
					* smoothstep(0.15, 0.30, c.s) * bare
				var brown := maxf(1.0 - smoothstep(0.10, 0.14, c.h), smoothstep(0.93, 0.97, c.h)) \
					* smoothstep(0.25, 0.40, c.s) * bare * (1.0 - green)
				sums[1] += lum * green
				weights[1] += green
				sums[2] += lum * brown
				weights[2] += brown
		if role == ROLE_OUTFIT:
			if weights[1] > 0.0:
				result["veil"] = maxf(sums[1] / weights[1], 0.0005)
			if weights[2] > 0.0:
				result["veil_alt"] = maxf(sums[2] / weights[2], 0.0005)
		elif weights[0] > 0.0:
			result["veil"] = maxf(sums[0] / weights[0], 0.0005)
			result["veil_alt"] = result["veil"]
	_stats[key] = result
	return result


static func _image_of(texture: Texture2D) -> Image:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	return image


static func _channel(texel: Color, channel: int) -> float:
	var weights: Vector4 = CHANNELS[clampi(channel, 0, CHANNELS.size() - 1)]
	return texel.r * weights.x + texel.g * weights.y + texel.b * weights.z + texel.a * weights.w


static func _luma(c: Color) -> float:
	return c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722


## Where one set's piece ends, in rest space: the hem of a coat or the trousers,
## the end of a sleeve, the cuff of a glove, the top of a boot, the rim of a
## hood. Measured over the surfaces a flair re-colours, so a bare hand at the end
## of a leather sleeve is not mistaken for the sleeve.
static func piece_edges(armor_meshes: Dictionary, slot: String, set_index: int) -> Vector4:
	var key := "%s:%d" % [slot, set_index]
	if _edges.has(key):
		return _edges[key]
	var low := INF
	var high := -INF
	var outer := 0.0
	var inner := INF
	for node: MeshInstance3D in armor_meshes.get(slot, {}).get(set_index, []):
		if node.mesh == null:
			continue
		for surface in node.mesh.get_surface_count():
			var authored := node.get_active_material(surface)
			if authored == null or not ROLES.has(str(authored.resource_name)) \
					and not str(authored.resource_name).begins_with("Flair_"):
				continue
			var vertices: PackedVector3Array = node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var at := node.transform * vertex
				var side := absf(at.x)
				if slot != "chest" or side < 0.28:
					low = minf(low, at.y)
				high = maxf(high, at.y)
				if side > 0.30:
					outer = maxf(outer, side)
					inner = minf(inner, side)
	var edges := Vector4(NO_EDGE, NO_EDGE, NO_EDGE, NO_EDGE)
	match slot:
		"head", "legs":
			edges.x = low if low < INF else NO_EDGE
		"chest":
			edges.x = low if low < INF else NO_EDGE
			edges.z = outer if outer > 0.35 else NO_EDGE
		"hands":
			edges.w = inner if inner < INF else NO_EDGE
		"feet":
			edges.y = high if high > -INF else NO_EDGE
	_edges[key] = edges
	return edges


# --- trophies ---------------------------------------------------------------

func _build_trophies() -> void:
	for spec: Dictionary in _flair.get("trophies", []):
		var name := str(spec.get("anchor", ""))
		var anchor := anchor_spec(name)
		var kind := str(spec.get("kind", ""))
		if anchor.is_empty() or not kind in Trophies.KINDS:
			continue
		if _skeleton.find_bone(str(anchor["bone"])) < 0:
			continue
		var attachment := BoneAttachment3D.new()
		attachment.name = "Trophy_" + name
		attachment.bone_name = str(anchor["bone"])
		attachment.visible = false
		_skeleton.add_child(attachment)
		var holder := Node3D.new()
		holder.name = "Holder"
		attachment.add_child(holder)
		_trophies.append({"name": name, "kind": kind, "anchor": anchor, "attachment": attachment,
			"holder": holder, "mesh": null, "size": Vector2(-1.0, -1.0)})


## One anchor, the right of a pair mirrored from its left.
static func anchor_spec(name: String) -> Dictionary:
	if ANCHORS.has(name):
		return ANCHORS[name]
	if not name.ends_with("_r"):
		return {}
	var left := name.substr(0, name.length() - 2) + "_l"
	if not ANCHORS.has(left):
		return {}
	var spec: Dictionary = (ANCHORS[left] as Dictionary).duplicate()
	var flip := Vector3(-1.0, 1.0, 1.0)
	for key in ["at", "dir", "out", "axis"]:
		if spec.has(key):
			spec[key] = (spec[key] as Vector3) * flip
	spec["bone"] = str(spec["bone"]).trim_suffix("_l") + "_r" if str(spec["bone"]).ends_with("_l") \
		else spec["bone"]
	spec["side"] = -1.0
	return spec


func _place_trophies(pieces: Dictionary) -> void:
	for trophy: Dictionary in _trophies:
		var anchor: Dictionary = trophy["anchor"]
		var attachment: BoneAttachment3D = trophy["attachment"]
		var shown := _real_set(str(anchor["slot"]), int(pieces.get(str(anchor["slot"]), ArmorData.NONE)))
		var frame := Transform3D()
		var size := Vector2.ZERO
		if shown:
			var placed := _anchor_frame(anchor, pieces)
			shown = not placed.is_empty()
			if shown:
				frame = placed["frame"]
				size = placed["size"]
		attachment.visible = shown
		if not shown:
			continue
		var bone := _skeleton.find_bone(str(anchor["bone"]))
		(trophy["holder"] as Node3D).transform = _skeleton.get_bone_global_rest(bone).affine_inverse() * frame
		var mesh_node: MeshInstance3D = trophy["mesh"]
		var previous: Vector2 = trophy["size"]
		if mesh_node == null or absf(previous.x - size.x) > 0.002 or absf(previous.y - size.y) > 0.002:
			if mesh_node != null:
				mesh_node.queue_free()
			trophy["mesh"] = _build_trophy(trophy, size)
			trophy["size"] = size


func _build_trophy(trophy: Dictionary, size: Vector2) -> MeshInstance3D:
	var anchor: Dictionary = trophy["anchor"]
	var kind := str(trophy["kind"])
	var merged
	if str(trophy["name"]) == "neck":
		merged = Trophies.build_necklace(kind, _trophy_mats, size)
	else:
		merged = Trophies.build(kind, _trophy_mats, size, float(anchor.get("side", 1.0)))
	# Trophies cast no shadow: a skull's shadow on the hip it hangs from is acne
	# at this scale, and eight bodies' worth of small casters is not free.
	return merged.commit(trophy["holder"], "Trophy", false)


## Where an anchor's trophy goes for the kit now drawn: a rest-space frame and,
## for a ring, the measured cross-section it ties round. Empty when nothing drawn
## reaches the anchor, which hides the trophy rather than floating it.
func _anchor_frame(anchor: Dictionary, pieces: Dictionary) -> Dictionary:
	var at: Vector3 = anchor["at"]
	if anchor.has("edge"):
		var slot := str(anchor["slot"])
		var edges := piece_edges(_armor_meshes, slot, int(pieces.get(slot, ArmorData.NONE)))
		if str(anchor["edge"]) == "inner":
			if edges.w <= 0.0:
				return {}
			at.x = signf(at.x if at.x != 0.0 else float(anchor.get("side", 1.0))) * (edges.w + 0.03)
		else:
			if edges.y <= 0.0:
				return {}
			at.y = edges.y - 0.025
	var clear := float(anchor.get("clear", 0.0))
	if str(anchor["type"]) == "ring":
		var section := _section(anchor, at)
		if section.is_empty():
			return {}
		var size: Vector2 = section["size"] + Vector2(clear, clear)
		return {"frame": Transform3D(Basis(section["u"], section["axis"], section["v"]),
			section["centre"]), "size": size}
	var reach := -1.0
	for slot: String in anchor["surfaces"]:
		for set_index: int in _armor_meshes.get(slot, {}):
			for node: MeshInstance3D in _armor_meshes[slot][set_index]:
				if node.visible:
					reach = maxf(reach, _surface_reach(node, anchor, at))
	if reach <= 0.0:
		return {}
	var dir := (anchor["dir"] as Vector3).normalized()
	var up := (anchor["up"] as Vector3).normalized()
	var out := anchor["out"] as Vector3
	out = (out - up * out.dot(up)).normalized()
	return {"frame": Transform3D(Basis(up.cross(out).normalized(), up, out), at + dir * (reach + clear)),
		"size": Vector2.ZERO}


## The widest cross-section of anything drawn at a ring anchor: half width along
## the ring's first axis, half depth along its second, and where its centre is.
## A neck and a wrist are wider across than deep, so the ring that ties round them
## is an ellipse; a circle measured on the widest axis stood off the body as a
## hoop, and one on the narrow axis sank into it.
func _section(anchor: Dictionary, at: Vector3) -> Dictionary:
	var best := {}
	for slot: String in anchor["surfaces"]:
		for set_index: int in _armor_meshes.get(slot, {}):
			for node: MeshInstance3D in _armor_meshes[slot][set_index]:
				if not node.visible:
					continue
				var section := _ring_section(node, anchor, at)
				if section.is_empty():
					continue
				var span: Vector2 = section["size"]
				if best.is_empty() or maxf(span.x, span.y) > maxf((best["size"] as Vector2).x,
						(best["size"] as Vector2).y):
					best = section
	return best


## One mesh's cross-section round a ring anchor, or {} when it does not reach it.
static func _ring_section(node: MeshInstance3D, anchor: Dictionary, at: Vector3) -> Dictionary:
	var key := "ring|%s|%s" % [node.name, str(at.snapped(Vector3.ONE * 0.001))]
	if _reaches.has(key):
		return _reaches[key]
	var axis := (anchor["axis"] as Vector3).normalized()
	var u := axis.cross(Vector3(0.0, 0.0, 1.0))
	if u.length_squared() < 0.0001:
		u = axis.cross(Vector3.RIGHT)
	u = u.normalized()
	var v := u.cross(axis).normalized()
	var half := float(anchor["half"])
	var cap := float(anchor["cap"])
	var low_u := INF
	var high_u := -INF
	var low_v := INF
	var high_v := -INF
	for point in _rest_points(node):
		var offset := point - at
		var along := offset.dot(axis)
		if absf(along) > half:
			continue
		var du := offset.dot(u)
		var dv := offset.dot(v)
		if Vector2(du, dv).length() > cap:
			continue
		low_u = minf(low_u, du)
		high_u = maxf(high_u, du)
		low_v = minf(low_v, dv)
		high_v = maxf(high_v, dv)
	var result := {}
	if high_u > low_u and high_v > low_v:
		var centre_u := (low_u + high_u) * 0.5
		var centre_v := (low_v + high_v) * 0.5
		result = {"size": Vector2((high_u - low_u) * 0.5, (high_v - low_v) * 0.5),
			"centre": at + u * centre_u + v * centre_v, "u": u, "v": v, "axis": axis}
	_reaches[key] = result
	return result


## How far out one mesh's surface is at an anchor: along the ray for a point
## anchor, round the axis for a ring. -1 when the mesh does not reach it.
static func _surface_reach(node: MeshInstance3D, anchor: Dictionary, at: Vector3) -> float:
	var key := "%s|%s|%s" % [node.name, str(anchor["bone"]) + str(anchor["type"]) + str(anchor.get("dir", anchor.get("axis"))),
		str(at.snapped(Vector3.ONE * 0.001))]
	if _reaches.has(key):
		return _reaches[key]
	var points := _rest_points(node)
	var best := -1.0
	if str(anchor["type"]) == "ring":
		var axis := (anchor["axis"] as Vector3).normalized()
		var half := float(anchor["half"])
		var cap := float(anchor["cap"])
		for point in points:
			var offset := point - at
			var along := offset.dot(axis)
			if absf(along) > half:
				continue
			var radial := (offset - axis * along).length()
			if radial < cap:
				best = maxf(best, radial)
	else:
		var dir := (anchor["dir"] as Vector3).normalized()
		var reach := float(anchor["reach"])
		for point in points:
			var offset := point - at
			var along := offset.dot(dir)
			if along <= 0.0:
				continue
			if (offset - dir * along).length_squared() < reach * reach:
				best = maxf(best, along)
	_reaches[key] = best
	return best


static func _rest_points(node: MeshInstance3D) -> PackedVector3Array:
	var key := str(node.name)
	if _points.has(key):
		return _points[key]
	var points := PackedVector3Array()
	if node.mesh != null:
		for surface in node.mesh.get_surface_count():
			for vertex in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
				points.append(node.transform * vertex)
	_points[key] = points
	return points
