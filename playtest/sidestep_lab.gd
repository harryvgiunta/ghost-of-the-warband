extends Node3D
## Rapid, isolated playtest range for the shared grounded quick step.
## The plaza, the facing tree and the measured trace exist so the step's
## distance, shoulder turn and planted feet can be judged without the full
## frontier. Gameplay still runs through scripts/dodge_step.gd and scripts/archer.gd.

const Archer = preload("res://scripts/archer.gd")
const DodgeStep = preload("res://scripts/dodge_step.gd")
const WALK_SPEED := 5.5
const SPRINT_SPEED := 8.5
const PLATEAU_RADIUS := 12.0

var archer
var player: CharacterBody3D
var camera: Camera3D
var step
var camera_yaw := 0.0
var camera_pitch := 0.08
var camera_distance := 4.5
var stamina := 100.0
var _spawn := Vector3(0,0.15,0)
var _cursor_free := false
var _jump_requested := false
var _tracing := false
var _trace_start := Vector3.ZERO
var _last_distance := 0.0
var _last_duration := 0.0
var _step_time := 0.0
var _peak_speed := 0.0
var _info: Label
var _trace: MeshInstance3D
var _trace_start_cap: MeshInstance3D
var _trace_end_cap: MeshInstance3D
var _trace_label: Label3D
var _reticle: ColorRect

func _ready() -> void:
	_build_environment()
	_build_plateau()
	_build_trees()
	_build_player()
	_build_camera()
	_build_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("IRONWOOD_SIDESTEP_LAB_READY distance=%.2f duration=%.2f" % [DodgeStep.TRAVEL,DodgeStep.DURATION])

func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("789fab")
	sky_material.sky_horizon_color = Color("dfdbc0")
	sky_material.ground_bottom_color = Color("637057")
	sky_material.ground_horizon_color = Color("c5cbb2")
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("bed1d1")
	environment.ambient_light_energy = 0.48
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "LabSun"
	sun.rotation_degrees = Vector3(-48,-32,0)
	sun.light_color = Color("ffe2b3")
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

func _build_plateau() -> void:
	var body := StaticBody3D.new()
	body.name = "Plateau"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(PLATEAU_RADIUS*2.0,0.4,PLATEAU_RADIUS*2.0)
	collider.shape = shape
	collider.position = Vector3(0,-0.2,0)
	body.add_child(collider)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("63705a")
	material.roughness = 0.95
	mesh.material_override = material
	mesh.position = collider.position
	add_child(mesh)
	_add_grid()

func _add_grid() -> void:
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	var extent := 10
	for index in range(-extent,extent+1):
		var strong := index == 0
		var colour := Color("aeb99a") if strong else Color("7d8a70")
		var offset := float(index)
		lines.surface_set_color(colour)
		lines.surface_add_vertex(Vector3(offset,0.012,-extent))
		lines.surface_set_color(colour)
		lines.surface_add_vertex(Vector3(offset,0.012,extent))
		lines.surface_set_color(colour)
		lines.surface_add_vertex(Vector3(-extent,0.012,offset))
		lines.surface_set_color(colour)
		lines.surface_add_vertex(Vector3(extent,0.012,offset))
	lines.surface_end()
	var mesh := MeshInstance3D.new()
	mesh.name = "MetreGrid"
	mesh.mesh = lines
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh.material_override = material
	add_child(mesh)

func _build_trees() -> void:
	# The reference tree sits directly ahead of the spawn, the way a player
	# would line up on an obstacle before stepping around it.
	var placements := [
		Vector3(0,0,-2.8),
		Vector3(-5.2,0,-4.6),
		Vector3(5.2,0,-4.6),
		Vector3(-7.0,0,1.2),
		Vector3(7.0,0,1.2),
		Vector3(0,0,7.5),
		Vector3(-3.4,0,6.4),
		Vector3(3.4,0,6.4),
	]
	for index in placements.size():
		_add_tree(placements[index],5.4 if index == 0 else 6.5)

func _add_tree(point: Vector3, height: float) -> void:
	var body := StaticBody3D.new()
	body.position = point
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var trunk_height := height*0.62
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = height*0.045
	shape.height = trunk_height
	collider.shape = shape
	collider.position.y = trunk_height*0.5
	body.add_child(collider)
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.bottom_radius = height*0.05
	trunk_mesh.top_radius = height*0.034
	trunk_mesh.height = trunk_height
	trunk_mesh.radial_segments = 8
	trunk.mesh = trunk_mesh
	trunk.position.y = trunk_height*0.5
	trunk.material_override = _matte(Color("4d4032"))
	body.add_child(trunk)
	for layer in 3:
		var crown := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.bottom_radius = height*(0.20-float(layer)*0.04)
		cone.top_radius = 0.0
		cone.height = height*0.34
		cone.radial_segments = 8
		crown.mesh = cone
		crown.position.y = height*(0.44+float(layer)*0.16)
		crown.material_override = _matte(Color("315e49") if layer != 1 else Color("54805a"))
		body.add_child(crown)

func _matte(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.92
	return material

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.collision_layer = 4
	player.collision_mask = 1
	player.floor_snap_length = 0.6
	player.floor_max_angle = deg_to_rad(46.0)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.80
	var collider := CollisionShape3D.new()
	collider.position.y = 0.90
	collider.shape = capsule
	player.add_child(collider)
	add_child(player)
	player.global_position = _spawn
	archer = Archer.new()
	player.add_child(archer)
	archer.set_ground_sampler(func(_point: Vector3) -> float: return 0.0)
	archer.set_bow(1)
	archer.set_sword(1)
	archer.set_armor(0)
	step = DodgeStep.new()
	add_child(step)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "LabCamera"
	camera.fov = 59.0
	camera.near = 0.08
	camera.far = 120.0
	camera.current = true
	add_child(camera)
	_update_camera(1.0)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18,18)
	panel.custom_minimum_size = Vector2(430,0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04,0.07,0.07,0.78)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel",style)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",4)
	panel.add_child(box)
	var title := Label.new()
	title.text = "SIDESTEP LAB"
	title.add_theme_font_size_override("font_size",22)
	title.add_theme_color_override("font_color",Color("f0e3bd"))
	box.add_child(title)
	var controls := Label.new()
	controls.text = "WASD move   Shift sprint   Space jump\nQ / E quick step   Mouse look   Wheel zoom\nR reset to the tree   Esc release cursor"
	controls.add_theme_font_size_override("font_size",15)
	controls.add_theme_color_override("font_color",Color("b9c8b0"))
	box.add_child(controls)
	var tuning := Label.new()
	tuning.text = "Step %.2f m in %.2f s   %.1f stamina   %.2f s cooldown" % [DodgeStep.TRAVEL,DodgeStep.DURATION,DodgeStep.STAMINA_COST,DodgeStep.COOLDOWN]
	tuning.add_theme_font_size_override("font_size",15)
	tuning.add_theme_color_override("font_color",Color("9fc6a0"))
	box.add_child(tuning)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size",15)
	_info.add_theme_color_override("font_color",Color("e8e2cc"))
	box.add_child(_info)
	var reticle := ColorRect.new()
	reticle.color = Color(1,1,1,0.75)
	reticle.size = Vector2(4,4)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(reticle)
	_reticle = reticle
	_build_trace()

func _build_trace() -> void:
	_trace = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.035,0.014,1.0)
	_trace.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("e0b64f")
	_trace.material_override = material
	_trace.visible = false
	add_child(_trace)
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.055
	cap_mesh.bottom_radius = 0.055
	cap_mesh.height = 0.012
	var cap_material := StandardMaterial3D.new()
	cap_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cap_material.albedo_color = Color("b9e08d")
	_trace_start_cap = MeshInstance3D.new()
	_trace_start_cap.mesh = cap_mesh
	_trace_start_cap.material_override = cap_material
	_trace_start_cap.visible = false
	add_child(_trace_start_cap)
	_trace_end_cap = MeshInstance3D.new()
	_trace_end_cap.mesh = cap_mesh
	_trace_end_cap.material_override = cap_material
	_trace_end_cap.visible = false
	add_child(_trace_end_cap)
	_trace_label = Label3D.new()
	_trace_label.font_size = 64
	_trace_label.pixel_size = 0.0032
	_trace_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_trace_label.outline_size = 12
	_trace_label.modulate = Color("f3e6bd")
	_trace_label.visible = false
	add_child(_trace_label)

func _physics_process(delta: float) -> void:
	if player == null:
		return
	var was_stepping: bool = step.active
	step.advance(delta,player.is_on_floor())
	var input_vector := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if input_vector.length() > 1.0:
		input_vector = input_vector.normalized()
	if _cursor_free:
		input_vector = Vector2.ZERO
	var running: bool = Input.is_physical_key_pressed(KEY_SHIFT) and stamina > 1.0 and input_vector.length_squared() > 0.1
	var speed := SPRINT_SPEED if running else WALK_SPEED
	stamina = clampf(stamina + delta*(-19.0 if running else 13.0),0.0,100.0)
	var camera_right := Vector3(cos(camera_yaw),0,-sin(camera_yaw))
	var camera_back := Vector3(sin(camera_yaw),0,cos(camera_yaw))
	var direction := camera_right*input_vector.x + camera_back*input_vector.y
	var acceleration := 35.0 if player.is_on_floor() else 10.0
	player.velocity.x = move_toward(player.velocity.x,direction.x*speed,acceleration*delta)
	player.velocity.z = move_toward(player.velocity.z,direction.z*speed,acceleration*delta)
	if step.active:
		var step_velocity: Vector3 = step.velocity()
		player.velocity.x = step_velocity.x
		player.velocity.z = step_velocity.z
		_peak_speed = maxf(_peak_speed,Vector2(step_velocity.x,step_velocity.z).length())
	if was_stepping or step.active:
		_step_time += delta
	if _jump_requested:
		player.velocity.y = 7.0
	elif player.is_on_floor():
		player.velocity.y = -1.0
	else:
		player.velocity.y -= 20.0*delta
	_jump_requested = false
	var previous := player.global_position
	player.move_and_slide()
	var limit := PLATEAU_RADIUS-1.0
	player.position.x = clampf(player.position.x,-limit,limit)
	player.position.z = clampf(player.position.z,-limit,limit)
	var actual := (player.global_position-previous)/maxf(delta,0.0001)
	archer.set_step(step.progress if step.active else -1.0,step.direction)
	archer.set_locomotion(actual,player.is_on_floor())
	_track_step()

func _track_step() -> void:
	if _tracing and not step.active:
		_tracing = false
		var finish := player.global_position
		_last_distance = Vector2(finish.x-_trace_start.x,finish.z-_trace_start.z).length()
		_last_duration = _step_time
		_show_trace(_trace_start,finish)

func _show_trace(from: Vector3,to: Vector3) -> void:
	var flat_from := Vector3(from.x,0.02,from.z)
	var flat_to := Vector3(to.x,0.02,to.z)
	var offset := flat_to-flat_from
	if offset.length_squared() < 0.0001:
		return
	var middle := (flat_from+flat_to)*0.5
	var basis := Basis.looking_at(offset.normalized(),Vector3.UP).scaled(Vector3(1,1,offset.length()))
	_trace.global_transform = Transform3D(basis,middle)
	_trace_start_cap.global_position = flat_from+Vector3.UP*0.006
	_trace_end_cap.global_position = flat_to+Vector3.UP*0.006
	_trace_label.global_position = middle+Vector3.UP*0.28
	_trace_label.text = "%.2f m" % _last_distance
	_trace.visible = true
	_trace_start_cap.visible = true
	_trace_end_cap.visible = true
	_trace_label.visible = true

func _process(delta: float) -> void:
	_update_camera(delta)
	var view := get_viewport().get_visible_rect().size
	_reticle.position = view*0.5-_reticle.size*0.5
	_info.text = "Last step   %.2f m / %.2f s   peak %.1f m/s\nCooldown    %s\nStamina     %3.0f\nFacing      %.1f deg   (root stays put during a step)" % [
		_last_distance,_last_duration,_peak_speed,
		"READY" if step.cooldown_left <= 0.0 and not step.active else "%.2f s" % step.cooldown_left,
		stamina,
		rad_to_deg(archer.global_rotation.y)]

func _update_camera(_delta: float) -> void:
	if player == null:
		return
	var focus := player.global_position+Vector3.UP*1.05
	var back := Vector3(sin(camera_yaw)*cos(camera_pitch),sin(camera_pitch),cos(camera_yaw)*cos(camera_pitch))
	var desired := focus+back*camera_distance
	var query := PhysicsRayQueryParameters3D.create(focus,desired,1)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		desired = hit.position+back.normalized()*0.12
	desired.y = maxf(desired.y,0.28)
	camera.global_position = desired
	camera.look_at(camera.global_position-back)

func quick_step(side: int) -> void:
	if side == 0 or _cursor_free:
		return
	var direction: Vector3 = Vector3(cos(camera_yaw),0,-sin(camera_yaw))*signf(float(side))
	if not step.try_step(direction,player.is_on_floor(),false):
		return
	_step_time = 0.0
	_peak_speed = 0.0
	_tracing = true
	_trace_start = player.global_position
	_trace.visible = false
	_trace_start_cap.visible = false
	_trace_end_cap.visible = false
	_trace_label.visible = false
	stamina = maxf(0.0,stamina-DodgeStep.STAMINA_COST)

func _reset() -> void:
	step.reset()
	player.global_position = _spawn
	player.velocity = Vector3.ZERO
	archer.set_step(-1.0,Vector3.FORWARD)
	archer.global_basis = Basis.IDENTITY
	archer.set_locomotion(Vector3.ZERO,true)
	camera_yaw = 0.0
	camera_pitch = 0.08
	camera_distance = 4.5
	stamina = 100.0
	_last_distance = 0.0
	_last_duration = 0.0
	_step_time = 0.0
	_peak_speed = 0.0
	_tracing = false
	_trace.visible = false
	_trace_start_cap.visible = false
	_trace_end_cap.visible = false
	_trace_label.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q: quick_step(-1)
			KEY_E: quick_step(1)
			KEY_R: _reset()
			KEY_SPACE: _jump_requested = true
			KEY_ESCAPE:
				_set_cursor_free(not _cursor_free)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and _cursor_free:
			_set_cursor_free(false)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = maxf(2.7,camera_distance-0.45)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = minf(9.0,camera_distance+0.45)
	if event is InputEventMouseMotion and not _cursor_free:
		camera_yaw -= event.relative.x*0.004
		camera_pitch = clampf(camera_pitch+event.relative.y*0.004,-0.7,0.7)

func _set_cursor_free(value: bool) -> void:
	_cursor_free = value
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_instance_valid(archer):
		_set_cursor_free(true)
