extends SceneTree

class Report extends Node:
	var command_id := 0
	var messages: Dictionary = {}
	@rpc("authority","call_remote","reliable")
	func command(value: int) -> void:
		command_id = value
	@rpc("any_peer","call_remote","reliable")
	func result(label: String, data: Dictionary) -> void:
		messages[label] = data

var arena
var report: Report
var failures := 0
var children: Array[int] = []
var released_charge := -1.0
var saw_damage := false
var saw_sword := false
var saw_roll := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func pause(seconds: float) -> void:
	await create_timer(seconds).timeout

func key(code: Key, shift_pressed: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift_pressed
	event.pressed = true
	Input.parse_input_event(event)
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift_pressed
	Input.parse_input_event(event)
	await pause(0.12)

func mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = root.get_screen_transform()*point
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	await mouse(point,true)
	await mouse(point,false)
	await pause(0.12)

func aim(point: Vector3) -> void:
	var delta: Vector3 = point-arena.actors[arena.local_slot].position
	var distance := Vector2(delta.x,delta.z).length()
	var yaw := atan2(-delta.x,-delta.z)+asin(clampf(0.70/maxf(distance,0.71),-0.99,0.99))
	var pitch := atan2(1.5-delta.y,sqrt(maxf(0.01,distance*distance-0.49)))
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(wrapf(arena._camera_yaw-yaw,-PI,PI),pitch-arena._camera_pitch)/0.004*root.get_screen_transform().get_scale()
	event.position = root.get_screen_transform()*(root.get_visible_rect().size*0.5)
	event.button_mask = Input.get_mouse_button_mask()
	Input.parse_input_event(event)
	await pause(0.08)

func wait_message(label: String) -> void:
	var elapsed := 0.0
	while not report.messages.has(label) and elapsed < 8:
		await pause(0.05)
		elapsed += 0.05
	check(report.messages.has(label),"Remote scenario reaches " + label)

func observe() -> void:
	if not is_instance_valid(arena) or arena.local_slot < 0:
		return
	for actor in arena.actors:
		saw_damage = saw_damage or actor.health < 99
		saw_sword = saw_sword or (actor.rig.weapon == "sword" and actor.rig.phase == "MELEE")
		saw_roll = saw_roll or actor.rig._roll_progress >= 0

func run() -> void:
	report = Report.new()
	report.name = "InputReport"
	root.add_child(report)
	arena = load("res://arena.tscn").instantiate()
	root.add_child(arena)
	process_frame.connect(observe)
	var args := OS.get_cmdline_user_args()
	if args.has("--input-client"):
		await client_run(int(args[args.find("--input-client")+1]))
	else:
		await host_run()
	print("NETWORK_INPUT_REGRESSION failures=",failures," damage=",saw_damage," sword=",saw_sword," roll=",saw_roll)
	arena.leave_game()
	await pause(0.15)
	quit(0 if failures == 0 else 1)

func host_run() -> void:
	var socket := PacketPeerUDP.new()
	check(socket.bind(0)==OK,"Network fixture gets an available UDP port")
	var port := socket.get_local_port()
	socket.close()
	arena.host_game(port,"Input host")
	for index in 3:
		var args := PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--script",get_script().resource_path,"--","--input-client",str(port)])
		children.append(OS.create_process(OS.get_executable_path(),args))
		await pause(0.15)
	var elapsed := 0.0
	while arena.get_human_count() < 4 and elapsed < 8:
		await pause(0.1)
		elapsed += 0.1
	check(arena.get_human_count()==4,"Four actual ENet game processes connect")
	for index in 4:
		arena._clear_slot_arrows(index)
		var actor = arena.actors[index]
		actor.revive()
		actor.position = [Vector3(0,0.05,-4),Vector3(0,0.05,4),Vector3(-14,0.05,14),Vector3(14,0.05,-14)][index]
		actor.rig.set_weapon("bow")
		actor.rig.set_bow(1)
		actor.rig.set_armor(0)
	arena.actors[1].fired.connect(func(_slot,_origin,_direction,_speed,charge): released_charge=charge)
	await pause(0.4)
	var initial_shots: int = arena.shots_fired
	report.command.rpc(1)
	await wait_message("holding")
	check(arena.actors[1].rig.phase in ["DRAWING","HOLDING"],"Remote mouse-down holds a draw instead of auto-firing")
	check(arena.shots_fired == initial_shots and arena.actors[0].health == 100,"Holding inflicts no damage on the server")
	check(int(report.messages.get("holding",{}).get("failures",1))==0,"Remote 1/2 keys and mouse-only size controls pass")
	report.command.rpc(2)
	await wait_message("released")
	await pause(0.55)
	check(arena.shots_fired == initial_shots+1,"Remote mouse release creates one arrow")
	check(released_charge>0 and released_charge<1,"Network release preserves fractional draw power")
	check(absf(arena.actors[0].health-(100.0-38.0*released_charge))<0.01,"Only actual projectile impact applies linear charge-scaled damage")
	await pause(2.1)
	arena.actors[0].position = Vector3(0,0.05,0)
	arena.actors[0].health = 100
	arena.actors[1].position = Vector3(0,0.05,1.4)
	await pause(0.3)
	report.command.rpc(3)
	await wait_message("chopped")
	check(is_equal_approx(arena.actors[0].health,50.0),"Revised remote greatsword animation still deals one authoritative hit")
	report.command.rpc(4)
	await wait_message("double_space")
	check(not saw_roll,"Remote repeated Space and malformed jump modifiers never roll")
	check(not arena.actors[1].is_on_floor(),"Remote Space alone still jumps")
	await pause(0.6)
	report.command.rpc(5)
	await wait_message("rolled")
	check(saw_roll and saw_sword,"One remote Shift+Space sends the roll state to the server")
	await pause(0.3)
	report.command.rpc(6)
	await wait_message("observer2")
	await wait_message("observer3")
	for label in ["observer2","observer3"]:
		var observation: Dictionary = report.messages.get(label,{})
		check(bool(observation.get("damage",false)) and bool(observation.get("sword",false)) and bool(observation.get("roll",false)),"Other clients receive damage and the revised animation states")
	await key(KEY_SPACE,true)
	check(arena.actors[0].roll.active,"Host local Shift+Space launches an immediate roll")
	arena.leave_game()
	await pause(0.8)
	for pid in children:
		if OS.is_process_running(pid):
			OS.kill(pid)

func client_run(port: int) -> void:
	await pause(0.1)
	arena.join_game("127.0.0.1",port,"Input peer")
	var elapsed := 0.0
	while (arena.local_slot < 0 or arena.last_snapshot_tick < 0) and elapsed < 8:
		await pause(0.05)
		elapsed += 0.05
	check(arena.local_slot>=1,"Client joins an assigned live seat")
	var completed := 0
	while arena.network_role == "client":
		if report.command_id>completed:
			completed = report.command_id
			if arena.local_slot==1:
				var rig = arena.actors[1].rig
				match completed:
					1:
						await key(KEY_I)
						await click(arena.hud.bow_buttons[2])
						await click(arena.hud.sword_buttons[0])
						await key(KEY_2)
						check(rig.weapon=="sword" and rig.bow_index==2 and rig.sword_index==0,"Remote key 2 equips sword without resizing either weapon")
						await key(KEY_3)
						check(rig.weapon=="sword" and rig.bow_index==2 and rig.sword_index==0,"Remote key 3 has no size binding")
						await key(KEY_1)
						check(rig.weapon=="bow","Remote key 1 equips bow")
						await click(arena.hud.bow_buttons[1])
						await key(KEY_I)
						await aim(Vector3(-3,1.2,-4))
						await mouse(root.get_visible_rect().size*0.5,true)
						await pause(0.40)
						report.result.rpc_id(1,"holding",{"failures":failures})
					2:
						await aim(Vector3(0,1.2,-4))
						await mouse(root.get_visible_rect().size*0.5,false)
						report.result.rpc_id(1,"released",{})
					3:
						await key(KEY_I)
						await click(arena.hud.sword_buttons[2])
						await key(KEY_2)
						await key(KEY_I)
						await aim(Vector3(0,1.2,0))
						await mouse(root.get_visible_rect().size*0.5,true)
						await mouse(root.get_visible_rect().size*0.5,false)
						await pause(3.1)
						report.result.rpc_id(1,"chopped",{})
					4:
						arena.send_action("jump",null)
						arena.send_action("jump",1)
						arena.send_action("jump","true")
						await key(KEY_SPACE)
						await key(KEY_SPACE)
						report.result.rpc_id(1,"double_space",{})
					5:
						await key(KEY_SPACE,true)
						await pause(0.3)
						report.result.rpc_id(1,"rolled",{})
			elif completed == 6:
				report.result.rpc_id(1,"observer%d"%arena.local_slot,{"damage":saw_damage,"sword":saw_sword,"roll":saw_roll})
		await pause(0.02)
