extends RefCounted
## Blood presentation shared by the frontier, arena and delve.
##
## The project renders with the GL Compatibility backend, which does not draw
## `Decal` nodes. Ground blood is therefore a small mesh patch conformed to the
## surface by physics rays, while body and weapon blood are bone- or
## weapon-parented wet blotches. A per-scene `BloodField` owns the 60-second
## spatter lifetime, the five-minute death pools, the fade and the render
## budget. Damage authority never changes: every call here is cosmetic and safe
## to skip on a peer that did not apply the damage.

const LIFETIME := 60.0
const FADE_SECONDS := 3.0
## Pooled blood outlives the spray: it stays under a body for as long as the
## corpse lies there (`scripts/corpse_hold.gd` holds corpses for five minutes).
const POOL_LIFETIME := 300.0
const SPLAT_VARIANTS := 3

static var _splat_textures: Array[Texture2D] = []
static var _pool_texture: Texture2D
static var _patch_materials: Array[StandardMaterial3D] = []
static var _soak_materials: Array[StandardMaterial3D] = []
static var _pool_material: StandardMaterial3D
static var _footprint_material: StandardMaterial3D
static var _blot_material: StandardMaterial3D
static var _blot_mesh: SphereMesh
static var _drop_mesh: SphereMesh
static var _drop_material: StandardMaterial3D
static var _prepared := false

# --- public entry points ---------------------------------------------------

static func impact(parent: Node, at: Vector3, direction: Vector3, amount: float,
		headshot: bool = false) -> void:
	if amount <= 0.0:
		return
	var field := field_for(parent)
	if field != null:
		field.impact(at, direction, amount, headshot)

static func wound(parent: Node, rig: Node3D, at: Vector3, amount: float,
		headshot: bool = false, lethal: bool = false, scale: float = 1.0) -> void:
	if amount <= 0.0 and not lethal:
		return
	var field := field_for(parent)
	if field != null:
		field.wound(rig, at, amount, headshot, lethal, scale)

## Blood from someone else landing on this body: the limb of a clawed or fanged
## attacker, with no second floor decal under it.
static func bloodied(parent: Node, rig: Node3D, at: Vector3, amount: float,
		scale: float = 1.0) -> void:
	if amount <= 0.0:
		return
	var field := field_for(parent)
	if field != null:
		field.bloodied(rig, at, amount, scale)

## A melee kill throws the victim's blood back over the killer: chest and face
## are doused, scaled by how close the blow landed. Only a real melee kill calls
## this — a distant arrow or throw leaves the shooter clean.
static func spatter_kill(attacker: Node3D, rig: Node3D, contact: Vector3,
		amount: float) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(rig) \
			or amount <= 0.0:
		return
	var field := field_for(attacker)
	if field == null:
		return
	var offset := contact - attacker.global_position
	offset.y = 0.0
	var distance := offset.length()
	var forward := offset / distance if distance > 0.001 \
		else -attacker.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var reach := clampf(1.7 / maxf(distance, 0.35), 0.5, 1.0)
	var scale := 1.0
	if attacker.has_method("blood_scale"):
		scale = float(attacker.blood_scale())
	var chest: Vector3 = attacker.global_position + Vector3.UP * 1.15 \
		+ forward * 0.22
	var face: Vector3 = attacker.global_position + Vector3.UP * 1.62 \
		+ forward * 0.14
	field.bloodied(rig, chest, amount * reach, scale)
	field.bloodied(rig, face, amount * reach * 0.65, scale)

## The mob that landed the blow wears the result. A held blade takes a coating
## through `blood_weapon_anchor`; a natural weapon takes a soak on the claw,
## paw or muzzle that struck.
static func stain_attacker(attacker: Node, amount: float) -> void:
	if not is_instance_valid(attacker) or amount <= 0.0:
		return
	var scale := 1.0
	if attacker.has_method("blood_scale"):
		scale = float(attacker.blood_scale())
	if attacker.has_method("blood_weapon_anchor"):
		var weapon: Node3D = attacker.blood_weapon_anchor()
		if is_instance_valid(weapon):
			stain_weapon_node(weapon, amount, scale)
			return
	if not attacker.has_method("blood_rig") \
			or not attacker.has_method("blood_strike_point"):
		return
	var rig = attacker.blood_rig()
	if not is_instance_valid(rig):
		return
	bloodied(attacker, rig, attacker.blood_strike_point(), amount * 0.85, scale)

static func stain_weapon(rig: Node, amount: float, hand: String = "") -> void:
	if not is_instance_valid(rig) or amount <= 0.0:
		return
	if not rig.has_method("blood_weapon_anchor"):
		return
	var anchor: Node3D = rig.blood_weapon_anchor(hand)
	if not is_instance_valid(anchor):
		return
	var scale := 0.8
	if rig.has_method("blood_scale"):
		scale = float(rig.blood_scale())
	stain_weapon_node(anchor, amount, scale)

static func stain_weapon_node(anchor: Node3D, amount: float, scale: float = 1.0) -> void:
	if not is_instance_valid(anchor) or amount <= 0.0 or not anchor.is_inside_tree():
		return
	var field := field_for(anchor)
	if field != null:
		field.stain_weapon(anchor, amount, clampf(scale, 0.3, 2.5))

static func stain_projectile(node: Node3D, amount: float) -> void:
	if not is_instance_valid(node) or amount <= 0.0 or not node.is_inside_tree():
		return
	var field := field_for(node)
	if field != null:
		field.stain_projectile(node, amount)

## Finds the per-scene blood owner, creating it under the current scene root on
## the first wound. Called only from real damage events.
static func field_for(parent: Node) -> Node:
	if not is_instance_valid(parent):
		return null
	var tree := parent.get_tree()
	if tree == null:
		return null
	var root := tree.current_scene
	if root == null:
		root = tree.root
	if root == null:
		return null
	var existing := root.get_node_or_null("BloodField")
	if existing != null:
		return existing
	var script := load("res://scripts/blood_field.gd")
	if script == null:
		return null
	var field: Node = script.new()
	field.name = "BloodField"
	root.add_child(field)
	return field

# --- shared art ------------------------------------------------------------

static func splat_texture(variant: int = -1) -> Texture2D:
	_prepare()
	if variant < 0:
		variant = randi() % SPLAT_VARIANTS
	return _splat_textures[clampi(variant, 0, _splat_textures.size() - 1)]

static func pool_texture() -> Texture2D:
	_prepare()
	return _pool_texture

static func patch_material(variant: int = -1) -> StandardMaterial3D:
	_prepare()
	if variant < 0:
		variant = randi() % SPLAT_VARIANTS
	return _patch_materials[clampi(variant, 0, _patch_materials.size() - 1)]

## Blood soaked into cloth or hide: a flat unshaded dye with a crisp rim, so a
## stain reads as colour on the garment instead of a lit blob sitting on top of
## it.
static func soak_material(variant: int = -1) -> StandardMaterial3D:
	_prepare()
	if variant < 0:
		variant = randi() % SPLAT_VARIANTS
	return _soak_materials[clampi(variant, 0, _soak_materials.size() - 1)]

static func pool_material() -> StandardMaterial3D:
	_prepare()
	return _pool_material

## Solid unshaded blood for footprints: the patch geometry is the foot shape,
## so a flat colour (not a circular splat texture) is what makes it read as a
## foot instead of a blob.
static func footprint_material() -> StandardMaterial3D:
	_prepare()
	return _footprint_material

static func blot_material() -> StandardMaterial3D:
	_prepare()
	return _blot_material

static func blot_mesh() -> SphereMesh:
	_prepare()
	return _blot_mesh

static func drop_mesh() -> SphereMesh:
	_prepare()
	return _drop_mesh

static func drop_material() -> StandardMaterial3D:
	_prepare()
	return _drop_material

static func _prepare() -> void:
	if _prepared:
		return
	_prepared = true
	_blot_material = StandardMaterial3D.new()
	_blot_material.albedo_color = Color(0.235, 0.008, 0.006, 1.0)
	_blot_material.roughness = 0.16
	_blot_material.metallic = 0.02

	_blot_mesh = SphereMesh.new()
	_blot_mesh.radius = 1.0
	_blot_mesh.height = 2.0
	_blot_mesh.radial_segments = 8
	_blot_mesh.rings = 4

	_drop_mesh = SphereMesh.new()
	_drop_mesh.radius = 1.0
	_drop_mesh.height = 2.0
	_drop_mesh.radial_segments = 5
	_drop_mesh.rings = 3

	_drop_material = StandardMaterial3D.new()
	# CPUParticles3D instance colors do not tint a StandardMaterial3D on the
	# compatibility renderer, so the blood tint lives on the shared material.
	_drop_material.albedo_color = Color(0.31, 0.022, 0.017, 1.0)
	_drop_material.vertex_color_use_as_albedo = false
	_drop_material.roughness = 0.48

	_splat_textures.clear()
	_patch_materials.clear()
	_soak_materials.clear()
	for variant in SPLAT_VARIANTS:
		var texture := _build_texture(0x51A7 + variant * 0x2C1, false)
		_splat_textures.append(texture)
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		material.render_priority = 0
		_patch_materials.append(material)
		# Unshaded flat colour: the stain reads as a dye on the cloth, not a
		# lit blob. A lit dark-red patch on a dark hood vanishes in shadow.
		var soak := StandardMaterial3D.new()
		soak.albedo_texture = _build_body_texture(0x9E37 + variant * 0x1F3)
		soak.albedo_color = [Color(1.0, 0.90, 0.88), Color(0.94, 0.80, 0.76),
			Color(0.86, 0.70, 0.66)][variant]
		soak.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		soak.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		soak.cull_mode = BaseMaterial3D.CULL_DISABLED
		soak.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		soak.render_priority = 1
		_soak_materials.append(soak)
	_pool_texture = _build_texture(0xB100D, true)
	_pool_material = StandardMaterial3D.new()
	_pool_material.albedo_texture = _pool_texture
	_pool_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pool_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pool_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_pool_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_footprint_material = StandardMaterial3D.new()
	_footprint_material.albedo_texture = _build_foot_texture()
	_footprint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_footprint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_footprint_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_footprint_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

## Builds a soft, irregular blood splat with a dark core and flung droplets.
## Deterministic per seed so the authored artwork stays stable.
static func _build_texture(seed_value: int, pool: bool) -> ImageTexture:
	var size := 192 if pool else 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.040 if pool else 0.055
	noise.fractal_octaves = 3
	var center := Vector2(float(size), float(size)) * 0.5
	var reach := float(size) * (0.42 if pool else 0.31)
	for y in size:
		for x in size:
			var point := Vector2(float(x) + 0.5, float(y) + 0.5)
			var radial := clampf(1.0 - point.distance_to(center) / reach, 0.0, 1.0)
			if radial <= 0.0:
				continue
			var grain := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var edge := radial * (0.52 + grain * 0.94)
			var alpha := smoothstep(0.14, 0.68, edge)
			if alpha <= 0.004:
				continue
			var shade := 0.52 + 0.48 * smoothstep(0.0, 1.0, radial)
			var color := Color(0.330 * shade + 0.045 * grain,
				0.0135 * shade + 0.004 * grain, 0.0105 * shade, alpha)
			image.set_pixel(x, y, color)
	var droplets := 88 if pool else 62
	for index in droplets:
		var angle := rng.randf() * TAU
		var distance := reach * rng.randf_range(0.50 if pool else 0.68,
			1.55 if pool else 1.92)
		var at := center + Vector2(cos(angle), sin(angle)) * distance
		var radius := rng.randf_range(0.8, 3.4 if pool else 2.6)
		var shade := rng.randf_range(0.42, 0.80)
		_paint_disc(image, at, radius,
			Color(0.320 * shade + 0.04, 0.013 * shade, 0.010 * shade,
				rng.randf_range(0.35, 0.94)))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

## Soaked cloth, not a dropped blob: a solid flat dye filling most of the patch
## with a thin crisp rim, plus a few faint specks at the edge. No ragged wicking
## or soft alpha ramp — at the centimetre sizes a wound uses, those read as a
## feathered bib rather than blood on the garment.
static func _build_body_texture(seed_value: int) -> ImageTexture:
	var size := 192
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.075
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.55
	var warp := FastNoiseLite.new()
	warp.seed = seed_value + 977
	warp.frequency = 0.024
	warp.fractal_octaves = 2
	var center := Vector2(float(size), float(size)) * 0.5
	# The core covers most of the patch: the texture is the stain, not a dot in
	# the middle with vanishing edges.
	var reach := float(size) * 0.46
	for y in size:
		for x in size:
			var point := Vector2(float(x) + 0.5, float(y) + 0.5)
			var offset := point - center
			# A light warp keeps the rim organic without bleeding it into a
			# feathered edge.
			var pull := warp.get_noise_2d(float(x), float(y)) * 0.08
			var radial := clampf(1.0 - offset.length() / reach - pull, 0.0, 1.0)
			if radial <= 0.0:
				continue
			var grain := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			# Flat dye, not a feathered bleed: a solid core with a thin, crisp
			# edge. The grain only nudges the rim so the stain is not a perfect
			# disc; it no longer erodes the fill into ragged soft edges.
			var edge := radial * (0.90 + grain * 0.20)
			var alpha := smoothstep(0.0, 0.10, edge)
			if alpha <= 0.004:
				continue
			# A wet core of fresh crimson; the wicking rim dries toward oxblood.
			# Unshaded, so these values are what the eye sees: kept a step below
			# pure saturation so the stain sits on the cloth instead of glowing.
			var shade := 0.65 + 0.35 * smoothstep(0.0, 0.85, radial)
			var color := Color((0.44 + 0.07 * grain) * shade,
				(0.042 + 0.013 * grain) * shade,
				(0.034 + 0.010 * grain) * shade, alpha)
			image.set_pixel(x, y, color)
	# A few small specks at the rim, kept flat and faint so they read as
	# spatter on the cloth, not separate blobs floating off it.
	for index in 24:
		var angle := rng.randf() * TAU
		var distance := reach * rng.randf_range(0.55, 1.0)
		var at := center + Vector2(cos(angle), sin(angle)) * distance
		var radius := rng.randf_range(0.4, 1.0)
		var shade := rng.randf_range(0.42, 0.80)
		_paint_disc(image, at, radius,
			Color(0.390 * shade + 0.02, 0.040 * shade, 0.032 * shade,
				rng.randf_range(0.25, 0.55)))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

## A footprint: a wide rounded forefoot (ball) at the toe and a smaller heel at
## the back, joined by a thin arch. Texture x runs heel-to-toe, y across the
## foot. Tread grooves (shoe lugs) and noise spottiness break up the shape so
## it reads as a real print, not a perfect vector foot.
##
## The canvas is 2.5:1 — the same ratio as the 25 cm x 10 cm patch `footprint`
## lays down — so the drawn foot fills the geometry instead of painting a small
## blob in the middle of a stretched quad, and pixels stay square on the ground.
static func _build_foot_texture() -> ImageTexture:
	var size := Vector2i(200, 80)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var blood := Color(0.42, 0.03, 0.025, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xF007
	var tread := FastNoiseLite.new()
	tread.seed = 0x77
	tread.frequency = 0.11
	tread.fractal_octaves = 2
	var spot := FastNoiseLite.new()
	spot.seed = 0x51A7
	spot.frequency = 0.09
	spot.fractal_octaves = 3
	# Three ellipses: forefoot (ball) at the toe, heel at the back, arch between.
	var fore := Vector2(0.70, 0.5)
	var fore_r := Vector2(0.24, 0.46)
	var heel := Vector2(0.20, 0.5)
	var heel_r := Vector2(0.18, 0.36)
	var arch := Vector2(0.45, 0.5)
	var arch_r := Vector2(0.13, 0.22)
	for y in size.y:
		for x in size.x:
			var p := Vector2((float(x) + 0.5) / float(size.x),
				(float(y) + 0.5) / float(size.y))
			var d_fore := ((p - fore) / fore_r).length()
			var d_heel := ((p - heel) / heel_r).length()
			var d_arch := ((p - arch) / arch_r).length()
			var d := minf(minf(d_fore, d_heel), d_arch)
			if d >= 1.0:
				continue
			var alpha := smoothstep(0.0, 0.18, clampf(1.0 - d, 0.0, 1.0))
			# Tread grooves: bands across the foot (varying heel-to-toe) thin the
			# print where a shoe sole has gaps, without cutting it apart.
			var groove := tread.get_noise_2d(float(x) * 0.5, float(y) * 0.12)
			if groove > 0.45:
				alpha *= 0.55
			# Spottiness: blotchy noise so the blood is not a perfect fill.
			var blotch := (spot.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			alpha *= 0.80 + blotch * 0.30
			# A few random dry specks where the blood did not reach.
			if rng.randf() < 0.015:
				alpha *= 0.5
			if alpha <= 0.01:
				continue
			image.set_pixel(x, y, Color(blood.r, blood.g, blood.b, alpha))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

static func _paint_disc(image: Image, center: Vector2, radius: float, color: Color) -> void:
	var low_x := maxi(0, int(floor(center.x - radius - 1.0)))
	var high_x := mini(image.get_width() - 1, int(ceil(center.x + radius + 1.0)))
	var low_y := maxi(0, int(floor(center.y - radius - 1.0)))
	var high_y := mini(image.get_height() - 1, int(ceil(center.y + radius + 1.0)))
	for y in range(low_y, high_y + 1):
		for x in range(low_x, high_x + 1):
			var distance := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(center)
			if distance > radius:
				continue
			var alpha := color.a * clampf((radius - distance) / maxf(radius * 0.45, 0.75),
				0.0, 1.0)
			if alpha <= 0.002:
				continue
			var under := image.get_pixel(x, y)
			image.set_pixel(x, y, Color(color.r, color.g, color.b,
				maxf(under.a, alpha)))
