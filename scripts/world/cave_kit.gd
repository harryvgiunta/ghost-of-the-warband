class_name CaveKit
extends RefCounted
## The Weeping Hollow's authored kit at runtime: the tileable rock sets, the
## formation and fauna meshes and the web from `assets/world/cave/` (built by
## `python tools/build_cave_kit.py` in Blender from CC0 Poly Haven scans), and the
## look each area of the cave dresses them in.
##
## Everything is loaded once and cached; nothing here runs per frame. A missing
## file is a loud error naming the rebuild command, never a silent stand-in.

const DIR := "res://assets/world/cave/"
const ROCK_SHADER: Shader = preload("res://scripts/world/shaders/cave_rock.gdshader")
const FAUNA_SHADER: Shader = preload("res://scripts/world/shaders/cave_fauna.gdshader")
const GLOW_SHADER: Shader = preload("res://scripts/world/shaders/cave_glow.gdshader")
const SHAFT_SHADER: Shader = preload("res://scripts/world/shaders/light_shaft.gdshader")

## Metres one tile of each set covers on a wall. The scans are 1.8-3 m tiles; a
## cave wall reads bigger than a cliff photographed at arm's length, so each is
## laid a little larger than it was shot.
const SET_METRES := {"limestone": 3.4, "strata": 4.2, "basalt": 3.9, "silt": 3.0}

## How each area of the floor is dressed. `set` is the wall rock; `rock` and
## `floor` tint the rock and the silt; `formation` tints the dripstone and the
## breakdown; `wet` darkens and glosses (pools on the floor when `pools`),
## `streaks` is water down the walls, `growth` the film on damp stone near the
## floor (in `growth_tint`), `stain` what the water leaves behind. `fog`, `haze`
## (exponential density) and `ambient` are the air the eye breathes there.
const AREAS := {
	"mouth": {"set": "limestone", "rock": Color(1.0, 0.96, 0.9), "floor": Color(1.0, 0.95, 0.88),
		"formation": Color(0.9, 0.86, 0.78), "wet": 0.12, "streaks": 0.45, "growth": 0.0, "pools": 0.0,
		"stain": Color(0.66, 0.54, 0.42), "growth_tint": Color(0.24, 0.3, 0.18),
		"fog": Color(0.10, 0.085, 0.07), "haze": 0.016, "ambient": Color(0.48, 0.44, 0.40)},
	"den": {"set": "limestone", "rock": Color(0.95, 0.86, 0.76), "floor": Color(0.95, 0.86, 0.76),
		"formation": Color(0.84, 0.75, 0.64), "wet": 0.05, "streaks": 0.3, "growth": 0.0, "pools": 0.0,
		"stain": Color(0.6, 0.48, 0.36), "growth_tint": Color(0.24, 0.3, 0.18),
		"fog": Color(0.11, 0.08, 0.06), "haze": 0.018, "ambient": Color(0.50, 0.42, 0.36)},
	"gallery": {"set": "basalt", "rock": Color(0.92, 1.0, 1.08), "floor": Color(0.82, 0.9, 0.96),
		"formation": Color(0.66, 0.76, 0.8), "wet": 0.7, "streaks": 0.85, "growth": 0.25, "pools": 0.8,
		"stain": Color(0.5, 0.62, 0.62), "growth_tint": Color(0.12, 0.26, 0.26),
		"fog": Color(0.045, 0.075, 0.085), "haze": 0.022, "ambient": Color(0.30, 0.42, 0.50)},
	"ossuary": {"set": "limestone", "rock": Color(1.08, 1.04, 0.97), "floor": Color(1.05, 1.0, 0.93),
		"formation": Color(1.0, 0.97, 0.9), "wet": 0.04, "streaks": 0.25, "growth": 0.0, "pools": 0.0,
		"stain": Color(0.7, 0.62, 0.5), "growth_tint": Color(0.24, 0.3, 0.18),
		"fog": Color(0.11, 0.10, 0.085), "haze": 0.016, "ambient": Color(0.52, 0.49, 0.44)},
	"garden": {"set": "limestone", "rock": Color(0.93, 1.0, 0.92), "floor": Color(0.9, 0.96, 0.86),
		"formation": Color(0.86, 0.94, 0.82), "wet": 0.35, "streaks": 0.55, "growth": 0.6, "pools": 0.3,
		"stain": Color(0.55, 0.62, 0.46), "growth_tint": Color(0.2, 0.32, 0.14),
		"fog": Color(0.06, 0.09, 0.07), "haze": 0.02, "ambient": Color(0.36, 0.48, 0.40)},
	"mere": {"set": "basalt", "rock": Color(0.95, 0.98, 1.06), "floor": Color(0.86, 0.9, 0.96),
		"formation": Color(0.76, 0.81, 0.86), "wet": 0.55, "streaks": 0.75, "growth": 0.12, "pools": 0.65,
		"stain": Color(0.56, 0.6, 0.66), "growth_tint": Color(0.14, 0.24, 0.24),
		"fog": Color(0.035, 0.045, 0.065), "haze": 0.014, "ambient": Color(0.30, 0.36, 0.48)},
	"chapel": {"set": "limestone", "rock": Color(1.05, 0.95, 0.83), "floor": Color(1.0, 0.92, 0.8),
		"formation": Color(0.96, 0.86, 0.72), "wet": 0.05, "streaks": 0.3, "growth": 0.0, "pools": 0.0,
		"stain": Color(0.66, 0.5, 0.36), "growth_tint": Color(0.24, 0.3, 0.18),
		"fog": Color(0.11, 0.08, 0.05), "haze": 0.016, "ambient": Color(0.52, 0.43, 0.34)},
	"rooted": {"set": "strata", "rock": Color(0.95, 0.86, 0.74), "floor": Color(0.88, 0.78, 0.64),
		"formation": Color(0.8, 0.7, 0.56), "wet": 0.25, "streaks": 0.4, "growth": 0.4, "pools": 0.1,
		"stain": Color(0.5, 0.42, 0.3), "growth_tint": Color(0.22, 0.26, 0.12),
		"fog": Color(0.085, 0.075, 0.055), "haze": 0.018, "ambient": Color(0.44, 0.40, 0.32)},
	"workings": {"set": "strata", "rock": Color(1.0, 0.92, 0.8), "floor": Color(0.98, 0.9, 0.78),
		"formation": Color(0.86, 0.77, 0.63), "wet": 0.05, "streaks": 0.25, "growth": 0.0, "pools": 0.0,
		"stain": Color(0.62, 0.48, 0.34), "growth_tint": Color(0.24, 0.3, 0.18),
		"fog": Color(0.12, 0.10, 0.07), "haze": 0.022, "ambient": Color(0.50, 0.44, 0.36)},
	"lair": {"set": "strata", "rock": Color(1.05, 0.8, 0.7), "floor": Color(0.95, 0.72, 0.62),
		"formation": Color(0.86, 0.62, 0.52), "wet": 0.15, "streaks": 0.5, "growth": 0.0, "pools": 0.1,
		"stain": Color(0.5, 0.24, 0.2), "growth_tint": Color(0.24, 0.3, 0.18),
		"fog": Color(0.12, 0.05, 0.04), "haze": 0.018, "ambient": Color(0.52, 0.34, 0.30)},
}

static var _textures: Dictionary = {}
static var _scenes: Dictionary = {}
static var _materials: Dictionary = {}
static var _reported: Dictionary = {}


# --- meshes ------------------------------------------------------------------------

## A formation piece by name (`StalagmiteTall`, `StalactiteCarrot`, `Column`,
## `BoulderA` ... see `cave_kit.json`): floor pieces stand on their origin, roof
## pieces hang from it. Empty when the kit is missing.
static func formation(piece: String) -> Mesh:
	return _mesh("cave_formations.glb", "Formation_" + piece)


## A fungus piece by name: `CapGiant` (about 2.6 m to the cap's crown) and
## `CapCluster` stand on their origin; a `Shelf` (three brackets) has its back on
## the origin's XY plane and grows out along +Z.
static func flora(piece: String) -> Mesh:
	return _mesh("cave_flora.glb", "Flora_" + piece)


## A fauna mesh by name (`Bat`, `Rat`, `Spider`, `Moth`), facing -Z.
static func fauna(piece: String) -> Mesh:
	return _mesh("cave_fauna.glb", "Fauna_" + piece)


static func _mesh(file: String, node_name: String) -> Mesh:
	var entry: Dictionary = _scene(file).get(node_name, {})
	if entry.is_empty():
		_report("CaveKit: %s has no '%s'. Rebuild with: python tools/build_cave_kit.py" % [file, node_name])
		return ArrayMesh.new()
	return entry["mesh"]


static func _scene(file: String) -> Dictionary:
	if _scenes.has(file):
		return _scenes[file]
	var out := {}
	var path := DIR + file
	var packed: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if packed == null:
		_report("CaveKit: missing %s. Rebuild with: python tools/build_cave_kit.py" % path)
	else:
		var root := packed.instantiate()
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var holder := node as MeshInstance3D
			out[str(holder.name)] = {"mesh": holder.mesh, "material": holder.get_active_material(0)}
		root.free()
	_scenes[file] = out
	return out


# --- materials -----------------------------------------------------------------------

## An area's stone for one part of a room: `wall` (and the skins over it), `floor`
## or `roof`. One shader, the area's set and tints; cached.
static func rock_material(area: String, part: String) -> ShaderMaterial:
	var key := "rock:%s:%s" % [area, part]
	if _materials.has(key):
		return _materials[key]
	var spec: Dictionary = AREAS.get(area, AREAS["mouth"])
	var set_id := str(spec["set"])
	var material := ShaderMaterial.new()
	material.shader = ROCK_SHADER
	material.set_shader_parameter("rock_albedo", texture("cave_%s_albedo" % set_id))
	material.set_shader_parameter("rock_normal", texture("cave_%s_normal" % set_id))
	material.set_shader_parameter("rock_orh", texture("cave_%s_orh" % set_id))
	material.set_shader_parameter("floor_albedo", texture("cave_silt_albedo"))
	material.set_shader_parameter("floor_normal", texture("cave_silt_normal"))
	material.set_shader_parameter("floor_orh", texture("cave_silt_orh"))
	material.set_shader_parameter("noise_texture", TextureLibrary.texture("terrain_noise"))
	material.set_shader_parameter("rock_tile", 1.0 / float(SET_METRES[set_id]))
	material.set_shader_parameter("floor_tile", 1.0 / float(SET_METRES["silt"]))
	material.set_shader_parameter("rock_tint", spec["rock"])
	material.set_shader_parameter("floor_tint", spec["floor"])
	material.set_shader_parameter("stain_tint", spec["stain"])
	material.set_shader_parameter("growth_tint", spec["growth_tint"])
	material.set_shader_parameter("wetness", float(spec["wet"]))
	material.set_shader_parameter("streaks", float(spec["streaks"]))
	material.set_shader_parameter("growth", float(spec["growth"]))
	match part:
		"floor":
			material.set_shader_parameter("floor_mode", 1.0)
			material.set_shader_parameter("sediment", 1.0)
			material.set_shader_parameter("pools", float(spec["pools"]))
		"roof":
			material.set_shader_parameter("sediment", 0.0)
			material.set_shader_parameter("streaks", 0.0)
		_:
			material.set_shader_parameter("sediment", 0.65)
	_materials[key] = material
	return material


## The kit's baked fungus material, its gills glowing `glow` at `energy`. Shares
## the atlas; the baked emission map says where the light is, `glow` its colour.
static func flora_material(glow: Color, energy: float) -> Material:
	var key := "flora:%s:%.2f" % [glow.to_html(false), energy]
	if _materials.has(key):
		return _materials[key]
	var source: Material = _scene("cave_flora.glb").get("Flora_CapGiant", {}).get("material")
	var material: StandardMaterial3D = null
	if source is StandardMaterial3D:
		material = (source as StandardMaterial3D).duplicate()
	else:
		_report("CaveKit: the flora kit has no baked material. Rebuild with: python tools/build_cave_kit.py")
		material = StandardMaterial3D.new()
	material.emission_enabled = true
	material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	material.emission = glow
	material.emission_energy_multiplier = energy
	# The baked caps are pale: under the fungus's own light they read as pallid
	# flesh at this, not as white plastic.
	material.albedo_color = Color(0.6, 0.63, 0.58)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials[key] = material
	return material


## The kit's baked dripstone/breakdown material, tinted for an area (wet areas
## glossier). Shares the atlas; only the parameters are the area's.
static func formation_material(area: String) -> Material:
	var key := "formation:%s" % area
	if _materials.has(key):
		return _materials[key]
	var source: Material = _scene("cave_formations.glb").get("Formation_StalagmiteTall", {}).get("material")
	var material: StandardMaterial3D = null
	if source is StandardMaterial3D:
		material = (source as StandardMaterial3D).duplicate()
	else:
		_report("CaveKit: the formation kit has no baked material. Rebuild with: python tools/build_cave_kit.py")
		material = StandardMaterial3D.new()
	var spec: Dictionary = AREAS.get(area, AREAS["mouth"])
	material.albedo_color = spec["formation"]
	material.roughness = lerpf(1.0, 0.55, float(spec["wet"]))
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials[key] = material
	return material


## The fauna's vertex-coloured, vertex-animated material for one kind (0 bat,
## 1 rat, 2 spider, 3 moth).
static func fauna_material(kind: int) -> ShaderMaterial:
	var key := "fauna:%d" % kind
	if _materials.has(key):
		return _materials[key]
	var material := ShaderMaterial.new()
	material.shader = FAUNA_SHADER
	material.set_shader_parameter("kind", kind)
	_materials[key] = material
	return material


## Glowworm threads: a cold point of light at the roof, a beaded thread below.
static func glow_material(colour: Color) -> ShaderMaterial:
	var key := "glow:%s" % colour.to_html(false)
	if _materials.has(key):
		return _materials[key]
	var material := ShaderMaterial.new()
	material.shader = GLOW_SHADER
	material.set_shader_parameter("glow", colour)
	_materials[key] = material
	return material


## The light that falls down a shaft: an additive cone, brightest at the hole.
static func shaft_material(colour: Color, height: float) -> ShaderMaterial:
	var key := "shaft:%s:%.2f" % [colour.to_html(false), height]
	if _materials.has(key):
		return _materials[key]
	var material := ShaderMaterial.new()
	material.shader = SHAFT_SHADER
	material.set_shader_parameter("colour", colour)
	material.set_shader_parameter("height", height)
	material.set_shader_parameter("noise_texture", TextureLibrary.texture("terrain_noise"))
	_materials[key] = material
	return material


## Old silk across a corner: the rendered web, lit by whatever torch finds it.
static func web_material() -> StandardMaterial3D:
	var key := "web"
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture("cave_web")
	material.albedo_color = Color(0.86, 0.85, 0.8, 0.8)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.55
	material.emission_enabled = true
	material.emission_texture = texture("cave_web")
	material.emission = Color(0.1, 0.1, 0.1)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials[key] = material
	return material


# --- textures ---------------------------------------------------------------------------

static func texture(id: String) -> Texture2D:
	if _textures.has(id):
		return _textures[id]
	var path := DIR + "textures/" + id + ".png"
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if tex == null:
		_report("CaveKit: missing texture %s. Rebuild with: python tools/build_cave_kit.py" % path)
		tex = TextureLibrary.texture("")
	_textures[id] = tex
	return tex


static func _report(message: String) -> void:
	if _reported.has(message):
		return
	_reported[message] = true
	push_error(message)
