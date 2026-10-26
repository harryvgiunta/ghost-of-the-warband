class_name TextureLibrary
extends RefCounted
## Cached texture loading and shared materials for the world-art framework.
##
## Textures live in `res://assets/world/textures/<id>.png` (authored by
## tools/world_textures.py). Materials are cached per texture/kind so every
## chunk and scene reuses the same resource; nothing here runs per frame.
##
## Missing textures are a loud error plus a visible magenta checker fallback
## (a flat normal fallback for `*_n` maps), never a silent skip.

const TEXTURE_DIR := "res://assets/world/textures/"
const ATLAS_SIZE := 512.0

const FOLIAGE_SHADER: Shader = preload("res://scripts/world/shaders/foliage.gdshader")
const GRASS_SHADER: Shader = preload("res://scripts/world/shaders/grass.gdshader")
const TERRAIN_SHADER: Shader = preload("res://scripts/world/shaders/terrain.gdshader")
const GROUND_SHADER: Shader = preload("res://scripts/world/shaders/ground.gdshader")
const WATER_SHADER: Shader = preload("res://scripts/world/shaders/water.gdshader")
const FLAME_SHADER: Shader = preload("res://scripts/world/shaders/flame.gdshader")

# Atlas layouts, in cells. `inset` is the transparent gutter around each cell in
# pixels (8 px per side = the contracted 16 px gutter between neighbours).
const ATLAS_LAYOUTS := {
	"leaves_broadleaf": {"cols": 2, "rows": 2, "inset": 8},
	"leaves_amber": {"cols": 2, "rows": 2, "inset": 8},
	"leaves_birch": {"cols": 2, "rows": 2, "inset": 8},
	"needles_pine": {"cols": 2, "rows": 2, "inset": 8},
	"grass_meadow": {"cols": 2, "rows": 2, "inset": 0},
	"flowers": {"cols": 4, "rows": 2, "inset": 0},
	"fern": {"cols": 2, "rows": 2, "inset": 0},
	"flame": {"cols": 2, "rows": 2, "inset": 8},
}

const BUILDING_KINDS := {
	"wood": "wood_planks",
	"timber": "timber",
	"plaster": "plaster",
	"roof": "roof_shingles",
	"stone": "stone_blocks",
	"thatch": "thatch",
	"hide": "hide",
	"bone": "bone",
	"wattle": "wattle",
}

# Triplanar repeats per metre for each building kind.
const BUILDING_SCALE := {
	"wood": 0.6,
	"timber": 0.75,
	"plaster": 0.4,
	"roof": 0.9,
	"stone": 0.55,
	"thatch": 0.70,
	"hide": 0.90,
	"bone": 2.1,
	"wattle": 1.30,
}

static var _textures: Dictionary = {}
static var _loaded_ids: Dictionary = {}
static var _materials: Dictionary = {}
static var _reported: Dictionary = {}
static var _fallback: ImageTexture
static var _flat_normal: ImageTexture


## Loads (and caches) a texture by id. Returns a visible magenta checker when the
## file is absent so missing art shows up instead of failing silently.
static func texture(id: String) -> Texture2D:
	if _textures.has(id):
		return _textures[id]
	var tex: Texture2D = null
	var path := _path(id)
	if not id.is_empty() and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		_report_missing("World textures: missing '%s' (%s). Using checker fallback." % [id, path])
		tex = _fallback_texture()
	else:
		_loaded_ids[id] = true
	_textures[id] = tex
	return tex


## Bark material: tiled bark albedo + normal, roughness high. Vertex colour drives
## albedo so MultiMesh instance colours tint each tree.
static func bark_material(bark_id: String) -> StandardMaterial3D:
	var key := "bark:" + bark_id
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture(bark_id)
	material.albedo_color = Color.WHITE
	material.vertex_color_use_as_albedo = true
	material.normal_enabled = true
	material.normal_texture = _normal_texture(bark_id)
	material.normal_scale = 0.8
	material.roughness = 0.95
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials[key] = material
	return material


## Shared foliage material for an atlas. Scenes that want species-specific sway
## should use `foliage_material_tuned` so the cache key includes the wind vector.
static func foliage_material(leaves_id: String) -> ShaderMaterial:
	return foliage_material_tuned(leaves_id, Vector2(0.3, 1.0))


static func foliage_material_tuned(leaves_id: String, wind: Vector2) -> ShaderMaterial:
	var key := "foliage:%s:%s" % [leaves_id, str(wind)]
	if _materials.has(key):
		return _materials[key]
	var material := ShaderMaterial.new()
	material.shader = FOLIAGE_SHADER
	material.set_shader_parameter("albedo_texture", texture(leaves_id))
	material.set_shader_parameter("tint", Color.WHITE)
	material.set_shader_parameter("alpha_scissor", 0.38)
	material.set_shader_parameter("wind_strength", maxf(0.0, wind.x))
	material.set_shader_parameter("wind_speed", maxf(0.01, wind.y))
	material.set_shader_parameter("wind_scale", 0.3)
	_materials[key] = material
	return material


static func grass_material() -> ShaderMaterial:
	var key := "grass:grass_meadow"
	if _materials.has(key):
		return _materials[key]
	var material := _clump_material("grass_meadow", 0.16, 1.25, 0.14)
	_materials[key] = material
	return material


static func flower_material() -> ShaderMaterial:
	var key := "grass:flowers"
	if _materials.has(key):
		return _materials[key]
	var material := _clump_material("flowers", 0.07, 1.0, 0.9)
	_materials[key] = material
	return material


static func fern_material() -> ShaderMaterial:
	var key := "grass:fern"
	if _materials.has(key):
		return _materials[key]
	var material := _clump_material("fern", 0.05, 0.9, 0.95)
	_materials[key] = material
	return material


## Frontier terrain shader wired to the style's textures, tints and scales.
static func terrain_material(style: WorldStyle) -> ShaderMaterial:
	var style_id := "default" if style == null else style.id
	var key := "terrain:" + style_id
	if _materials.has(key):
		return _materials[key]
	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	if style != null:
		var ground: Dictionary = style.ground
		material.set_shader_parameter("grass_texture", texture(String(ground.get("grass_texture", "terrain_grass"))))
		material.set_shader_parameter("dirt_texture", texture(String(ground.get("dirt_texture", "terrain_dirt"))))
		material.set_shader_parameter("rock_texture", texture(String(ground.get("rock_texture", "terrain_rock"))))
		material.set_shader_parameter("macro_texture", texture(String(ground.get("macro_texture", "terrain_macro"))))
		material.set_shader_parameter("grass_tint", ground.get("grass_tint", Color.WHITE))
		material.set_shader_parameter("dirt_tint", ground.get("dirt_tint", Color.WHITE))
		material.set_shader_parameter("rock_tint", ground.get("rock_tint", Color.WHITE))
		material.set_shader_parameter("tile", float(ground.get("tile", 7.0)))
		material.set_shader_parameter("dirt_tile", float(ground.get("dirt_tile", 6.0)))
		material.set_shader_parameter("rock_tile", float(ground.get("rock_tile", 5.0)))
		material.set_shader_parameter("macro_tile", float(ground.get("macro_tile", 27.0)))
		material.set_shader_parameter("detail_strength", float(ground.get("detail_strength", 1.0)))
		material.set_shader_parameter("detail_fade", ground.get("detail_fade", Vector2(95.0, 150.0)))
	else:
		material.set_shader_parameter("grass_texture", texture("terrain_grass"))
		material.set_shader_parameter("dirt_texture", texture("terrain_dirt"))
		material.set_shader_parameter("rock_texture", texture("terrain_rock"))
		material.set_shader_parameter("macro_texture", texture("terrain_macro"))
	_materials[key] = material
	return material


## Flat arena floor shader (grass + macro variation, no dirt/rock blend).
static func ground_material(style: WorldStyle) -> ShaderMaterial:
	var style_id := "default" if style == null else style.id
	var key := "ground:" + style_id
	if _materials.has(key):
		return _materials[key]
	var material := ShaderMaterial.new()
	material.shader = GROUND_SHADER
	if style != null:
		var ground: Dictionary = style.ground
		material.set_shader_parameter("grass_texture", texture(String(ground.get("grass_texture", "terrain_grass"))))
		material.set_shader_parameter("macro_texture", texture(String(ground.get("macro_texture", "terrain_macro"))))
		material.set_shader_parameter("grass_tint", ground.get("grass_tint", Color.WHITE))
		material.set_shader_parameter("tile", float(ground.get("tile", 6.0)))
		material.set_shader_parameter("macro_tile", float(ground.get("macro_tile", 22.0)))
		material.set_shader_parameter("detail_strength", float(ground.get("detail_strength", 0.9)))
		material.set_shader_parameter("detail_fade", ground.get("detail_fade", Vector2(70.0, 120.0)))
	else:
		material.set_shader_parameter("grass_texture", texture("terrain_grass"))
		material.set_shader_parameter("macro_texture", texture("terrain_macro"))
	_materials[key] = material
	return material


## Bark material with an explicit albedo tint, for dead wood and split stakes.
## Same tiling and normal as `bark_material`, but the tint is authoritative
## instead of the per-instance vertex colour.
static func bark_material_tinted(bark_id: String, tint: Color) -> StandardMaterial3D:
	var key := "bark:%s:%s" % [bark_id, tint.to_html(false)]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture(bark_id)
	material.albedo_color = tint
	material.normal_enabled = true
	material.normal_texture = _normal_texture(bark_id)
	material.normal_scale = 0.8
	material.roughness = 0.95
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials[key] = material
	return material


## Granite surface for single carved props (fire stones, plinths): the boulder
## albedo and normal in world space, tinted instead of instance-coloured.
static func granite_material(tint: Color = Color.WHITE) -> StandardMaterial3D:
	var key := "granite:%s" % tint.to_html(false)
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture("rock")
	material.albedo_color = tint
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_triplanar_sharpness = 0.80
	material.uv1_scale = Vector3(0.9, 0.9, 0.9)
	material.normal_enabled = true
	material.normal_texture = _normal_texture("rock")
	material.normal_scale = 1.0
	material.roughness = 0.92
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials[key] = material
	return material


## Rock material: world-triplanar granite with a normal map, tintable per instance.
static func rock_material() -> StandardMaterial3D:
	var key := "rock"
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture("rock")
	material.albedo_color = Color.WHITE
	material.vertex_color_use_as_albedo = true
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_triplanar_sharpness = 0.85
	material.uv1_scale = Vector3(0.4, 0.4, 0.4)
	material.normal_enabled = true
	material.normal_texture = _normal_texture("rock")
	material.normal_scale = 1.0
	material.roughness = 0.92
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials[key] = material
	return material


## Triplanar building material. `kind` is one of "wood", "timber", "plaster",
## "roof", "stone". `tint` multiplies the albedo (use Color.WHITE for authoring).
static func building_material(kind: String, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var id: String = BUILDING_KINDS.get(kind, kind)
	var key := "building:%s:%s" % [kind, tint.to_html(false)]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture(id)
	material.albedo_color = tint
	# Buildings are ordinary BoxMesh props with no COLOR attribute; keep the
	# texture albedo authoritative instead of multiplying a possibly missing
	# vertex colour. Tinting is done through albedo_color.
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_triplanar_sharpness = 0.9
	var scale_at := float(BUILDING_SCALE.get(kind, 0.6))
	material.uv1_scale = Vector3(scale_at, scale_at, scale_at)
	material.roughness = 0.85
	# Kinds that author a matching normal map (thatch, hide, bone) get relief;
	# the plank/plaster/stone kinds stay flat until they author one too.
	var normal := _optional_texture(id + "_n")
	if normal != null:
		material.normal_enabled = true
		material.normal_texture = normal
		material.normal_scale = 0.9
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials[key] = material
	return material


## Animated flame cards: the authored 2x2 tongue atlas cycled by the flame shader.
static func flame_material() -> ShaderMaterial:
	var key := "flame"
	if _materials.has(key):
		return _materials[key]
	var material := ShaderMaterial.new()
	material.shader = FLAME_SHADER
	material.set_shader_parameter("albedo_texture", texture("flame"))
	material.set_shader_parameter("frame_rate", 11.0)
	material.set_shader_parameter("glow", 1.35)
	material.set_shader_parameter("waver", 0.016)
	_materials[key] = material
	return material


## Pond water. The optional normal map is used when present; otherwise the
## shader's cheap analytic ripple path takes over (water_normal.png is optional
## in the texture contract, so no error is raised for it).
static func water_material() -> ShaderMaterial:
	var key := "water"
	if _materials.has(key):
		return _materials[key]
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	var ripple := _optional_texture("water_normal")
	material.set_shader_parameter("ripple_texture", ripple if ripple != null else _flat_normal_texture())
	material.set_shader_parameter("ripple_on", 1.0 if ripple != null else 0.0)
	material.set_shader_parameter("shallow_color", Color("4f7c6d"))
	material.set_shader_parameter("deep_color", Color("1b3d40"))
	material.set_shader_parameter("sky_tint", Color("b7d3d6"))
	material.set_shader_parameter("ripple_strength", 0.34)
	material.set_shader_parameter("base_alpha", 0.85)
	_materials[key] = material
	return material


## UV rect of one atlas cell. Known layouts come from ATLAS_LAYOUTS; foliage
## atlases are inset by 8 px per side (16 px gutter between cells).
static func atlas_cell(texture_id: String, index: int) -> Rect2:
	var layout: Dictionary = ATLAS_LAYOUTS.get(texture_id, {"cols": 2, "rows": 2, "inset": 0})
	var cols := maxi(1, int(layout.get("cols", 2)))
	var rows := maxi(1, int(layout.get("rows", 2)))
	var total := cols * rows
	var cell_index := posmod(index, total)
	var column := cell_index % cols
	var row := int(cell_index / float(cols))
	var inset := float(layout.get("inset", 0)) / ATLAS_SIZE
	var cell_width := 1.0 / float(cols)
	var cell_height := 1.0 / float(rows)
	return Rect2(
		float(column) * cell_width + inset,
		float(row) * cell_height + inset,
		maxf(0.0001, cell_width - inset * 2.0),
		maxf(0.0001, cell_height - inset * 2.0)
	)


static func cell_count(texture_id: String) -> int:
	var layout: Dictionary = ATLAS_LAYOUTS.get(texture_id, {"cols": 2, "rows": 2})
	return maxi(1, int(layout.get("cols", 2)) * int(layout.get("rows", 2)))


## Number of distinct textures actually resolved (useful for generation_stats).
static func texture_count() -> int:
	return _loaded_ids.size()


static func _clump_material(texture_id: String, wind_strength: float, wind_speed: float, scissor: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GRASS_SHADER
	material.set_shader_parameter("albedo_texture", texture(texture_id))
	material.set_shader_parameter("tint", Color.WHITE)
	material.set_shader_parameter("alpha_scissor", scissor)
	material.set_shader_parameter("wind_strength", wind_strength)
	material.set_shader_parameter("wind_speed", wind_speed)
	material.set_shader_parameter("wind_scale", 0.45)
	material.set_shader_parameter("fade_start", 58.0)
	material.set_shader_parameter("fade_end", 72.0)
	return material


static func _path(id: String) -> String:
	return TEXTURE_DIR + id + ".png"


static func _normal_texture(base_id: String) -> Texture2D:
	var normal_id := base_id + "_n"
	var path := _path(normal_id)
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			_loaded_ids[normal_id] = true
			return tex
	_report_missing("World textures: missing normal '%s' (%s). Using flat normal fallback." % [normal_id, path])
	return _flat_normal_texture()


static func _optional_texture(id: String) -> Texture2D:
	var path := _path(id)
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex != null:
		_loaded_ids[id] = true
	return tex


static func _report_missing(message: String) -> void:
	if _reported.has(message):
		return
	_reported[message] = true
	push_error(message)


static func _fallback_texture() -> ImageTexture:
	if _fallback != null:
		return _fallback
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color("3a123f"))
	for y in range(0, 64, 16):
		for x in range(0, 64, 16):
			if ((x / 16) + (y / 16)) % 2 == 0:
				image.fill_rect(Rect2i(x, y, 16, 16), Color("ff3fd2"))
	_fallback = ImageTexture.create_from_image(image)
	return _fallback


static func _flat_normal_texture() -> ImageTexture:
	if _flat_normal != null:
		return _flat_normal
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.5, 0.5, 1.0, 1.0))
	_flat_normal = ImageTexture.create_from_image(image)
	return _flat_normal
