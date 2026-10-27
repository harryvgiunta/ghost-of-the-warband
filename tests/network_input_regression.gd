extends SceneTree

class Report extends Node:
	var command_id := 0
	var messages: Dictionary = {}
	var automatic_slot := -1
	var lookout_slot := -1
	@rpc("authority","call_local","reliable")
	func lookout_stage(slot: int) -> void:
		lookout_slot = slot
	@rpc("authority","call_local","reliable")
	func automatic_stage(slot: int) -> void:
		automatic_slot = slot
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
var saw_cover := false
var saw_peek := false
var manual_crouch_seen: Dictionary = {}
var standing_seen: Dictionary = {}
var peek_seen: Dictionary = {}
var lean_seen: Dictionary = {}
var tucked_draw_seen: Dictionary = {}
var automatic_aim_seen: Dictionary = {}
var automatic_arrow_seen: Dictionary = {}
var melee_cover_seen: Dictionary = {}
var melee_exit_seen: Dictionary = {}
var lookout_pose_seen: Dictionary = {}
var lookout_arrow_seen: Dictionary = {}
var lookout_return_seen: Dictionary = {}
var pending_cover_charge: Dictionary = {}
var remote_exposure_wait_seen := false

func tree_lookout_checks() -> void:
	var actor = arena.actors[arena.local_slot]
	arena._set_cursor_free(false)
	arena._camera_yaw = 0.0
	arena._camera_pitch = 0.0
	await key(KEY_1)
	await key(KEY_F)
	await pause(0.35)
	check(actor.cover.active and not actor.cover.low,"Remote controller attaches to the real cylindrical arena tree")
	var anchor: Vector3 = actor.position
	var center := root.get_visible_rect().size*0.5
	for side in [-1,1]:
		arena._camera_yaw = 0.0
		if arena._shoulder_camera.side != side:
			await key(KEY_X)
		var initial_shots: int = arena.shots_fired
		if side == -1:
			await mouse(center,true,MOUSE_BUTTON_RIGHT)
			await pause(0.4)
			await mouse(center,true)
		else:
			held_attack(true)
		await pause(0.6)
		check(actor.cover.peeking and actor.cover.lean.x*side>0.95 and actor.position.x*side>anchor.x*side+0.35,"Remote left/right tree lookout reaches a physical side exposure")
		var captured: Vector3 = arena._peek_right
		if side == -1:
			await mouse(center,false,MOUSE_BUTTON_RIGHT)
			await pause(0.4)
			check(not actor.cover.peeking and actor.rig.phase in ["DRAWING","HOLDING"],"Remote manual left retuck preserves its held draw without client-inferred auto ownership")
			await mouse(center,false)
		else:
			var motion := InputEventMouseMotion.new()
			motion.relative = Vector2(-500,0)*root.get_screen_transform().get_scale()
			Input.parse_input_event(motion)
			await pause(0.15)
			check(actor.cover.lean.x>0.95 and actor.rig.phase in ["DRAWING","HOLDING"],"Remote free look crosses the side sign without switching shoulder or canceling draw")
			held_attack(false)
		# A manually retucked release includes re-exposure, follow-through and
		# physical return before the next replicated draw can begin.
		var elapsed := 0.0
		while elapsed < 2.5:
			if arena.shots_fired > initial_shots and actor.cover.active and not actor.cover.peeking \
					and actor.cover.lean.is_zero_approx() and actor.position.distance_to(anchor)<0.04 and actor.rig.phase=="READY":
				break
			await pause(0.05)
			elapsed += 0.05
		check(arena._peek_right.is_equal_approx(captured),"Ordered release context retains the captured remote view-right")
		check(arena.shots_fired==initial_shots+1,"Remote tree lookout releases one authoritative projectile per request")
		check(actor.cover.active and not actor.cover.peeking and actor.position.distance_to(anchor)<0.04,"Remote tree shot retucks to its original protected anchor")
		check(actor.rig.phase=="READY","Remote tree shot completes recovery before the next held attack")

func check_tree_observations() -> void:
	for side in [-1,1]:
		check(lookout_pose_seen.has(side),"Every peer sees the remote tree lookout's signed physical lean and posed bow")
		check(lookout_arrow_seen.has(side),"Every peer sees the remote left/right projectile fly clear of its source tree")
		check(lookout_return_seen.has(side),"Every peer sees each remote tree lookout return to cover")

func melee_cover_exit_checks() -> void:
	var actor = arena.actors[arena.local_slot]
	arena._camera_yaw = 0.0
	arena.send_action("sword",0)
	await key(KEY_2)
	await key(KEY_F)
	await pause(0.3)
	check(actor.cover.active and not actor.cover.peeking,"Network melee fixture is attached and tucked before attack")
	var origin: Vector3 = actor.position
	await mouse(root.get_visible_rect().size*0.5,true)
	await mouse(root.get_visible_rect().size*0.5,false)
	await pause(0.15)
	check(not actor.cover.active and actor.rig.phase.begins_with("MELEE") and Vector2(actor.position.x-origin.x,actor.position.z-origin.z).length()<0.03,"Network melee starts without a peek step and breaks attachment on the authority and replica")
	await pause(1.2)
	check(not actor.cover.active and actor.rig.phase=="READY","Network sword recovery stays detached")

func automatic_cover_checks() -> void:
	var actor = arena.actors[arena.local_slot]
	var initial_shots: int = arena.shots_fired
	await aim(actor.position+Vector3(0,3,-14))
	await mouse(root.get_visible_rect().size*0.5,true)
	await pause(0.6)
	var desired: Vector3 = (actor.rig._aim_point-actor.rig.get_arrow_origin()).normalized()
	var horizontal := Vector3(desired.x,0,desired.z).normalized()
	check(actor.cover.peeking and actor.cover.lean.y>0.95 and actor.cover._capsule.height>1.6,"Direct network LMB automatically exposes without RMB")
	check((-actor.rig.global_basis.z).dot(horizontal)>0.95 and actor.rig.active_bow.get_arrow_direction().dot(desired)>0.98,"Direct network attack visibly faces and points the bow at aim")
	check(arena.shots_fired==initial_shots,"Automatic exposure does not release a held network draw")
	await mouse(root.get_visible_rect().size*0.5,false)
	await pause(0.85)
	check(arena.shots_fired==initial_shots+1 and actor.cover.active and not actor.cover.peeking and actor.cover.lean.is_zero_approx(),"Direct network shot fires once and retucks automatically")
	await pause(0.6)

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

func mouse(point: Vector2, pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
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

func held_key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func held_attack(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = root.get_screen_transform()*(root.get_visible_rect().size*0.5)
	Input.parse_input_event(event)

func crouch_checks() -> void:
	var actor = arena.actors[arena.local_slot]
	var armor: int = actor.rig.armor_bits()
	var standing_height: float = actor.cover._capsule.height
	for invalid in [null,1,"true",{"pressed":true}]:
		arena.send_action("crouch",invalid)
	await pause(0.25)
	check(not actor.cover.crouch_requested and not actor.cover.crouched and absf(actor.cover._capsule.height-standing_height)<0.02,"Malformed crouch values cannot change the authoritative posture")
	await key(KEY_C)
	await pause(0.4)
	check(not actor.cover.active and actor.cover.crouched and actor.cover._capsule.height<standing_height-0.4,"C crouches outside cover with a smaller real collider")
	check(actor.rig.armor_bits()==armor,"C crouch preserves armor across the network")
	for invalid in [null,0,"false",{}]:
		arena.send_action("crouch",invalid)
	await pause(0.25)
	check(actor.cover.crouch_requested and actor.cover.crouched and actor.cover._capsule.height<1.2,"Malformed false-like values cannot stand a crouched actor")
	arena.send_action("crouch",true)
	arena.send_action("crouch",true)
	await pause(0.25)
	check(actor.cover.crouched and actor.cover._capsule.height<1.2,"Repeated desired true requests do not toggle crouch")
	await key(KEY_C)
	await pause(0.4)
	check(not actor.cover.crouched and absf(actor.cover._capsule.height-standing_height)<0.02,"Second C restores the authoritative standing collider")
	check(actor.rig.armor_bits()==armor,"C stand preserves armor across the network")

func slide_distance(code: Key, fast: bool) -> float:
	var actor = arena.actors[arena.local_slot]
	held_key(KEY_SHIFT,fast)
	held_key(code,true)
	await pause(0.1)
	var start: Vector3 = actor.position
	await pause(0.2)
	var distance := absf(actor.position.x-start.x)
	held_key(code,false)
	held_key(KEY_SHIFT,false)
	await pause(0.15)
	check(actor.cover.active and absf(actor.position.x)<1.6 and actor.position.z> -12.0,"Network slide stays attached within the real wall instead of penetrating it")
	return distance

func enter_cover_checks() -> void:
	arena._set_cursor_free(false)
	arena._camera_yaw = 0.0
	await crouch_checks()
	arena.send_action("cover",true)
	arena.send_action("cover",{"position":Vector3.ZERO})
	await pause(0.15)
	var actor = arena.actors[arena.local_slot]
	check(not actor.cover.active,"Malformed cover requests cannot attach or teleport")
	await key(KEY_F)
	await pause(0.35)
	check(actor.cover.active and actor.cover.low and actor.cover._capsule.height<1.2,"F attaches to low stone cover with a physically crouched actor")
	var ordinary: float = await slide_distance(KEY_D,false)
	var fast: float = await slide_distance(KEY_A,true)
	check(ordinary>0.2 and fast>ordinary*1.4,"Shift makes replicated attached movement faster than ordinary slide")
	arena.send_action("peek",{"pressed":true,"right":Vector3(NAN,0,0),"side":1})
	arena.send_action("peek",{"pressed":true,"right":Vector3.RIGHT,"side":0})
	await pause(0.15)
	check(not actor.cover.peeking,"Malformed peek intent cannot expose the actor")

func draw_and_peek_checks() -> void:
	var actor = arena.actors[arena.local_slot]
	var initial_shots: int = arena.shots_fired
	await mouse(root.get_visible_rect().size*0.5,true,MOUSE_BUTTON_RIGHT)
	await pause(0.45)
	await mouse(root.get_visible_rect().size*0.5,true)
	await pause(0.3)
	await key(KEY_X)
	await pause(0.4)
	check(actor.cover.active and actor.cover.peeking and actor.cover._capsule.height>1.6 and arena._shoulder_camera.side == -1,"Held RMB peeks physically while X switches the local shoulder")
	var height: float = actor.cover._capsule.height
	await pause(0.3)
	check(actor.cover.active and actor.cover.peeking and absf(actor.cover._capsule.height-height)<0.02,"Continuously held RMB keeps replicated peek posture stable")
	check(arena.shots_fired==initial_shots,"Drawing and holding peek do not auto-fire")

func return_to_cover_checks() -> void:
	var actor = arena.actors[arena.local_slot]
	var draw_before: float = actor.rig.draw_amount
	await mouse(root.get_visible_rect().size*0.5,false,MOUSE_BUTTON_RIGHT)
	if arena.network_role == "client":
		for stamp in [null,true,0.5,"0",-1,2147483647]:
			arena._action_input.rpc_id(1,"release",arena._crosshair_aim(),stamp,null)
			arena._move_input.rpc_id(1,Vector2.ONE,false,arena._crosshair_aim(),stamp,null)
	await pause(0.4)
	check(actor.cover.active and not actor.cover.peeking and actor.cover._capsule.height<1.2,"RMB release returns to low cover without detaching")
	check(actor.rig.phase in ["DRAWING","HOLDING"] and actor.rig.draw_amount>=draw_before,"RMB release preserves the held bow draw on the authority and replica")

func release_cover_shot_checks() -> void:
	var initial_shots: int = arena.shots_fired
	if arena.network_role == "client":
		# Reliable release can trail a newer unreliable aim: preserve the newer
		# point/acknowledgement, but do not discard this valid release intent.
		var old_tick := maxi(0,int(arena._snapshot_ticks[arena.local_slot])-30)
		arena._action_input.rpc_id(1,"release",Vector3(20,4,20),old_tick)
	await mouse(root.get_visible_rect().size*0.5,false)
	await pause(0.6)
	check(arena.shots_fired==initial_shots+1,"LMB release from manually tucked draw re-exposes and launches exactly one network projectile")
	await mouse(root.get_visible_rect().size*0.5,false)
	await pause(0.15)
	check(arena.shots_fired==initial_shots+1,"Repeated LMB release cannot duplicate the projectile")
	if arena.network_role == "client":
		await stale_cover_release_checks()

func stale_cover_release_checks() -> void:
	var actor = arena.actors[arena.local_slot]
	var elapsed := 0.0
	while actor.rig.phase != "READY" and elapsed < 2.0:
		await pause(0.05)
		elapsed += 0.05
	check(actor.rig.phase=="READY" and actor.cover.active and not actor.cover.peeking,"Lost-input fixture starts with a recovered tucked bow")
	var initial_shots: int = arena.shots_fired
	# Keep RPC/snapshot reception live but stop movement/aim transmission. The
	# normal reliable press/release now waits for an exposure acknowledgement
	# that this paused input stream cannot supply.
	arena.set_physics_process(false)
	await mouse(root.get_visible_rect().size*0.5,true)
	await mouse(root.get_visible_rect().size*0.5,false)
	var saw_frozen := false
	elapsed = 0.0
	while elapsed < 1.2:
		saw_frozen = saw_frozen or actor.rig.charge_frozen
		if saw_frozen and actor.rig.phase=="READY" and not actor.rig.charge_frozen:
			break
		await pause(0.05)
		elapsed += 0.05
	check(saw_frozen,"Paused remote aim stream reaches a real frozen pending cover release")
	check(actor.rig.phase=="READY" and not actor.rig.charge_frozen and arena.shots_fired==initial_shots,"Existing stale-input boundary cancels the pending shot without firing")
	arena.set_physics_process(true)
	await pause(0.2)
	check(arena.shots_fired==initial_shots and actor.rig.phase=="READY","Resuming remote aim transmission cannot resurrect the canceled release")

func jump_out_checks() -> void:
	var actor = arena.actors[arena.local_slot]
	var ground_height: float = actor.position.y
	await key(KEY_SPACE)
	check(not actor.cover.active and not actor.roll.active and actor.position.y>ground_height+0.15,"Space alone jumps out of low cover without rolling")
	check(not actor.cover.crouch_requested and actor.cover._capsule.height>1.6,"Jumping out restores standing collision immediately")

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
		if actor.authoritative and actor.combat._release_pending:
			if not pending_cover_charge.has(actor.slot):
				pending_cover_charge[actor.slot] = actor.rig.draw_amount
			check(actor.rig.charge_frozen and absf(actor.rig.draw_amount-float(pending_cover_charge[actor.slot]))<0.0001,"Pending remote exposure acknowledgement cannot increase frozen charge")
			if actor.slot==1 and actor.cover.peeking and not actor.combat.cover_aim_ready:
				remote_exposure_wait_seen = true
		else:
			pending_cover_charge.erase(actor.slot)
		saw_damage = saw_damage or actor.health < 99
		saw_sword = saw_sword or (actor.rig.weapon == "sword" and actor.rig.phase.begins_with("MELEE"))
		if actor.cover.active and actor.rig.weapon=="sword":
			melee_cover_seen[actor.slot] = true
		if melee_cover_seen.has(actor.slot) and not actor.cover.active and actor.rig.phase.begins_with("MELEE"):
			var aim_direction: Vector3 = actor.rig._aim_point-actor.position
			aim_direction.y = 0.0
			if (-actor.rig.global_basis.z).dot(aim_direction.normalized())>0.95:
				melee_exit_seen[actor.slot] = true
		saw_roll = saw_roll or actor.rig._roll_progress >= 0
		saw_cover = saw_cover or (actor.cover.active and actor.cover.low and not actor.cover.peeking)
		saw_peek = saw_peek or actor.cover.peeking
		if not actor.cover.active and actor.cover.crouched and actor.cover._capsule.height<1.2:
			manual_crouch_seen[actor.slot] = true
		if manual_crouch_seen.has(actor.slot) and not actor.cover.active and not actor.cover.crouched and actor.cover._capsule.height>1.6:
			standing_seen[actor.slot] = true
		if actor.cover.peeking and actor.cover._capsule.height>1.6:
			peek_seen[actor.slot] = true
		if peek_seen.has(actor.slot) and actor.cover.active and not actor.cover.peeking and actor.cover._capsule.height<1.2 and actor.rig.phase in ["DRAWING","HOLDING"]:
			tucked_draw_seen[actor.slot] = true
		if actor.cover.peeking and actor.cover.low:
			var torso: Vector3 = (actor.rig._bone_world(actor.rig._arms[0][0]).origin+actor.rig._bone_world(actor.rig._arms[1][0]).origin)*0.5-actor.rig._bone_world(actor.rig._bones.pelvis).origin
			if torso.dot(-actor.cover.normal)>0.07:
				lean_seen[actor.slot] = true
		if actor.slot==report.automatic_slot and actor.cover.peeking and actor.cover.low and actor.rig.phase in ["DRAWING","HOLDING","RELEASE"]:
			var desired: Vector3 = (actor.rig._aim_point-actor.rig.get_arrow_origin()).normalized()
			var horizontal := Vector3(desired.x,0,desired.z).normalized()
			var torso: Vector3 = (actor.rig._bone_world(actor.rig._arms[0][0]).origin+actor.rig._bone_world(actor.rig._arms[1][0]).origin)*0.5-actor.rig._bone_world(actor.rig._bones.pelvis).origin
			if (-actor.rig.global_basis.z).dot(horizontal)>0.95 and actor.rig.active_bow.get_arrow_direction().dot(desired)>0.98 and torso.dot(-actor.cover.normal)>0.07:
				automatic_aim_seen[actor.slot] = true
		if actor.slot==report.lookout_slot and actor.cover.active:
			if actor.cover.peeking and absf(actor.cover.lean.x)>0.95 and actor.rig.phase in ["DRAWING","HOLDING","RELEASE"]:
				var side := 1 if actor.cover.lean.x>0 else -1
				var desired: Vector3 = (actor.rig._aim_point-actor.rig.get_arrow_origin()).normalized()
				if actor.rig._cover_lean.dot(actor.cover.lean)>0.95 and actor.rig.active_bow.get_arrow_direction().dot(desired)>0.98:
					lookout_pose_seen[side] = true
			elif actor.cover.lean.is_zero_approx() and actor.rig.phase in ["RELEASE","RECOVER","READY"]:
				for side in lookout_arrow_seen:
					lookout_return_seen[side] = true
	for arrow in arena.projectiles:
		if is_instance_valid(arrow):
			for actor in arena.actors:
				if actor.slot==report.automatic_slot and arrow.source_id==actor.slot and actor.cover.active and actor.rig.phase=="RELEASE" and arrow.position.distance_to(actor.position)<8.0:
					var desired: Vector3 = (actor.rig._aim_point-arrow.position).normalized()
					if arrow.velocity.normalized().dot(desired)>0.97:
						automatic_arrow_seen[actor.slot] = true
				if actor.slot==report.lookout_slot and arrow.source_id==actor.slot and actor.cover.active and absf(actor.cover.lean.x)>0.1 and arrow.flying and arrow.position.distance_to(actor.position)>2.0 and arrow.position.distance_to(actor.position)<8.0:
					var query := PhysicsRayQueryParameters3D.create(arrow.position,arrow.position+arrow.velocity.normalized()*2.0,1)
					query.hit_from_inside = true
					if arena.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
						lookout_arrow_seen[1 if actor.cover.lean.x>0 else -1] = true

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
	arena.actors[1].fired.connect(func(_slot,_origin,_direction,_speed,charge):
		released_charge = charge
		var actor = arena.actors[1]
		if actor.cover.active:
			check(actor._exposure_tick>=0 and actor.aim_snapshot_tick>=actor._exposure_tick,"Remote cover release uses an aim sampled after the authoritative exposure snapshot")
			if pending_cover_charge.has(1):
				check(absf(charge-float(pending_cover_charge[1]))<0.0001,"Remote shot retains the charge frozen before aim acknowledgement"))
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
	# A standard greatsword cleave applies base damage once, not an incidental
	# headshot or one copy per sampled contact.
	arena.actors[0].health = 200.0
	arena.actors[1].position = Vector3(0,0.05,1.4)
	await pause(0.3)
	report.command.rpc(3)
	await wait_message("chopped")
	var chop_damage: float = 200.0 - float(arena.actors[0].health)
	check(is_equal_approx(chop_damage,50.0),"Remote greatsword cleave deals one authoritative 50-damage hit (got %.2f; source %s; target %s; aim %s)" % [chop_damage,arena.actors[1].position,arena.actors[0].position,arena.actors[1].combat.aim_point])
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
	arena._set_cursor_free(false)
	await key(KEY_SPACE,true)
	check(arena.actors[0].roll.active,"Host local Shift+Space launches an immediate roll")
	await pause(1.0)
	arena.actors[1].revive()
	arena.actors[1].rig.set_weapon("bow")
	arena.actors[1].position = Vector3(0,0.05,-11.6)
	await pause(0.4)
	report.command.rpc(7)
	await wait_message("covered")
	check(arena.actors[1].cover.active and arena.actors[1].cover.low,"Remote F attaches to real arena stone cover on the host")
	check(absf(arena.actors[1].position.x)<1.6 and arena.actors[1].position.z> -12.0,"Remote cover motion stays along the wall without penetrating it")
	var cover_shots: int = arena.shots_fired
	report.automatic_stage.rpc(1)
	report.command.rpc(8)
	await wait_message("automatic_fired")
	check(not arena.actors[1].cover.peeking and arena.shots_fired==cover_shots+1,"Remote direct attack fires once and returns behind cover")
	check(automatic_aim_seen.has(1) and automatic_arrow_seen.has(1),"Host observes the remote automatic attack's real bow and projectile direction")
	report.automatic_stage.rpc(-1)
	report.command.rpc(9)
	await wait_message("retucked")
	check(arena.actors[1].cover.active and not arena.actors[1].cover.peeking and arena.actors[1].rig.phase in ["DRAWING","HOLDING"],"Remote RMB release preserves cover and the authoritative bow draw")
	var aim_before: Vector3 = arena.actors[1].combat.aim_point
	var stamp_before: int = arena.actors[1].aim_snapshot_tick
	check(not arena._set_aim(1,Vector3(20,4,20),int(arena._snapshot_ticks[1])+1),"Authority rejects aim stamps newer than snapshots actually sent")
	check(arena._set_aim(1,Vector3(20,4,20),maxi(0,stamp_before-1)),"A valid stale aim stamp still permits its ordered release intent")
	check(arena.actors[1].combat.aim_point.is_equal_approx(aim_before) and arena.actors[1].aim_snapshot_tick==stamp_before,"Stale aim cannot overwrite the point while retaining a newer acknowledgement")
	report.command.rpc(10)
	await wait_message("cover_fired")
	check(arena.shots_fired==cover_shots+2,"Remote automatic and manually retucked releases each produce one authoritative projectile")
	check(remote_exposure_wait_seen,"Remote cover release waits for an aim acknowledging physical exposure instead of firing at stale near-cover aim")
	report.command.rpc(11)
	await wait_message("left_cover")
	check(not arena.actors[1].cover.active and not arena.actors[1].roll.active and not arena.actors[1].is_on_floor(),"Remote unmodified Space leaves low cover and jumps")
	await pause(0.8)
	arena.actors[1].position = Vector3(0,0.05,4)
	arena.actors[0].revive()
	arena.actors[0].rig.set_weapon("bow")
	arena.actors[0].position = Vector3(0,0.05,-11.6)
	await pause(0.4)
	await enter_cover_checks()
	report.automatic_stage.rpc(0)
	await automatic_cover_checks()
	check(automatic_aim_seen.has(0) and automatic_arrow_seen.has(0),"Host observes its own automatic attack's real bow and projectile direction")
	report.automatic_stage.rpc(-1)
	await draw_and_peek_checks()
	await return_to_cover_checks()
	await release_cover_shot_checks()
	await jump_out_checks()
	report.command.rpc(12)
	await wait_message("cover_observer1")
	await wait_message("cover_observer2")
	await wait_message("cover_observer3")
	for label in ["covered","automatic_fired","retucked","cover_fired","left_cover","cover_observer1","cover_observer2","cover_observer3"]:
		check(int(report.messages.get(label,{}).get("failures",1))==0,"Remote cover behavior and presentation pass for "+label)
	await pause(0.8)
	arena.actors[0].position = Vector3(0,0.05,-11.6)
	await pause(0.4)
	await melee_cover_exit_checks()
	check(melee_exit_seen.has(0),"Host observes its cover constraint removed before its melee pose")
	arena.actors[0].position = Vector3(4,0.05,4)
	arena.actors[1].revive()
	arena.actors[1].position = Vector3(0,0.05,-11.6)
	await pause(0.4)
	report.command.rpc(13)
	await wait_message("melee_cover_exit")
	check(melee_exit_seen.has(1) and not arena.actors[1].cover.active,"Host applies and retains the remote melee cover exit")
	report.command.rpc(14)
	for label in ["melee_observer1","melee_observer2","melee_observer3"]:
		await wait_message(label)
		check(int(report.messages.get(label,{}).get("failures",1))==0,"Remote melee cover-exit observation passes for "+label)
	check(int(report.messages.get("melee_cover_exit",{}).get("failures",1))==0,"Remote direct melee input breaks cover and stays detached")
	arena.actors[1].revive()
	arena.actors[1].rig.set_weapon("bow")
	arena.actors[1].position = Vector3(-9,0.05,-6.05)
	await pause(0.4)
	report.lookout_stage.rpc(1)
	report.command.rpc(15)
	await wait_message("tree_lookouts")
	check(int(report.messages.get("tree_lookouts",{}).get("failures",1))==0,"Remote tree inputs, captured context and left/right shots pass")
	check_tree_observations()
	check(arena.actors[1].peek_view_right.is_equal_approx(Vector3.RIGHT),"Host receives the original right vector at release despite remote camera rotation")
	report.command.rpc(16)
	for label in ["tree_observer1","tree_observer2","tree_observer3"]:
		await wait_message(label)
		check(int(report.messages.get(label,{}).get("failures",1))==0,"Replicated tree lookout pose and projectiles pass for "+label)
	report.lookout_stage.rpc(-1)
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
						arena.send_action("bow",2)
						arena.send_action("sword",0)
						await pause(0.15)
						await key(KEY_2)
						check(rig.weapon=="sword" and rig.bow_index==2 and rig.sword_index==0,"Remote key 2 equips sword without resizing either weapon")
						await key(KEY_3)
						check(rig.weapon=="dagger" and rig.bow_index==2 and rig.sword_index==0,"Remote key 3 equips the dagger without resizing either weapon")
						await key(KEY_1)
						check(rig.weapon=="bow","Remote key 1 equips bow")
						arena.send_action("bow",1)
						await pause(0.15)
						await aim(Vector3(-3,1.2,-4))
						await mouse(root.get_visible_rect().size*0.5,true)
						await pause(0.40)
						report.result.rpc_id(1,"holding",{"failures":failures})
					2:
						await aim(Vector3(0,1.2,-4))
						await mouse(root.get_visible_rect().size*0.5,false)
						report.result.rpc_id(1,"released",{})
					3:
						arena.send_action("sword",2)
						await pause(0.15)
						await key(KEY_2)
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
					7:
						await enter_cover_checks()
						report.result.rpc_id(1,"covered",{"failures":failures})
					8:
						await automatic_cover_checks()
						report.result.rpc_id(1,"automatic_fired",{"failures":failures})
					9:
						await draw_and_peek_checks()
						await return_to_cover_checks()
						report.result.rpc_id(1,"retucked",{"failures":failures})
					10:
						await release_cover_shot_checks()
						report.result.rpc_id(1,"cover_fired",{"failures":failures})
					11:
						await jump_out_checks()
						report.result.rpc_id(1,"left_cover",{"failures":failures})
					12:
						for slot in [0,1]:
							check(automatic_aim_seen.has(slot) and automatic_arrow_seen.has(slot),"Attacking client observes its own and host automatic bow/projectile directions")
						report.result.rpc_id(1,"cover_observer1",{"failures":failures})
					13:
						await melee_cover_exit_checks()
						report.result.rpc_id(1,"melee_cover_exit",{"failures":failures})
					14:
						for slot in [0,1]:
							check(melee_exit_seen.has(slot),"Attacking client observes both melee cover exits with attack-facing poses")
						report.result.rpc_id(1,"melee_observer1",{"failures":failures})
					15:
						await tree_lookout_checks()
						report.result.rpc_id(1,"tree_lookouts",{"failures":failures})
					16:
						check_tree_observations()
						report.result.rpc_id(1,"tree_observer1",{"failures":failures})
			elif completed == 6:
				report.result.rpc_id(1,"observer%d"%arena.local_slot,{"damage":saw_damage,"sword":saw_sword,"roll":saw_roll})
			elif completed == 12:
				check(saw_cover and saw_peek,"Observer receives crouched and exposed cover transitions")
				for slot in [0,1]:
					check(manual_crouch_seen.has(slot) and standing_seen.has(slot),"Observer receives host and client C crouch/stand collider transitions")
					check(peek_seen.has(slot) and tucked_draw_seen.has(slot),"Observer sees host and client peek return preserve a tucked draw")
					check(lean_seen.has(slot),"Observer sees the host and client torso lean over cover, not only a raised collider")
					check(automatic_aim_seen.has(slot) and automatic_arrow_seen.has(slot),"Observer sees host and client exposed bow facing and real projectile direction")
				report.result.rpc_id(1,"cover_observer%d"%arena.local_slot,{"failures":failures})
			elif completed == 14:
				for slot in [0,1]:
					check(melee_exit_seen.has(slot),"Observer sees the host and remote player leave cover before their melee swings")
				report.result.rpc_id(1,"melee_observer%d"%arena.local_slot,{"failures":failures})
			elif completed == 16:
				check_tree_observations()
				report.result.rpc_id(1,"tree_observer%d"%arena.local_slot,{"failures":failures})
		await pause(0.02)
