extends Node3D
## The Hollow: out-of-raid staging. The ranger, their kit, three vendors and the
## four ways out — arena skirmish, host, join, or the open frontier.

const Archer = preload("res://scripts/archer.gd")
const Geo = preload("res://scripts/geo.gd")
const StateScript = preload("res://scripts/player_state.gd")
const SessionScript = preload("res://scripts/session.gd")
const HubHud = preload("res://scripts/menu_hud.gd")
const SKIRMISH_PORT := 7777

var state
var session
var hud
var archer
var camera: Camera3D
var state_override: Node = null
var session_override: Node = null
var _yaw := 0.0
var _pitch := 0.11
var _distance := 4.4
var _dragging := false
var _focus := Vector3(0,1.02,0)
var _lanterns: Array[OmniLight3D] = []
var _lantern_energy: Array[float] = []
var _time := 0.0

func _ready() -> void:
	_resolve_services()
	_build_environment()
	_build_ground()
	_build_stalls()
	_build_character()
	_build_camera()
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HubHud.new()
	layer.add_child(hud)
	hud.configure(state,session)
	hud.mode_selected.connect(_on_mode_selected)
	hud.host_confirmed.connect(_on_host_confirmed)
	hud.join_confirmed.connect(_on_join_confirmed)
	hud.buy_requested.connect(_on_buy)
	hud.equip_requested.connect(_on_equip)
	hud.stash_requested.connect(_on_stash)
	hud.unstash_requested.connect(_on_unstash)
	hud.sell_requested.connect(_on_sell)
	state.changed.connect(_refresh)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("IRONWOOD_HUB_READY credits=%d inventory=%d/%d stash=%d/%d" % [state.credits,state.inventory.size(),state.INVENTORY_CAPACITY,state.stash.size(),state.STASH_CAPACITY])

func _resolve_services() -> void:
	state = state_override
	if state == null:
		state = get_node_or_null("/root/PlayerState")
	if state == null:
		state = StateScript.new()
		state.name = "PlayerStateFallback"
		add_child(state)
	session = session_override
	if session == null:
		session = get_node_or_null("/root/Session")
	if session == null:
		session = SessionScript.new()
		session.name = "SessionFallback"
		add_child(session)

func _process(delta: float) -> void:
	_time += delta
	_update_camera()
	for index in _lanterns.size():
		_lanterns[index].light_energy = _lantern_energy[index] * (0.90 + 0.10 * sin(_time * 2.7 + float(index) * 1.9))

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if hud != null and hud.is_form_open():
			hud.close_form()
			get_viewport().set_input_as_handled()
		return
	var over_ui := _over_hud_control()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = not over_ui
			else:
				_dragging = false
		elif event.pressed and not over_ui and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(2.8,_distance - 0.35)
		elif event.pressed and not over_ui and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(7.0,_distance + 0.35)
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * 0.008
		_pitch = clampf(_pitch + event.relative.y * 0.004,-0.04,0.55)

func _over_hud_control() -> bool:
	if hud == null:
		return false
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and hovered != hud

func _refresh() -> void:
	if hud != null:
		hud.refresh()
	_apply_preview_loadout()

func _apply_preview_loadout() -> void:
	if archer == null or state == null:
		return
	archer.set_bow(state.equipped_index("bow"))
	archer.set_sword(state.equipped_index("sword"))
	archer.set_armor(state.equipped_index("armor"))

func _on_buy(item_id: String) -> void:
	var result: Dictionary = state.buy(item_id)
	hud.set_status(str(result.message))

func _on_equip(index: int) -> void:
	var result: Dictionary = state.equip(index)
	hud.set_status(str(result.message))

func _on_stash(index: int) -> void:
	var result: Dictionary = state.move_to_stash(index)
	hud.clear_selection()
	hud.refresh()
	hud.set_status(str(result.message))

func _on_unstash(index: int) -> void:
	var result: Dictionary = state.move_to_inventory(index)
	hud.clear_selection()
	hud.refresh()
	hud.set_status(str(result.message))

func _on_sell(location: String, index: int) -> void:
	var result: Dictionary = state.sell(location,index)
	hud.clear_selection()
	hud.refresh()
	hud.set_status(str(result.message))

func _on_mode_selected(mode: String) -> void:
	if mode == "pve":
		_enter_frontier()
	elif mode == "skirmish":
		_open_arena("skirmish","127.0.0.1",SKIRMISH_PORT,_preferred_name())

func _on_host_confirmed(port: int, player_name: String) -> void:
	_open_arena("host","127.0.0.1",port,player_name)

func _on_join_confirmed(address: String, port: int, player_name: String) -> void:
	_open_arena("client",address,port,player_name)

func _preferred_name() -> String:
	var value := str(session.player_name).strip_edges()
	if value.is_empty() or value == "Ranger":
		var cache := get_node_or_null("/root/NetCache")
		if cache != null:
			value = str(cache.player_name)
	return "Ranger" if value.is_empty() else value.left(16)

func _open_arena(mode: String, address: String, port: int, player_name: String) -> void:
	session.player_name = player_name
	session.arm_arena(mode,address,port,player_name)
	var cache := get_node_or_null("/root/NetCache")
	if cache != null:
		# Hosting should not overwrite the address of the last host this player
		# joined; only a join updates it.
		cache.remember(player_name,address if mode == "client" else "",port)
	state.save_state()
	get_tree().change_scene_to_file("res://arena.tscn")

func _enter_frontier() -> void:
	state.save_state()
	get_tree().change_scene_to_file("res://main.tscn")

func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("09141a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("9ab7ba")
	environment.ambient_light_energy = 0.52
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = true
	environment.fog_light_color = Color("2b4147")
	environment.fog_light_energy = 0.8
	environment.fog_density = 0.035
	environment.fog_sky_affect = 0.0
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var moon := DirectionalLight3D.new()
	moon.name = "HollowMoon"
	moon.rotation_degrees = Vector3(-58,-26,0)
	moon.light_color = Color("a9c3cb")
	moon.light_energy = 0.55
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 40.0
	moon.shadow_bias = 0.05
	add_child(moon)

func _build_ground() -> void:
	var earth := Geo.material(Color("2a2a21"),0.0,1.0)
	var stone := Geo.material(Color("3d3a30"),0.05,0.92)
	var wood := Geo.material(Color("4a3626"),0.0,0.85)
	Geo.cylinder(self,14.0,14.0,0.4,Vector3(0,-0.2,0),earth,32)
	Geo.cylinder(self,6.2,6.4,0.1,Vector3(0,0.01,0),stone,32)
	for index in 10:
		var angle := TAU * float(index) / 10.0 + 0.18
		var radius := 6.9
		var rock := Geo.box(self,Vector3(0.7,0.28,0.5),Vector3(cos(angle)*radius,0.14,sin(angle)*radius),stone)
		rock.rotation.y = angle
	# A dark treeline closes the clearing without any collision or navigation cost.
	for index in 14:
		var angle := TAU * float(index) / 14.0 + 0.09
		var radius := 10.5 + 1.7 * absf(sin(float(index) * 2.3))
		var trunk := Geo.cylinder(self,0.28,0.2,6.5,Vector3(cos(angle)*radius,3.2,sin(angle)*radius),wood,7)
		trunk.rotation.y = angle
		var canopy := Geo.cylinder(self,0.0,1.9,4.6,Vector3(cos(angle)*radius,7.7,sin(angle)*radius),Geo.material(Color("17261f")),8)
		canopy.rotation.y = angle

func _build_stalls() -> void:
	_stall(Vector3(-3.35,0,-1.15),Color("2f4d55"),"FLETCHER","bows")
	_stall(Vector3(3.25,0,-1.05),Color("5b3a2b"),"SMITH","swords")
	_stall(Vector3(0.35,0,-3.45),Color("33472f"),"QUARTERMASTER","armor")
	var key := OmniLight3D.new()
	key.name = "HollowKeyLight"
	key.position = Vector3(1.5,2.9,2.8)
	key.light_color = Color("ffe2bd")
	key.light_energy = 1.7
	key.omni_range = 9.0
	add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.6,2.4,-2.0)
	rim.light_color = Color("7fb6c4")
	rim.light_energy = 1.2
	rim.omni_range = 7.0
	add_child(rim)

func _stall(origin: Vector3, canvas_color: Color, title: String, kind: String) -> void:
	var stall := Node3D.new()
	stall.position = origin
	stall.rotation.y = atan2(-origin.x,-origin.z)
	add_child(stall)
	var wood := Geo.material(Color("3c2b1e"),0.0,0.9)
	var cloth := Geo.material(canvas_color,0.0,0.95)
	Geo.box(stall,Vector3(2.3,0.92,0.72),Vector3(0,0.46,0.32),wood)
	Geo.box(stall,Vector3(2.42,0.08,0.82),Vector3(0,0.94,0.32),Geo.material(Color("6a5138"),0.0,0.8))
	for side in [-1.0,1.0]:
		Geo.cylinder(stall,0.07,0.06,2.5,Vector3(side*1.12,1.25,0.02),wood,7)
	var awning := Geo.box(stall,Vector3(2.7,0.08,1.35),Vector3(0,2.52,0.28),cloth)
	awning.rotation.x = -0.14
	Geo.box(stall,Vector3(2.24,1.05,0.10),Vector3(0,1.55,-0.32),Geo.material(Color("2b231a"),0.0,0.9))
	match kind:
		"bows":
			for index in 3:
				var x := -0.62 + float(index) * 0.62
				Geo.beam(stall,Vector3(x-0.05,0.98,-0.25),Vector3(x+0.16,1.65,-0.25),0.022,Geo.material(Color("8a6a3c"),0.1,0.7),6)
				Geo.beam(stall,Vector3(x-0.05,0.98,-0.22),Vector3(x-0.12,1.62,-0.14),0.007,Geo.material(Color("cfc3a4")),4)
			Geo.box(stall,Vector3(0.55,0.24,0.4),Vector3(0.72,1.06,0.28),Geo.material(Color("5a4a32"),0.0,0.9))
		"swords":
			var steel := Geo.material(Color("9aa8aa"),0.75,0.35)
			for index in 3:
				var blade := Geo.box(stall,Vector3(0.07,1.15,0.025),Vector3(-0.55+float(index)*0.4,1.55,-0.22),steel)
				blade.rotation.z = 0.16 - float(index) * 0.12
				Geo.box(stall,Vector3(0.26,0.06,0.07),Vector3(-0.62+float(index)*0.4,1.02,-0.22),wood)
			var stump := Geo.cylinder(stall,0.22,0.2,0.55,Vector3(0.65,0.27,0.28),wood,8)
			stump.rotation.y = 0.3
			Geo.box(stall,Vector3(0.52,0.22,0.3),Vector3(0.65,0.63,0.28),Geo.material(Color("3f4748"),0.7,0.4))
		"armor":
			for index in 3:
				Geo.box(stall,Vector3(0.62,0.5,0.5),Vector3(-0.66+float(index)*0.68,0.25+float(index % 2)*0.48,-0.15),wood)
			Geo.cylinder(stall,0.05,0.04,1.55,Vector3(0.72,0.78,0.24),wood,6)
			Geo.box(stall,Vector3(0.62,0.5,0.26),Vector3(0.72,1.34,0.24),Geo.material(Color("5b5f54"),0.25,0.7))
			Geo.box(stall,Vector3(0.82,0.08,0.26),Vector3(0.72,1.62,0.24),Geo.material(Color("454a42"),0.2,0.7))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0,2.15,0.55)
	lamp.light_color = Color("ffb46a")
	lamp.light_energy = 1.35
	lamp.omni_range = 5.5
	stall.add_child(lamp)
	_lanterns.append(lamp)
	_lantern_energy.append(lamp.light_energy)
	var sign := Label3D.new()
	sign.text = title
	sign.font_size = 44
	sign.pixel_size = 0.0042
	sign.position = Vector3(0,2.82,0.55)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.modulate = Color("e9bf76")
	sign.outline_size = 6
	sign.no_depth_test = false
	stall.add_child(sign)

func _build_character() -> void:
	archer = Archer.new()
	archer.position = Vector3(0,0.02,0)
	# The imported ranger faces -Z in gameplay space; turn the staging pose to the camera.
	archer.rotation.y = PI
	add_child(archer)
	archer.set_ground_sampler(func(_point: Vector3): return 0.0)
	archer.set_locomotion(Vector3.ZERO,true)
	_apply_preview_loadout()

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "HollowCamera"
	camera.fov = 55.0
	camera.near = 0.08
	camera.far = 120.0
	camera.current = true
	add_child(camera)
	_update_camera()

func _update_camera() -> void:
	var back := Vector3(sin(_yaw) * cos(_pitch),sin(_pitch),cos(_yaw) * cos(_pitch))
	camera.global_position = _focus + back * _distance
	camera.look_at(_focus + Vector3(0,0.10,0),Vector3.UP)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and hud != null and hud.is_form_open():
		hud.close_form()
