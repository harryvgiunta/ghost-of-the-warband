extends SubViewportContainer
## The paperdoll's live mercenary: a second Archer rendered into its own
## SubViewport and dressed from the same `PlayerState.build_loadout()` shape the
## world rig uses. It never takes input and never joins the gameplay tree's
## collision or network state.

const Archer = preload("res://scripts/archer.gd")
const TrinketArt = preload("res://scripts/trinket_art.gd")

const RIM_COLOR := Color("e9bf76")

var rig
var viewport: SubViewport
var camera: Camera3D
var _built := false
## The kit and the look the stage is showing, kept so a rig rebuilt for a new
## body can be dressed with the same gear it was already wearing.
var _loadout: Dictionary = {}
var _trinkets: Dictionary = {}
var _appearance: Dictionary = {}

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	viewport = SubViewport.new()
	viewport.name = "CharacterViewport"
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Viewport.MSAA_4X
	add_child(viewport)
	camera = Camera3D.new()
	camera.fov = 28.0
	camera.near = 0.04
	camera.far = 30.0
	camera.look_at_from_position(Vector3(0.52,1.14,-4.02),Vector3(0.0,1.03,0.0),Vector3.UP)
	viewport.add_child(camera)
	camera.current = true
	_add_lights()
	_add_stage()
	rig = Archer.new()
	rig.name = "PreviewRanger"
	viewport.add_child(rig)
	rig.set_physics_process(false)
	built.emit()


signal built


func _add_lights() -> void:
	var key := DirectionalLight3D.new()
	key.name = "PreviewKey"
	key.rotation_degrees = Vector3(-34.0,-28.0,0.0)
	key.light_energy = 2.0
	key.light_color = Color("ffe9c8")
	key.shadow_enabled = true
	viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.name = "PreviewFill"
	fill.rotation_degrees = Vector3(-12.0,142.0,0.0)
	fill.light_energy = 0.8
	fill.light_color = Color("9dc6cc")
	viewport.add_child(fill)
	var rim := OmniLight3D.new()
	rim.name = "PreviewRim"
	rim.position = Vector3(-1.4,1.9,0.9)
	rim.light_energy = 1.4
	rim.light_color = RIM_COLOR
	rim.omni_range = 4.0
	viewport.add_child(rim)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0,0,0,0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("6d8e93")
	env.ambient_light_energy = 1.25
	environment.environment = env
	viewport.add_child(environment)


func _add_stage() -> void:
	var platform := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.62
	disc.bottom_radius = 0.68
	disc.height = 0.07
	disc.radial_segments = 48
	platform.mesh = disc
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("263a3d")
	material.roughness = 0.92
	material.metallic = 0.05
	platform.material_override = material
	platform.position = Vector3(0.0,-0.04,0.0)
	viewport.add_child(platform)


func apply_kit(loadout: Dictionary, trinkets: Dictionary) -> void:
	if not _built:
		return
	_loadout = loadout
	_trinkets = trinkets
	rig.apply_loadout(loadout)
	TrinketArt.apply(rig.skeleton,trinkets)


## Put one mercenary's body on the stage. The height a look carries is baked into
## the rig before the rig measures its own legs, so a different look means a
## different rig; the kit it was wearing is dressed again on the new one.
func set_appearance(profile: Dictionary) -> void:
	if not _built or profile == _appearance:
		return
	_appearance = profile.duplicate()
	if rig != null and is_instance_valid(rig):
		rig.queue_free()
	rig = Archer.new()
	rig.name = "PreviewRanger"
	rig.appearance = _appearance
	viewport.add_child(rig)
	rig.set_physics_process(false)
	if not _loadout.is_empty():
		apply_kit(_loadout, _trinkets)


func set_active(active: bool) -> void:
	if not _built:
		return
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active \
		else SubViewport.UPDATE_DISABLED
	rig.set_physics_process(active)
