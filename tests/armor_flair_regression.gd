extends SceneTree
## The warband's armour flair: the livery, device, border, finish and trophies a
## mercenary puts on the pieces the whole band wears.
##
##     godot --headless --path . --script res://tests/armor_flair_regression.gd
##
## Owns: `WarbandFlair` (a pure function of the id, deterministic, eight bodies
## that never share a livery), the shader and the materials `ArmorFlair` builds
## on a live rig (every worn piece dressed, rest space baked, the authored
## material mirrored), the measured edges the borders and trim ride on, the
## trophy anchors (shown only with a real piece worn, measured onto the surface,
## a ring following the limb's cross-section), and that a body with no look is
## left exactly as it was.

const Looks = preload("res://scripts/warband/warband_looks.gd")
const Flair = preload("res://scripts/warband/warband_flair.gd")
const LookHash = preload("res://scripts/warband/look_hash.gd")
const ArmorFlair = preload("res://scripts/armor_flair.gd")
const Trophies = preload("res://scripts/armor_trophies.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const Archer = preload("res://scripts/archer.gd")

const SHADER_PATH := "res://scripts/world/shaders/armor_flair.gdshader"
const DEPLOYED_BODIES := 8

var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + message)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	check_profile_table()
	check_determinism()
	check_distinct_liveries()
	check_trophy_table()
	await check_shader()
	await check_rig()
	await check_trophies()
	await check_untouched()
	print("ARMOR_FLAIR_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


# --- the flair a mercenary gets ---------------------------------------------

func check_profile_table() -> void:
	var profile := Flair.profile_for(1)
	for key in ["field", "charge", "thread", "leather", "fittings", "bone", "feather"]:
		check(_is_hex(str(profile[key])), "flair %s is a #rrggbb colour" % key)
	for key in ["design", "motif", "hem", "finish"]:
		check(int(profile[key]) >= 0, "flair %s is an index" % key)
	check(int(profile["design"]) < Flair.DESIGNS.size(), "the design is one of the table's")
	check(int(profile["motif"]) < Flair.MOTIFS.size(), "the device is one of the table's")
	check(int(profile["hem"]) < Flair.HEMS.size(), "the border is one of the table's")
	check(int(profile["finish"]) < Flair.FINISHES.size(), "the finish is one of the table's")
	check(float(profile["thread_metal"]) >= 0.0 and float(profile["thread_metal"]) <= 1.0,
		"the thread's metallic share is a fraction")
	check(float(profile["seed"]) >= 0.0 and float(profile["seed"]) < 16.0, "the paint seed is bounded")
	check(not (profile["trophies"] as Array).is_empty(), "a mercenary hangs something on himself")
	# Every dye carries a charge, or a design would be drawn in the field's own
	# colour and the livery would read as a plain coat.
	for field in Flair.FIELDS:
		var charges: Array = (field as Dictionary)["charges"]
		check(charges.size() >= 2, "%s carries at least two charges" % (field as Dictionary)["name"])
		var valid := true
		for entry in charges:
			valid = valid and _is_hex(str(entry))
		check(valid, "%s's charges are #rrggbb" % (field as Dictionary)["name"])
	# A thread that vanished into the cloth would be a border nobody stitched.
	for id in range(1, DEPLOYED_BODIES + 1):
		var one := Flair.profile_for(id)
		var thread := Color(str(one["thread"])).get_luminance()
		var field := Color(str(one["field"])).get_luminance()
		var charge := Color(str(one["charge"])).get_luminance()
		check(absf(thread - field) >= 0.12 or absf(thread - charge) >= 0.12,
			"mercenary %d's thread reads on his livery" % id)
	check(Flair.LEATHERS.size() >= 4, "the leather stains carry variation")
	check(Flair.FINISHES.size() >= 3, "there are at least three ways to finish steel")
	check(Flair.FITTINGS.size() >= 3 and Flair.BONES.size() >= 3 and Flair.FEATHERS.size() >= 3,
		"the fittings, bone and feather palettes are authored")
	# The shader numbers the designs, devices and borders by table order.
	check(Flair.DESIGNS.size() == 15, "the design table is the shader's fifteen")
	check(Flair.MOTIFS.size() == 8, "the device table is the shader's eight")
	check(Flair.HEMS.size() == 6, "the border table is the shader's six")


func check_determinism() -> void:
	var first := Flair.profile_for(3).duplicate(true)
	check(first == Flair.profile_for(3), "a flair is the same every time it is asked for")
	Flair._profiles.clear()
	check(Flair.profile_for(3) == first, "a flair does not depend on having been asked for before")
	var alone := Flair.profile_for(7).duplicate(true)
	Flair._profiles.clear()
	for id in range(1, 13):
		Flair.profile_for(id)
	check(Flair.profile_for(7) == alone, "a flair does not depend on the order bodies spawn in")
	check(int(Flair.profile_for(0)["design"]) == int(Flair.profile_for(1)["design"]),
		"id 0 is treated as the first mercenary")
	# The look carries it, so a body only has to be given its look.
	check(Looks.profile_for(4).get("flair", {}).get("field", "")
		== Flair.profile_for(4)["field"], "the look carries the flair")


func check_distinct_liveries() -> void:
	var fields := {}
	var designs := {}
	var motifs := {}
	var hems := {}
	var threads := {}
	var trophies := {}
	for id in range(1, DEPLOYED_BODIES + 1):
		var profile := Flair.profile_for(id)
		fields[str(profile["field"])] = true
		designs[int(profile["design"])] = true
		motifs[int(profile["motif"])] = true
		hems[int(profile["hem"])] = true
		threads[str(profile["thread"])] = true
		var anchors := {}
		for entry in profile["trophies"]:
			var anchor := str((entry as Dictionary)["anchor"])
			check(not anchors.has(anchor), "merc %d hangs one trophy per place (%s)" % [id, anchor])
			anchors[anchor] = true
			trophies[anchor] = true
		check(anchors.has("hip_l"), "merc %d carries something at his belt" % id)
	check(fields.size() == DEPLOYED_BODIES, "eight bodies, eight fields")
	check(motifs.size() == DEPLOYED_BODIES, "eight bodies, eight devices")
	check(designs.size() >= 6, "the band wears six or more different designs (%d)" % designs.size())
	check(hems.size() >= 5, "the band sews five or more different borders (%d)" % hems.size())
	check(threads.size() >= 3, "the thread varies through the band (%d)" % threads.size())
	check(trophies.size() >= 4, "the band hangs trophies in four or more places (%d)" % trophies.size())
	# Hashed, not stepped: a tenth man is somebody else's double, which is a band.
	var wrapped := Flair.FIELDS.size() + 1
	check(Flair.profile_for(wrapped)["field"] == Flair.profile_for(1)["field"],
		"the palettes wrap rather than run out (id %d)" % wrapped)


func check_trophy_table() -> void:
	var tables := {"head": Flair.HEAD_TROPHIES, "hip": Flair.HIP_TROPHIES,
		"shoulder": Flair.SHOULDER_TROPHIES, "neck": Flair.NECK_TROPHIES,
		"wrist": Flair.WRIST_TROPHIES, "thigh": Flair.THIGH_TROPHIES,
		"ankle": Flair.ANKLE_TROPHIES}
	for group: String in tables:
		for kind in tables[group]:
			check(kind in Trophies.KINDS, "the %s %s has a builder" % [group, kind])
	# Every anchor a profile may name exists, and its part has a mirror.
	var anchors := ArmorFlair.ANCHORS
	for name in ["crown", "temple_l", "hip_l", "shoulder_l", "thigh_l", "neck", "wrist_l", "ankle_l"]:
		check(anchors.has(name), "the %s anchor is written down" % name)
	for name: String in anchors:
		var spec: Dictionary = anchors[name]
		check(spec.has("slot") and spec["slot"] in ArmorData.SLOTS,
			"%s hangs on a real armour slot" % name)
		check(str(spec.get("type", "")) in ["point", "ring"], "%s is a point or a ring" % name)
		check(spec.has("surfaces") and not (spec["surfaces"] as Array).is_empty(),
			"%s names the pieces it may sit outside of" % name)
	var mirror := ArmorFlair.anchor_spec("hip_r")
	check(not mirror.is_empty(), "the right hip mirrors the left")
	check((mirror["dir"] as Vector3).x < 0.0, "the mirrored anchor looks the other way")
	var wrist := ArmorFlair.anchor_spec("wrist_r")
	check(str(wrist["bone"]) == "lowerarm_r", "the mirrored anchor rides the mirrored bone")
	# Every trophy in a profile names a real anchor and a builder.
	for id in range(1, DEPLOYED_BODIES + 1):
		for entry in Flair.profile_for(id)["trophies"]:
			var kind := str((entry as Dictionary)["kind"])
			var anchor := str((entry as Dictionary)["anchor"])
			check(kind in Trophies.KINDS, "%s builds" % kind)
			check(not ArmorFlair.anchor_spec(anchor).is_empty(), "%s is an anchor" % anchor)


func _is_hex(value: String) -> bool:
	if value.length() != 7 or not value.begins_with("#"):
		return false
	for index in range(1, 7):
		if not value[index] in "0123456789abcdefABCDEF":
			return false
	return true


# --- the shader and the surfaces it dresses ---------------------------------

func check_shader() -> void:
	check(ResourceLoader.exists(SHADER_PATH), "the flair shader imports")
	var shader := load(SHADER_PATH) as Shader
	check(shader != null, "the flair shader loads")
	if shader == null:
		return
	var code := shader.code
	for uniform in ["role", "veil", "veil_alt", "piece", "edges", "surcoat", "field_color",
			"charge_color", "thread_color", "stain_color", "fittings_color", "bone_color",
			"finish_tint", "paint_color", "design", "motif", "hem", "seed"]:
		check(code.contains("uniform") and code.contains(uniform), "the shader takes %s" % uniform)
	check(code.contains("CUSTOM0"), "the shader reads the baked rest space")
	check(not code.contains("ALBEDO_TEXTURE"), "the shader draws the mirrored authored map itself")
	# Every authored armour material the rig can put on screen has a role, or a
	# set would silently keep the artist's colour while the rest of the kit takes
	# the man's.
	var seen := await _authored_materials()
	check(seen.size() >= 15, "the armour sets carry their authored materials (%d)" % seen.size())
	for name: String in seen:
		check(ArmorFlair.ROLES.has(name), "the authored %s has a flair role" % name)
	for name: String in ArmorFlair.ROLES:
		var role := int((ArmorFlair.ROLES[name] as Dictionary)["role"])
		check(role >= ArmorFlair.ROLE_CLOTH and role <= ArmorFlair.ROLE_BONE,
			"%s's role is one the shader knows" % name)


## Every authored material name on the armour a rig can wear that the flair
## dresses. The naked body and the ranger outfit's own skin patch are the look's
## surfaces (`Archer.LOOKS_SURFACES` tints those), not the armour's.
func _authored_materials() -> Dictionary:
	var rig = Archer.new()
	root.add_child(rig)
	await process_frame
	var names := {}
	var naked := ArmorData.SET_IDS.find("naked")
	for slot in ArmorData.SLOTS:
		for set_index in ArmorData.SET_IDS.size():
			if set_index == naked:
				continue
			for node: MeshInstance3D in rig._armor_meshes[slot][set_index]:
				if node.mesh == null:
					continue
				for surface in node.mesh.get_surface_count():
					var material := node.get_active_material(surface)
					if material == null or str(material.resource_name).is_empty():
						continue
					if Archer.LOOKS_SURFACES.has(str(material.resource_name)):
						continue
					names[str(material.resource_name)] = true
	rig.queue_free()
	await process_frame
	return names


# --- a live body -------------------------------------------------------------

func check_rig() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var rig = Archer.new()
	rig.appearance = Looks.profile_for(2)
	holder.add_child(rig)
	await process_frame
	check(rig._flair != null, "a body with a look builds its flair")
	if rig._flair == null:
		return
	var mail := ArmorData.SET_IDS.find("mail")
	var pieces := {}
	for slot in ArmorData.SLOTS:
		pieces[slot] = mail
	rig.set_armor_pieces(pieces)
	await process_frame

	# The worn pieces are dressed, and nothing else is touched.
	var dressed := 0
	var authored_left := 0
	for slot in ArmorData.SLOTS:
		for set_index in ArmorData.SET_IDS.size():
			for node: MeshInstance3D in rig._armor_meshes[slot][set_index]:
				var is_worn := set_index == mail
				for surface in node.mesh.get_surface_count():
					var active := node.get_active_material(surface)
					if is_worn:
						check(active is ShaderMaterial,
							"%s's surface is drawn by the flair" % node.name)
						dressed += 1
						var material := active as ShaderMaterial
						check(int(material.get_shader_parameter("piece")) ==
							ArmorData.SLOTS.find(slot), "%s knows which piece it is" % node.name)
						check(int(material.get_shader_parameter("role")) > 0,
							"%s knows what it is made of" % node.name)
					elif active is ShaderMaterial:
						authored_left += 1
	check(dressed >= 5, "every worn piece takes the flair (%d surfaces)" % dressed)
	check(authored_left == 0, "only the worn pieces are dressed (%d stray)" % authored_left)
	# The livery's own colours reached the shader.
	var first := _first_flair_material(rig)
	if first != null:
		check((first.get_shader_parameter("field_color") as Color).is_equal_approx(
			Color(str(rig.appearance["flair"]["field"]))), "the field dye reached the shader")
		check(int(first.get_shader_parameter("design")) == int(rig.appearance["flair"]["design"]),
			"the design reached the shader")
		# A surcoat is the man's own choice: the mail trunk shows one when his
		# flair says so, and never when it does not.
		var surcoat := bool(rig.appearance["flair"]["surcoat"])
		check(bool(first.get_shader_parameter("surcoat")) == surcoat,
			"the mail trunk's surcoat follows the flair (%s)" % str(surcoat))

	# Rest space: CUSTOM0 is the vertex's position before the skin moves it.
	var node: MeshInstance3D = (rig._armor_meshes["chest"][mail] as Array)[0]
	check(node.mesh.has_meta("flair_rest"), "the worn mesh carries its rest space")
	var source := node.mesh as ArrayMesh
	check(source.surface_get_format(0) & (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) != 0,
		"the rest space is a three-float custom channel")
	var arrays := source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var rest: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	check(rest.size() == vertices.size() * 3, "every vertex has a rest position")
	var worst := 0.0
	for index in mini(vertices.size(), 400):
		var expected := node.transform * vertices[index]
		worst = maxf(worst, expected.distance_to(Vector3(rest[index * 3], rest[index * 3 + 1],
			rest[index * 3 + 2])))
	check(worst < 0.0005, "the rest space is the mesh's own vertices (%.4f m off)" % worst)
	# It is baked once and shared: a second body does not pay for it again.
	var other = Archer.new()
	other.appearance = Looks.profile_for(5)
	holder.add_child(other)
	await process_frame
	other.set_armor(mail)
	await process_frame
	var other_node: MeshInstance3D = (other._armor_meshes["chest"][mail] as Array)[0]
	check(other_node.mesh.get_instance_id() == source.get_instance_id(),
		"the rest mesh is shared by every body")
	# ... while the materials are each body's own.
	var other_first := _first_flair_material(other)
	check(other_first != null and other_first != first, "each body has its own seeded materials")

	# The edges the borders ride on.
	for set_index in ArmorData.SET_IDS.size():
		if ArmorData.SET_IDS[set_index] == "naked":
			continue
		var legs := ArmorFlair.piece_edges(rig._armor_meshes, "legs", set_index)
		check(legs.x < 1.10, "%s legs have a hem at rest height (%.2f)"
			% [ArmorData.SET_IDS[set_index], legs.x])
		var chest := ArmorFlair.piece_edges(rig._armor_meshes, "chest", set_index)
		check(chest.z > 0.40, "%s chest has a sleeve end (%.2f)"
			% [ArmorData.SET_IDS[set_index], chest.z])
		var feet := ArmorFlair.piece_edges(rig._armor_meshes, "feet", set_index)
		check(feet.y > 0.10, "%s boots have a top (%.2f)" % [ArmorData.SET_IDS[set_index], feet.y])
	var hands := ArmorFlair.piece_edges(rig._armor_meshes, "hands", mail)
	check(hands.w > 0.5, "the gloves have a cuff (%.2f)" % hands.w)

	# The veils: dividing the authored map by them is what leaves the weave and
	# the grain without the colour.
	var leather := ArmorFlair.material_stats(_authored(rig, "M_Armor_Leather"), ArmorFlair.ROLE_LEATHER)
	check(float(leather["veil"]) > 0.004 and float(leather["veil"]) < 0.6,
		"the leather's veil is a measured luminance (%.3f)" % float(leather["veil"]))
	var outfit := ArmorFlair.material_stats(_authored(rig, "MI_Ranger"), ArmorFlair.ROLE_OUTFIT)
	check(float(outfit["veil"]) > 0.004 and float(outfit["veil_alt"]) > 0.004,
		"the ranger's atlas is split into its cloth and its leather")
	check(not is_equal_approx(float(outfit["veil"]), float(outfit["veil_alt"])),
		"the outfit's cloth and leather are measured apart (%.3f / %.3f)"
		% [float(outfit["veil"]), float(outfit["veil_alt"])])
	holder.queue_free()
	await process_frame


func _authored(rig, name: String) -> BaseMaterial3D:
	for slot in ArmorData.SLOTS:
		for set_index in ArmorData.SET_IDS.size():
			for node: MeshInstance3D in rig._armor_meshes[slot][set_index]:
				if node.mesh == null:
					continue
				for surface in node.mesh.get_surface_count():
					var active := node.get_active_material(surface)
					if active is BaseMaterial3D and str(active.resource_name) == name:
						return active as BaseMaterial3D
	return null


func _first_flair_material(rig) -> ShaderMaterial:
	for slot in ArmorData.SLOTS:
		for set_index in ArmorData.SET_IDS.size():
			for node: MeshInstance3D in rig._armor_meshes[slot][set_index]:
				if not node.visible or node.mesh == null:
					continue
				for surface in node.mesh.get_surface_count():
					var active := node.get_surface_override_material(surface)
					if active is ShaderMaterial:
						return active as ShaderMaterial
	return null


# --- the trophies ------------------------------------------------------------

func check_trophies() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var rig = Archer.new()
	rig.appearance = Looks.profile_for(1)
	holder.add_child(rig)
	await process_frame
	check(rig._flair != null, "the body has a flair to hang trophies on")
	if rig._flair == null:
		return
	var naked := ArmorData.SET_IDS.find("naked")
	rig.set_armor(naked)
	await process_frame
	for row in rig._flair.trophies():
		check(not bool(row["visible"]), "a bare body shows no %s trophy" % str(row["anchor"]))
	var plate := ArmorData.SET_IDS.find("plate")
	rig.set_armor(plate)
	await process_frame
	var shown := 0
	var bones := {}
	for row in rig._flair.trophies():
		var anchor := str(row["anchor"])
		bones[anchor] = true
		if not bool(row["visible"]):
			continue
		shown += 1
		var attachment := row["node"] as BoneAttachment3D
		check(attachment != null, "%s rides a bone" % anchor)
		if attachment == null:
			continue
		check(rig.skeleton.find_bone(attachment.bone_name) >= 0, "%s's bone exists" % anchor)
		check(attachment.visible, "%s's attachment is shown with its piece" % anchor)
		check(attachment.get_child_count() == 1, "%s carries one holder" % anchor)
		var mesh_node := attachment.get_child(0).get_child(0) as MeshInstance3D
		check(mesh_node != null and mesh_node.mesh is ArrayMesh, "%s built its geometry" % anchor)
		if mesh_node != null and mesh_node.mesh is ArrayMesh:
			var tris := 0
			for surface in mesh_node.mesh.get_surface_count():
				tris += (mesh_node.mesh as ArrayMesh).surface_get_array_len(surface) / 3
			check(tris > 12, "%s is real geometry (%d triangles)" % [anchor, tris])
			check(tris < 900, "%s stays cheap (%d triangles)" % [anchor, tris])
		check(mesh_node != null and mesh_node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"%s casts no shadow" % anchor)
		# The holder's frame is in the bone's rest space, so the trophy follows
		# the body through every pose instead of hanging where it was built.
		var placement := attachment.get_child(0) as Node3D
		check(placement != null and not placement.transform.is_equal_approx(Transform3D.IDENTITY),
			"%s is placed on the garment, not at the bone" % anchor)
	check(shown >= 1, "the plate body wears its trophies (%d)" % shown)
	check(bones.size() >= 1, "the body's trophies are listed")
	# A trophy is on the piece, not at the anchor: the measured frame stands off
	# whatever is drawn there.
	var hip := ArmorFlair.anchor_spec("hip_l")
	var placed: Dictionary = rig._flair._anchor_frame(hip, rig.armor_pieces)
	check(not placed.is_empty(), "the hip anchor finds a surface on plate")
	if not placed.is_empty():
		var origin: Vector3 = (placed["frame"] as Transform3D).origin
		check(absf(origin.x) > 0.12, "the hip trophy sits outside the waist (%.2f m)" % absf(origin.x))
	# A ring follows the cross-section: a neck is wider across than deep.
	var neck := ArmorFlair.anchor_spec("neck")
	var section: Dictionary = rig._flair._anchor_frame(neck, rig.armor_pieces)
	check(not section.is_empty(), "the neck anchor measures a cross-section")
	if not section.is_empty():
		var size: Vector2 = section["size"]
		check(size.x > 0.10 and size.y > 0.08, "the necklace is a neck's size (%.2f x %.2f)"
			% [size.x, size.y])
		check(absf(size.x - size.y) > 0.008, "the necklace follows an oval neck (%.3f x %.3f)"
			% [size.x, size.y])
	# The trophy geometry itself: a hanging trophy in its own frame, a ring round
	# the measured cross-section.
	var mats := Trophies.materials(rig.appearance["flair"])
	var merged = Trophies.build("skull", mats, Vector2.ZERO, 1.0)
	var host := Node3D.new()
	holder.add_child(host)
	var built: MeshInstance3D = merged.commit(host, "TrialSkull", false)
	check(built != null and built.mesh.get_surface_count() >= 2,
		"a skull is bone and cord on two surfaces")
	var necklace = Trophies.build_necklace("teeth", mats, Vector2(0.11, 0.09))
	check(not necklace.is_empty(), "a necklace builds round a measured neck")
	# Every kind builds, at the sizes it is asked for.
	for kind in Trophies.KINDS:
		var size := Vector2(0.11, 0.09) if kind in ["beads", "rattles"] else Vector2.ZERO
		var trial = Trophies.build(kind, mats, size, 1.0)
		check(not trial.is_empty(), "%s builds" % kind)
	# The band's own bodies hang something a player can read at a distance.
	var hung := 0
	for id in range(1, DEPLOYED_BODIES + 1):
		var body = Archer.new()
		body.appearance = Looks.profile_for(id)
		holder.add_child(body)
		await process_frame
		body.set_armor(plate)
		await process_frame
		for row in body._flair.trophies():
			if bool(row["visible"]):
				hung += 1
	check(hung >= DEPLOYED_BODIES, "the whole band hangs trophies (%d)" % hung)
	holder.queue_free()
	await process_frame


# --- a body with no look is untouched ---------------------------------------

func check_untouched() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var rig = Archer.new()
	holder.add_child(rig)
	await process_frame
	check(rig._flair == null, "a body with no look has no flair")
	rig.set_armor(ArmorData.SET_IDS.find("plate"))
	await process_frame
	var overridden := 0
	var rebaked := 0
	for slot in ArmorData.SLOTS:
		for set_index in ArmorData.SET_IDS.size():
			for node: MeshInstance3D in rig._armor_meshes[slot][set_index]:
				if node.mesh != null and node.mesh.has_meta("flair_rest"):
					rebaked += 1
				for surface in node.mesh.get_surface_count():
					if node.get_surface_override_material(surface) != null:
						overridden += 1
	check(overridden == 0, "no authored surface is dressed (%d)" % overridden)
	check(rebaked == 0, "no authored mesh is rebaked (%d)" % rebaked)
	holder.queue_free()
	await process_frame
