extends SubViewportContainer
## The paperdoll's live mercenary: a second Archer rendered into its own
## SubViewport and dressed from the same `PlayerState.build_loadout()` shape the
## world rig uses. It never takes input and never joins the gameplay tree's
## collision or network state.

const Archer = preload("res://scripts/archer.gd")
const TrinketArt = preload("res://scripts/trinket_art.gd")

const RIM_COLOR := Color("e9bf76")
## Where the portrait camera aims when the rig cannot answer: a standing ranger's
## head is about this high.
const HEAD_FALLBACK := Vector3(0.0, 1.62, 0.0)
## How far off the head the bust camera stands, in head half-heights (the head is
## two of those tall), and how far above its centre it sits: a portrait looks
## slightly down on the face.
const BUST_STANDOFF := 8.8
const BUST_LIFT := 0.5
## How far the look target sits below the skull's centre, in head half-heights:
## the shoulders belong in the frame under it.
const BUST_DROP := 0.55
## How far round the head the camera stands, in degrees. The rig's own presentation
## pose turns the face a little; the camera turns with it so the portrait is a
## three-quarter view and not a profile.
const BUST_YAW := 16.0

var rig
var viewport: SubViewport
var camera: Camera3D
var platform: MeshInstance3D
var _built := false
## Head-and-shoulders instead of the whole figure (the HUD's portrait), and the
## frames a one-shot render still owes after `flash()`.
var _bust := false
var _flash := 0
var _active := false
## The kit and the look the stage is showing, kept so a rig rebuilt for a new
## body can be dressed with the same gear it was already wearing.
var _loadout: Dictionary = {}
var _trinkets: Dictionary = {}
var _appearance: Dictionary = {}
## How many annointments each held copy carries, so the ranger on the stage wears
## the same worked steel the body in the world does.
var _marks: Dictionary = {}

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	set_process(true)


## Render the frames a one-shot still owes and stop again. A portrait of a man who
## is standing still only changes when he is re-dressed, so it must not keep a
## whole 3D pass running: `flash()` draws it and the viewport goes back to sleep.
func _process(_delta: float) -> void:
	if _flash <= 0:
		return
	_flash -= 1
	if _flash == 0 and not _active:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


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
	_frame_camera()
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
	platform = MeshInstance3D.new()
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


func apply_kit(loadout: Dictionary, trinkets: Dictionary, marks: Dictionary = {}) -> void:
	if not _built:
		return
	_loadout = loadout
	_trinkets = trinkets
	_marks = marks
	rig.apply_loadout(loadout)
	rig.set_annoint_marks(_marks) if rig.has_method("set_annoint_marks") else null
	TrinketArt.apply(rig.skeleton,trinkets)
	_frame_camera()


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
		apply_kit(_loadout, _trinkets, _marks)
	_frame_camera()


func set_active(active: bool) -> void:
	if not _built:
		return
	_active = active
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active \
		else SubViewport.UPDATE_DISABLED
	rig.set_physics_process(active)


## Head and shoulders instead of the whole figure: the HUD's portrait is a bust,
## the gear page's stage is a man. The camera hangs off the head bone, so a taller
## mercenary is framed by his own skull rather than by a constant.
func set_bust(on: bool) -> void:
	if _bust == on:
		return
	_bust = on
	_frame_camera()


func flash(frames: int = 3) -> void:
	if not _built:
		return
	_flash = maxi(frames, 1)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _frame_camera() -> void:
	if not _built:
		return
	if platform != null:
		# A bust hangs in the frame the HUD draws behind it; the stage disc
		# belongs to the standing figure on the gear page.
		platform.visible = not _bust
	if not _bust:
		camera.fov = 28.0
		camera.look_at_from_position(Vector3(0.52,1.14,-4.02),Vector3(0.0,1.03,0.0),Vector3.UP)
		return
	var head := _head_centre()
	var half_height: float = maxf(_head_half_height(), 0.08)
	# The camera stands off the head by the head's own size and turns with the
	# pose, so a taller or broader mercenary is framed by his own skull.
	var distance: float = half_height * BUST_STANDOFF
	var yaw := deg_to_rad(BUST_YAW)
	var stand := Vector3(sin(yaw), 0.0, -cos(yaw)) * distance
	camera.fov = 34.0
	camera.look_at_from_position(head + Vector3(0.0, half_height * BUST_LIFT, 0.0) + stand,
		head + Vector3(0.0, -half_height * BUST_DROP, 0.0), Vector3.UP)


## Where the head is: the rig's own head point, the one an arrow is stopped by.
## A bone's origin sits at the neck, so it is the rig that knows where the skull
## ended up once its height and its pose are applied.
func _head_centre() -> Vector3:
	if rig != null and is_instance_valid(rig) and rig.has_method("head_hitbox_center"):
		return rig.head_hitbox_center()
	return HEAD_FALLBACK


func _head_half_height() -> float:
	if rig != null and is_instance_valid(rig) and rig.has_method("head_hit_profile"):
		return float((rig.head_hit_profile() as Vector2).y)
	return 0.14
