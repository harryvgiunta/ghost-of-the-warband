extends SceneTree
## The warband has to look like a band, not eight copies of one man.
##
## Three things are held here. First, a look is a *pure function of the mercenary
## id*: every peer and every reload must dress the same body the same way, which is
## what lets the look stay off the wire and out of the save. Second, the eight
## bodies a warband can deploy never share a face or a haircut, and no body leaves
## the height band the authoring tool declares. Third, the rig actually applies the
## look: the shipped head is replaced by its variant, one hairstyle and one beard
## are drawn, the shirt and skin are tinted from the veiled maps, hair goes under
## a helmet and head hitboxes follow the height.
##
##     godot --headless --path . --script res://tests/warband_appearance_regression.gd

const Looks = preload("res://scripts/warband/warband_looks.gd")
const Archer = preload("res://scripts/archer.gd")
const ActorScript = preload("res://scripts/warband/warband_body.gd")
const ArmorData = preload("res://scripts/armor_data.gd")

const FACES_PATH := "res://assets/characters/warband/ironwood_faces.glb"
const HAIR_PATH := "res://assets/characters/warband/ironwood_hair.glb"
const SKIN_PATH := "res://assets/characters/warband/warband_skin_basecolor.png"
const SHIRT_PATH := "res://assets/characters/warband/warband_shirt_basecolor.png"
const DEPLOYED_BODIES := 8

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WARBAND_LOOK_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check_table()
	check_determinism()
	check_distinct_bodies()
	check_assets()
	await check_rig()
	await check_untouched_rig()
	await check_actor()
	print("WARBAND_APPEARANCE_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


# --- the authored table -----------------------------------------------------

func check_table() -> void:
	var table := Looks.data()
	check(not table.is_empty(), "the look table loads")
	var faces: Array = table.get("faces", [])
	var hairs: Array = table.get("hair", [])
	var beards: Array = table.get("beards", [])
	var tones: Dictionary = table.get("tones", {})
	var eyes: Array = table.get("eye_tones", [])
	check(faces.size() >= DEPLOYED_BODIES, "there is a face per deployable body (%d)" % faces.size())
	check(hairs.size() >= DEPLOYED_BODIES, "there is a hairstyle per deployable body (%d)"
		% hairs.size())
	check(beards.size() >= 3, "the beards are authored (%d)" % beards.size())
	check(eyes.size() >= 4, "the iris tones are authored (%d)" % eyes.size())
	for key in ["skin", "shirt", "shorts", "hair"]:
		var palette: Array = tones.get(key, [])
		check(palette.size() >= 4, "the %s palette carries variation (%d)" % [key, palette.size()])
		var valid := true
		for entry in palette:
			valid = valid and _is_hex(str(entry))
		check(valid, "every %s tone is a #rrggbb colour" % key)
	# Palette entry 0 is the measured base of the shipped texture: that is what
	# makes an untinted mercenary look exactly as he shipped, and it is a claim the
	# authoring tool makes in its own metadata.
	var veil: Dictionary = table.get("veil", {})
	for key in ["skin", "shirt", "shorts"]:
		var palette: Array = tones.get(key, [])
		check(not palette.is_empty() and _same_tone(str(palette[0]), veil.get(key)),
			"the %s palette starts at the measured base colour" % key)

func _is_hex(value: String) -> bool:
	if value.length() != 7 or not value.begins_with("#"):
		return false
	for index in range(1, 7):
		if not value[index] in "0123456789abcdefABCDEF":
			return false
	return true


## The palettes are sRGB hex and `veil` is the same measured base as linear RGB
## floats, because that is the space `albedo_color` multiplies in. One tone in two
## encodings: compare them in one space, at half an 8-bit step of slack.
func _same_tone(hex: String, linear: Variant) -> bool:
	if not (linear is Array) or not _is_hex(hex):
		return false
	var measured: Array = linear
	if measured.size() != 3:
		return false
	var tone := Color(hex).srgb_to_linear()
	return absf(tone.r - float(measured[0])) <= 0.006 \
		and absf(tone.g - float(measured[1])) <= 0.006 \
		and absf(tone.b - float(measured[2])) <= 0.006


# --- determinism ------------------------------------------------------------

func check_determinism() -> void:
	var first := Looks.profile_for(3).duplicate()
	var again := Looks.profile_for(3)
	check(first == again, "a look is the same every time it is asked for")
	Looks._profiles.clear()
	var rebuilt := Looks.profile_for(3)
	check(rebuilt == first, "a look does not depend on having been asked for before")
	# Order must not matter either: an id looked at alone answers the same as one
	# looked at after the rest of the roster.
	var alone := Looks.profile_for(7).duplicate()
	Looks._profiles.clear()
	for id in range(1, 13):
		Looks.profile_for(id)
	check(Looks.profile_for(7) == alone, "a look does not depend on the order bodies spawn in")
	check(int(Looks.profile_for(0)["merc_id"]) == 1, "id 0 is treated as the first mercenary")


# --- eight different men ----------------------------------------------------

func check_distinct_bodies() -> void:
	var faces := {}
	var hairs := {}
	var heights := {}
	var skins := {}
	var shirts := {}
	var shorts := {}
	var lowest := 2.0
	var highest := 0.0
	for id in range(1, DEPLOYED_BODIES + 1):
		var profile := Looks.profile_for(id)
		faces[int(profile["face"])] = true
		hairs[str(profile["hair_name"])] = true
		skins[str(profile["skin"])] = true
		shirts[str(profile["shirt"])] = true
		shorts[str(profile["shorts"])] = true
		var height := float(profile["height"])
		heights[snappedf(height, 0.001)] = true
		lowest = minf(lowest, height)
		highest = maxf(highest, height)
		check(height >= Looks.HEIGHT_MIN - 0.001 and height <= Looks.HEIGHT_MAX + 0.001,
			"mercenary %d is inside the height band (%.3f)" % [id, height])
		check(float(profile["height"]) >= 0.80 and float(profile["height"]) <= 1.20,
			"mercenary %d height is a legal rig scale" % id)
		check(int(profile["beard"]) >= 0 and int(profile["beard"])
			< (Looks.data().get("beards", []) as Array).size(),
			"mercenary %d wears an authored beard" % id)
		check(int(profile["eye"]) >= 0 and int(profile["eye"])
			< (Looks.data().get("eye_tones", []) as Array).size(),
			"mercenary %d has an authored iris" % id)
		var tones: Dictionary = Looks.data().get("tones", {})
		for key in ["skin", "shirt", "shorts", "hair_tone"]:
			check((tones.get(key.substr(0, key.length() - 5) if key == "hair_tone" else key,
				[]) as Array).has(str(profile[key])),
				"mercenary %d %s is a palette entry" % [id, key])
	check(faces.size() == DEPLOYED_BODIES, "eight bodies, eight different faces")
	check(skins.size() == DEPLOYED_BODIES, "eight bodies, eight different skins")
	check(shirts.size() == DEPLOYED_BODIES, "eight bodies, eight different shirts")
	check(shorts.size() == DEPLOYED_BODIES, "eight bodies, eight different shorts")
	# Past the deployment cap the palettes wrap rather than run out: a ninth hired
	# man is somebody else's double, which is a warband, not an error.
	check(Looks.profile_for(DEPLOYED_BODIES + 1)["shirt"]
		== Looks.profile_for(1)["shirt"], "the ninth body reuses the first shirt")
	check(hairs.size() == DEPLOYED_BODIES, "eight bodies, eight different haircuts")
	check(heights.size() >= 4, "the band is at four or more distinct heights (%d)" % heights.size())
	check(highest - lowest >= 0.10, "the tallest man is a hand above the shortest (%.2f m to %.2f m)"
		% [highest * 1.869, lowest * 1.869])


# --- the authored assets ----------------------------------------------------

func check_assets() -> void:
	check(ResourceLoader.exists(FACES_PATH), "the faces asset imports")
	check(ResourceLoader.exists(HAIR_PATH), "the hair asset imports")
	check(ResourceLoader.exists(SKIN_PATH), "the veiled skin map imports")
	check(ResourceLoader.exists(SHIRT_PATH), "the veiled shirt map imports")
	var faces := load(FACES_PATH) as PackedScene
	var hair := load(HAIR_PATH) as PackedScene
	if faces == null or hair == null:
		check(false, "the look assets load as scenes")
		return
	var face_root := faces.instantiate() as Node3D
	var hair_root := hair.instantiate() as Node3D
	var face_names := {}
	var hair_names := {}
	for node in face_root.find_children("*", "MeshInstance3D", true, false):
		face_names[str(node.name)] = true
		var mesh := (node as MeshInstance3D).mesh
		check(mesh != null, "%s carries a mesh" % node.name)
		if mesh != null:
			var skinned := false
			for surface in mesh.get_surface_count():
				var material := mesh.surface_get_material(surface)
				skinned = skinned or (material != null and not str(material.resource_name).is_empty())
			check(skinned, "%s carries a named material" % node.name)
	for node in hair_root.find_children("*", "MeshInstance3D", true, false):
		hair_names[str(node.name)] = true
	# Every name the table hands the rig has to exist in the files, or a body
	# would silently spawn bald and faceless.
	for index in (Looks.data().get("faces", []) as Array).size():
		var face_name := "Face%d" % (index + 1)
		check(face_names.has(face_name + "_Skin"), "%s has a skin mesh" % face_name)
		check(face_names.has(face_name + "_Brows"), "%s has brows" % face_name)
		check(face_names.has(face_name + "_Eyes"), "%s has eyes" % face_name)
	var authored := 0
	for style in Looks.data().get("hair", []):
		var style_name := str((style as Dictionary).get("name", ""))
		if bool((style as Dictionary).get("bare", false)):
			continue
		authored += 1
		check(hair_names.has("Hair_" + style_name), "the %s hairstyle is in the asset" % style_name)
	check(authored == (Looks.data().get("hair", []) as Array).size() - 1,
		"exactly one hairstyle is the shaved head")
	for style in Looks.data().get("beards", []):
		var beard_name := str((style as Dictionary).get("name", ""))
		if beard_name == "None":
			continue
		check(hair_names.has("Beard_" + beard_name), "the %s beard is in the asset" % beard_name)
	face_root.free()
	hair_root.free()


# --- the rig ----------------------------------------------------------------

func check_rig() -> void:
	var rig = Archer.new()
	rig.appearance = Looks.profile_for(2)
	root.add_child(rig)
	await process_frame
	var profile: Dictionary = rig.appearance
	var height := float(profile["height"])
	check(absf(rig.body_scale() - height) < 0.0001, "the rig reports its own height")
	check(rig._model.scale.is_equal_approx(Vector3.ONE * height),
		"the height is baked into the model (%.2f)" % rig._model.scale.y)
	check(absf(rig.head_hit_profile().x - 0.34 * height) < 0.001,
		"the head zone is the height's head zone")
	# The shipped head is replaced by its variant.
	for name in ["Ranger_Head_SuperHero_Male", "Ranger_Head_Eyebrows", "Ranger_Head_Eyes"]:
		var shipped := rig._model.find_child(name, true, false) as MeshInstance3D
		check(shipped != null and not shipped.visible, "the shipped %s is replaced" % name)
	check(rig._looks_face != null, "a face variant is attached")
	var face_name := str(profile["face_name"]) + "_"
	var visible_faces := 0
	var stray_faces := 0
	for node in rig._looks_face.find_children("*", "MeshInstance3D", true, false):
		if not (node as MeshInstance3D).visible:
			continue
		if str(node.name).begins_with(face_name):
			visible_faces += 1
		else:
			stray_faces += 1
	check(visible_faces == 3, "the whole chosen face is drawn (%d meshes)" % visible_faces)
	check(stray_faces == 0, "no other man's face is drawn beside it (%d stray)" % stray_faces)

	# Hair and beard.
	var hair_name := str(profile["hair_name"])
	var beard_name := str(profile["beard_name"])
	var visible_hair := 0
	var visible_beard := 0
	for node in rig._looks_hair.find_children("*", "MeshInstance3D", true, false):
		if not (node as MeshInstance3D).visible:
			continue
		if str(node.name) == hair_name:
			visible_hair += 1
		elif str(node.name) == beard_name:
			visible_beard += 1
	check(visible_hair == 1, "the chosen hairstyle is drawn once")
	check(visible_beard == 1, "the chosen beard is drawn once")

	# Tints: the naked set is the body a warband starts in.
	var naked: int = ArmorData.SET_IDS.find("naked")
	rig.set_armor(naked)
	await process_frame
	var skin_ok := false
	var shirt_ok := false
	var shorts_ok := false
	for node in rig._model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var override := mesh.get_surface_override_material(surface)
			if override == null:
				continue
			var key := str(override.resource_name)
			var material := override as BaseMaterial3D
			if material == null:
				continue
			if key == "Naked_Skin":
				skin_ok = material.albedo_texture == load(SKIN_PATH) \
					and material.albedo_color.is_equal_approx(Color(profile["skin"]).srgb_to_linear())
			if key == "Naked_Shirt":
				shirt_ok = material.albedo_texture == load(SHIRT_PATH) \
					and material.albedo_color.is_equal_approx(Color(profile["shirt"]).srgb_to_linear())
			if key == "Naked_Shorts":
				shorts_ok = material.albedo_color.is_equal_approx(
					Color(profile["shorts"]).srgb_to_linear())
	check(skin_ok, "the skin is tinted from the veiled skin map")
	check(shirt_ok, "the shirt is dyed from the veiled linen")
	check(shorts_ok, "the shorts are dyed")
	check(rig._looks_hair.visible, "hair is drawn while the head is bare")
	rig.set_armor_piece("head", 0)
	await process_frame
	check(not rig._looks_hair.visible, "hair goes under a helmet")
	rig.set_armor_piece("head", naked)
	await process_frame
	check(rig._looks_hair.visible, "hair comes back when the helmet does")
	rig.queue_free()
	await process_frame


# --- a body with no look is untouched ---------------------------------------

func check_untouched_rig() -> void:
	var rig = Archer.new()
	root.add_child(rig)
	await process_frame
	check(rig.body_scale() == 1.0, "a body with no look is the authored height")
	check(rig._model.scale.is_equal_approx(Vector3.ONE), "a body with no look is not scaled")
	check(rig._looks_face == null and rig._looks_hair == null,
		"a body with no look instantiates no look assets")
	var shipped := rig._model.find_child("Ranger_Head_SuperHero_Male", true, false) as MeshInstance3D
	check(shipped != null and shipped.visible, "a body with no look keeps the shipped head")
	check(absf(rig.head_hit_profile().x - 0.34) < 0.001, "a body with no look keeps the authored head zone")
	rig.queue_free()
	await process_frame


# --- the arena body carries the look into the world ------------------------

func check_actor() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var actor = ActorScript.new()
	actor.slot = 0
	actor.appearance = Looks.profile_for(4)
	holder.add_child(actor)
	await process_frame
	var height := float(actor.appearance["height"])
	check(absf(actor.body_scale() - height) < 0.0001, "the body reports the look's height")
	check(is_instance_valid(actor.rig) and absf(actor.rig.body_scale() - height) < 0.0001,
		"the body's rig wears the look")
	var aim: Vector3 = actor.get_aim_position() - actor.global_position
	check(absf(aim.y - 1.2 * height) < 0.001, "aim points at the body's own chest")
	check(actor._label != null and absf(actor._label.position.y - 2.3 * height) < 0.001,
		"the name plate sits over the body's own head")
	holder.queue_free()
	await process_frame
