extends SceneTree
## Phase 1 regression for the soul: one player, many bodies.
##
## Every check runs against real `ArenaActor` bodies added to this SceneTree, the
## real `Warband` router and the real camera rig - never a pure function stand-in.
## The list the ticket asks for, in order: eight gear-distinct bodies, peer 2
## refused on peer 1's body, both peers keeping a body through a cycle, downed
## bodies skipped and never re-enterable, the camera riding and swooping, the
## soul ejected by a router state change and by a real `take_damage`, the peer
## released when the squad is gone, and `server_apply` unable to steal a body.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Controller = preload("res://scripts/warband/possession_controller.gd")
const State = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")

const TEST_SAVE := "user://possession_regression_state.json"

## Eight legally equipped mercenaries whose main hands are all different: the
## only thing that may differ between bodies is what they carry.
const KITS: Array[Dictionary] = [
	{"main": "bow_short", "head": "armor_leather_head", "chest": "armor_leather_chest",
		"legs": "armor_leather_legs", "neck": "neck_ember", "ring1": "ring_copper"},
	{"main": "bow_recurve", "head": "armor_mail_head", "chest": "armor_mail_chest",
		"ring1": "ring_silver", "ring2": "ring_dash"},
	{"main": "bow_long", "head": "armor_plate_head", "chest": "armor_plate_chest",
		"legs": "armor_plate_legs", "feet": "armor_plate_feet"},
	{"main": "sword_arming", "off": "shield_kite", "chest": "armor_mail_chest",
		"hands": "armor_mail_hands", "ring1": "ring_melee"},
	{"main": "sword_great", "head": "armor_plate_head", "chest": "armor_plate_chest",
		"ring1": "ring_ironhide"},
	{"main": "dagger_iron", "off": "sword_short", "chest": "armor_cloth_chest",
		"legs": "armor_cloth_legs", "ring1": "ring_swift"},
	{"main": "staff_fire", "off": "focus_tome", "head": "armor_cloth_head",
		"neck": "neck_bone"},
	{"main": "sword_short", "off": "dagger_iron", "feet": "armor_makeshift_feet",
		"ring1": "ring_ranged"},
]

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("POSSESSION_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")
	call_deferred("_watchdog")

## A regression that dies mid-run must not hold the harness open forever.
func _watchdog() -> void:
	await create_timer(120.0).timeout
	push_error("possession regression timed out")
	print("POSSESSION_REGRESSION checks=", checks, " failures=", failures + 1)
	quit(1)

func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

func key_event(code: Key, pressed: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	return event

func mouse_event(button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = Vector2(720, 450)
	return event

func run() -> void:
	_remove_test_save()
	var state = root.get_node("PlayerState")
	var warband = root.get_node("Warband")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = TEST_SAVE
	warband.reset_state()

	var merc_ids: Array[int] = []
	for index in KITS.size():
		var merc_id: int = warband.add_mercenary("Soul %d" % (index + 1), KITS[index])
		warband.set_deployed(merc_id, true)
		merc_ids.append(merc_id)
	check(merc_ids.size() == 8, "eight mercenaries join the warband")
	check(warband.deployed_merc_ids().size() == 8, "all eight are marked for the battle line")

	# --- the arena, built in the real tree --------------------------------
	var arena := Node3D.new()
	arena.name = "PossessionFixture"
	root.add_child(arena)
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	ground.add_child(floor_shape)
	arena.add_child(ground)
	var bodies_root := Node3D.new()
	bodies_root.name = "Bodies"
	arena.add_child(bodies_root)
	var camera := Camera3D.new()
	camera.name = "ModeCamera"
	camera.current = true
	arena.add_child(camera)
	var controller = Controller.new()
	controller.name = "Soul"
	arena.add_child(controller)
	controller.setup(warband, camera, bodies_root)
	# The mode owns the pointer; the controller only reads it.
	controller.input_enabled = true
	# A HUD retargets on this signal, so every transfer and release must reach it.
	var events: Array = []
	controller.possession_changed.connect(func(peer_id: int, merc_id: int):
		events.append([peer_id, merc_id]))

	var spawn_points: Array[Vector3] = []
	for index in 8:
		spawn_points.append(Vector3(float(index) * 3.0 - 10.5, 0.0, 0.0))
	var bodies: Array = controller.spawn_mercenaries(spawn_points, true)
	await physics_frame
	check(controller.is_inside_tree() and bodies_root.is_inside_tree(),
		"the controller and its bodies live in the real tree")
	check(bodies.size() == 8, "eight real ArenaActors are fielded, got %d" % bodies.size())
	check(controller.bodies().size() == 8, "the controller keeps all eight bodies")
	check(camera.get_parent() == controller.camera_rig,
		"the mode's camera is adopted by the possession rig, not duplicated")

	check_bodies(warband, controller, merc_ids)
	check_opposition(warband, controller, merc_ids, events)
	check_cycle(warband, controller, merc_ids)
	check_camera(warband, controller, merc_ids)
	await check_router_eject(warband, controller, merc_ids)
	await check_health_eject(warband, controller, merc_ids)
	check_squad_release(warband, controller, merc_ids, events)
	check_server_apply(warband, controller, merc_ids)
	await check_live_input(warband, controller, merc_ids)
	await check_wire_movement(warband, controller, merc_ids)

	_remove_test_save()
	print("POSSESSION_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

# --- eight bodies, eight kits ----------------------------------------------

func check_bodies(warband, controller, merc_ids: Array[int]) -> void:
	var mains: Dictionary = {}
	for index in merc_ids.size():
		var merc_id := merc_ids[index]
		var actor = controller.body_of(merc_id)
		check(actor != null, "mercenary %d has a body" % merc_id)
		if actor == null:
			continue
		check(actor.alive and actor.authoritative, "body %d is a live authoritative fighter" % merc_id)
		check(actor.is_inside_tree(), "body %d is in the scene tree" % merc_id)
		check(warband.souls.has_body(merc_id), "body %d is registered with the soul router" % merc_id)
		check(warband.souls.body_node(merc_id) == actor, "the router points at the spawned body")
		check(controller.merc_of(actor) == merc_id, "the body maps back to its mercenary")

		var kit: Dictionary = KITS[index]
		var main_id := str(kit.get("main", ""))
		mains[main_id] = true
		var loadout: Dictionary = controller.seat_loadout(merc_id)
		check(str(loadout.get("main", "")) == main_id,
			"body %d wears its own main hand, got '%s'" % [merc_id, str(loadout.get("main", ""))])
		check(str(loadout.get("off", "")) == str(kit.get("off", "")),
			"body %d wears its own off hand" % merc_id)

		# The rig itself must carry that hand: index, mode and armour bits.
		var item: Dictionary = State.ITEMS[main_id]
		var category := str(item.get("category", ""))
		var index_of := int(item.get("index", 0))
		if category == "bow":
			check(actor.rig.weapon == "bow" and actor.rig.bow_index == index_of,
				"body %d holds its bow index %d" % [merc_id, index_of])
		elif category == "staff":
			check(actor.rig.weapon == "sword" and actor.rig.staff_active,
				"body %d holds its staff" % merc_id)
		elif str(item.get("kind", "")) == "dagger":
			check(actor.rig.weapon == "dagger", "body %d holds its dagger" % merc_id)
		else:
			# A one-hander over a legal off-hand weapon is carried in dual.
			var dual := index_of <= 1 and str(kit.get("off", "")) in ["dagger_iron", "sword_short"]
			var expected_mode := "dual" if dual else "sword"
			check(actor.rig.weapon == expected_mode and actor.rig.sword_index == index_of,
				"body %d holds its sword index %d in %s mode" % [merc_id, index_of, expected_mode])

		var pieces := {}
		for slot in ArmorData.SLOTS:
			var worn := str(kit.get(slot, ""))
			pieces[slot] = int(State.ITEMS.get(worn, {}).get("set", ArmorData.NONE)) \
				if not worn.is_empty() else ArmorData.NONE
		var packed := ArmorData.pack(pieces)
		check(int(loadout.get("armor", -1)) == packed,
			"body %d's seat loadout carries its packed armour" % merc_id)
		check(actor.rig.armor_bits() == packed,
			"body %d wears exactly the armour its record names" % merc_id)
		check(str(actor.rig.trinkets.get("neck", "")) == str(kit.get("neck", "")),
			"body %d wears its own neck piece" % merc_id)
	check(mains.size() == 8, "all eight bodies carry a different main hand")

	# The arena marks its two squads through this call; an empty body obeys it.
	controller.set_bot(merc_ids[4], false)
	check(not controller.body_of(merc_ids[4]).is_bot, "a body can be reserved for a human seat")
	controller.set_bot(merc_ids[4], true)
	check(controller.body_of(merc_ids[4]).is_bot, "and handed back to the AI")

# --- peer 2 cannot take peer 1's body --------------------------------------

func check_opposition(warband, controller, merc_ids: Array[int], events: Array) -> void:
	var first: Dictionary = controller.activate(1, merc_ids[0])
	check(bool(first.get("ok", false)), "peer 1 enters body A")
	var body_a = controller.body_of(merc_ids[0])
	check(warband.souls.body_of(1) == merc_ids[0], "the router records peer 1 inside A")
	check(warband.possessed_by(1) == merc_ids[0], "the warband mirror records the possession")
	check(body_a.is_local and not body_a.is_bot, "the possessed body takes player input")
	check(not body_a.predicting, "the host body is simulated, never predicted")
	check(controller.active_actor == body_a, "the controller's active body is A")

	var stolen: Dictionary = controller.activate(2, merc_ids[0])
	check(not bool(stolen.get("ok", false)), "peer 2 is refused body A")
	check(str(stolen.get("reason", "")) == SoulRouter.REASON_OCCUPIED,
		"the refusal names the occupied rule, got '%s'" % str(stolen.get("reason", "")))
	check(warband.souls.body_of(1) == merc_ids[0], "a refusal leaves peer 1 where it was")
	check(warband.souls.body_of(2) == -1, "a refusal does not put peer 2 anywhere")
	check(warband.souls.occupied_by(merc_ids[0]) == 1, "A stays peer 1's body")
	check(controller.active_actor == body_a, "a refusal does not move the local camera")

	var second: Dictionary = controller.activate(2, merc_ids[1])
	check(bool(second.get("ok", false)), "peer 2 enters body B instead")
	var body_b = controller.body_of(merc_ids[1])
	check(not body_b.is_local and not body_b.is_bot, "a remote peer's body is neither local nor AI")
	check(controller.active_actor == body_a, "peer 2's entry did not take local control")
	check(warband.possessed_by(2) == merc_ids[1], "the mirror holds both peers")
	check(events.size() == 2 and events[0] == [1, merc_ids[0]] and events[1] == [2, merc_ids[1]],
		"possession_changed fired for each successful transfer only")

# --- cycling ---------------------------------------------------------------

func check_cycle(warband, controller, merc_ids: Array[int]) -> void:
	var before_one: int = warband.souls.body_of(1)
	var before_two: int = warband.souls.body_of(2)
	var next: Dictionary = controller.cycle(1, 1)
	check(bool(next.get("ok", false)), "peer 1 cycles forward")
	var now_one: int = warband.souls.body_of(1)
	check(now_one != before_one, "cycling forward changed peer 1's body")
	check(warband.souls.body_state(now_one) == Contracts.HealthState.ALIVE,
		"the new body is alive")
	check(warband.souls.occupied_by(before_one) == 0, "the old body is released")
	check(warband.souls.occupied_by(now_one) == 1, "the new body is peer 1's")
	check(warband.souls.body_of(2) == before_two, "peer 1's cycle never touches peer 2")
	check(controller.body_of(before_one).is_local == false,
		"the released body stops taking player input")

	var back: Dictionary = controller.cycle(1, -1)
	check(bool(back.get("ok", false)), "peer 1 cycles backward")
	var now_back: int = warband.souls.body_of(1)
	check(now_back != now_one and warband.souls.body_state(now_back) == Contracts.HealthState.ALIVE,
		"cycling backward lands on another living body")

	var second_cycle: Dictionary = controller.cycle(2, 1)
	check(bool(second_cycle.get("ok", false)), "peer 2 cycles forward")
	check(warband.souls.body_of(2) != warband.souls.body_of(1),
		"two souls never share a body after a cycle")
	check(warband.souls.occupied_by(warband.souls.body_of(2)) == 2, "peer 2 owns its body")
	check(warband.souls.occupied_by(warband.souls.body_of(1)) == 1, "peer 1 owns its body")

	# A downed body is skipped by the ring and refused by a direct ask.
	check(warband.souls.body_of(3) == -1, "no third peer has entered anything")
	var victim := merc_ids[3]
	warband.souls.set_body_state(victim, Contracts.HealthState.DOWNED)
	check(warband.souls.body_state(victim) == Contracts.HealthState.DOWNED, "body D is downed")
	for step in 10:
		var direction := 1 if step % 2 == 0 else -1
		var result: Dictionary = controller.cycle(1, direction)
		check(bool(result.get("ok", false)), "cycle %d still finds a body" % step)
		var landed: int = warband.souls.body_of(1)
		check(landed != victim, "a cycle never lands on a downed body")
		check(warband.souls.body_state(landed) == Contracts.HealthState.ALIVE
			and controller.body_of(landed).alive, "every cycle lands on a living body")

	var refused: Dictionary = controller.direct(1, victim)
	check(not bool(refused.get("ok", false)), "a direct ask for a downed body is refused")
	check(str(refused.get("reason", "")) == SoulRouter.REASON_DOWNED,
		"the refusal names the downed rule")
	check(warband.souls.occupied_by(victim) == 0, "the downed body stays empty")
	warband.souls.set_body_state(victim, Contracts.HealthState.ALIVE)

# --- camera ----------------------------------------------------------------

func check_camera(warband, controller, merc_ids: Array[int]) -> void:
	# Nobody else may be standing in the body this test watches.
	warband.souls.release_peer(2, "camera test")
	var entry: Dictionary = controller.activate(1, merc_ids[0])
	check(bool(entry.get("ok", false)), "peer 1 enters body A for the camera")
	var rider = controller.body_of(merc_ids[0])
	check(controller.camera_rig.active_body() == rider, "the camera rides the possessed body")
	check(controller.camera_rig.camera.current, "the possession camera is the active camera")
	var ray: Dictionary = controller.camera_rig.aim_ray()
	var origin: Vector3 = ray.get("origin", Vector3.ZERO)
	var direction: Vector3 = ray.get("direction", Vector3.ZERO)
	check(origin.distance_to(controller.camera_rig.camera.global_position) < 0.001,
		"the aim ray starts at the camera")
	check(is_equal_approx(direction.length(), 1.0), "the aim ray is a unit direction")

	var target = controller.body_of(merc_ids[4])
	controller.camera_rig.swoop_to(target, 0.35)
	check(controller.camera_rig.active_body() == target, "a swoop retargets immediately")
	check(controller.camera_rig.camera.global_position.distance_to(controller.camera_rig.follow_point()) > 0.5,
		"the swoop has not arrived on its first frame")
	for frame in 14:
		controller.camera_rig.update(0.035)
	var settled: Vector3 = controller.camera_rig.camera.global_position
	check(settled.distance_to(controller.camera_rig.follow_point()) <= 1.0,
		"the swoop ends on the follow point, %.2f m away" % settled.distance_to(controller.camera_rig.follow_point()))
	check(settled.y > target.global_position.y + 0.5,
		"the settled camera stays above the body it rides")

	var second: Dictionary = controller.activate(1, merc_ids[2])
	check(bool(second.get("ok", false)), "peer 1 enters a third body")
	check(controller.camera_rig.active_body() == controller.body_of(merc_ids[2]),
		"a second activate retargets the camera")
	check(controller.camera_rig.camera.global_position.distance_to(
		controller.camera_rig.follow_point()) > 0.05, "that retarget starts an arc, not a cut")

# --- eject on a router state change ---------------------------------------

## A downed body keeps its soul: the player crawls it themselves and waits to be
## picked up. Only a death moves the soul out.
func check_router_eject(warband, controller, merc_ids: Array[int]) -> void:
	controller.activate(1, merc_ids[0])
	var doomed := merc_ids[0]
	warband.souls.set_body_state(doomed, Contracts.HealthState.DOWNED)
	await physics_frame
	check(warband.souls.body_of(1) == doomed, "a downed body keeps its soul")
	check(warband.souls.occupied_by(doomed) == 1, "the downed body is still occupied")
	check(controller.merc_for_peer(1) == doomed, "the peer map still names the downed body")
	check(controller.active_actor == controller.body_of(doomed),
		"the controller keeps riding the downed body")
	warband.souls.set_body_state(doomed, Contracts.HealthState.DEAD)
	await physics_frame
	check(warband.souls.body_of(1) != doomed, "a dead body lets the soul go")
	check(warband.souls.occupied_by(doomed) == 0, "the dead body is unoccupied")
	var landed: int = warband.souls.body_of(1)
	if landed > 0:
		check(warband.souls.body_state(landed) == Contracts.HealthState.ALIVE,
			"the soul moved to a living body")
		check(controller.active_actor == controller.body_of(landed),
			"the controller follows the soul to the new body")
		check(controller.merc_for_peer(1) == landed, "the peer map names the new body")
	warband.souls.set_body_state(doomed, Contracts.HealthState.ALIVE)
	await physics_frame

# --- eject on real damage --------------------------------------------------

func check_health_eject(warband, controller, merc_ids: Array[int]) -> void:
	var entry: Dictionary = controller.activate(1, merc_ids[0])
	check(bool(entry.get("ok", false)), "peer 1 is back inside body A")
	var victim = controller.body_of(merc_ids[0])
	var before: int = warband.souls.body_of(1)
	# A campaign body is never killed by the blow itself: 300 damage on a 100
	# pool puts it on its chest for the whole bleed clock, whatever the hit was.
	victim.take_damage(300.0, 99)
	check(victim.alive and bool(victim.downed),
		"a blow that would be lethal drops a warband body instead of killing it")
	check(victim.rig.visible, "a downed body is still on screen")
	check(warband.souls.body_of(1) == before, "the downed body keeps its soul")
	check(warband.souls.body_state(before) == Contracts.HealthState.DOWNED,
		"the router records the body as downed, not dead")
	# A blow that lands on it while it is down is a finisher, and that is the only
	# thing here that ends a campaign body short of the bleed clock.
	victim.take_damage(1.0, 99)
	check(not victim.alive, "any blow that lands on a downed body finishes it")
	check(victim.rig.visible, "the corpse stays where it fell instead of vanishing")
	check(victim.rig.is_downed_pose(), "the corpse keeps the lie it fell in")
	check(victim.rig.corpse_still, "and it lies still instead of dragging itself along")
	var landed: int = warband.souls.body_of(1)
	check(landed != before and landed > 0, "the soul left the body the hit finished")
	check(warband.souls.body_state(before) == Contracts.HealthState.DEAD,
		"the finished body is dead in the router")
	check(warband.souls.occupied_by(before) == 0, "the dead body is unoccupied")
	check(controller.active_actor != victim, "the controller stopped riding the corpse")
	check(controller.active_actor != null and controller.active_actor.alive,
		"the soul is in a living body after the kill")
	var refused: Dictionary = controller.direct(1, before)
	check(not bool(refused.get("ok", false)), "a dead body cannot be re-entered")
	check(str(refused.get("reason", "")) == SoulRouter.REASON_DEAD, "the refusal names death")
	# The downed/revive worktree owns body health; the fixture stands the body
	# back up so the later ownership checks start from a clean squad.
	victim.revive()
	warband.souls.set_body_state(before, Contracts.HealthState.ALIVE)
	await physics_frame

# --- the squad is gone -----------------------------------------------------

func check_squad_release(warband, controller, merc_ids: Array[int], events: Array) -> void:
	var held: int = warband.souls.body_of(1)
	if held <= 0:
		controller.activate(1, merc_ids[5])
		held = warband.souls.body_of(1)
	for body_id in warband.souls.body_ids():
		if warband.souls.body_state(body_id) == Contracts.HealthState.ALIVE:
			# Dead, not downed: a downed body keeps its soul on purpose.
			warband.souls.set_body_state(body_id, Contracts.HealthState.DEAD)
	check(not warband.souls.is_possessed(1), "with every body gone the peer is released")
	check(warband.possessed_by(1) == -1, "the warband mirror forgets the possession")
	check(controller.active_actor == null, "no body takes input any more")
	check(not controller.camera_rig.has_target(), "the camera has nobody to ride")
	check(events.size() > 0 and events[-1] == [1, -1],
		"possession_changed reported the release to the HUD")
	var refused: Dictionary = controller.activate(1, merc_ids[2])
	check(not bool(refused.get("ok", false)), "a dead squad cannot be re-entered")
	check(str(refused.get("reason", "")) == SoulRouter.REASON_DEAD,
		"the refusal names death")
	for body_id in warband.souls.body_ids():
		warband.souls.set_body_state(body_id, Contracts.HealthState.ALIVE)

# --- server_apply ----------------------------------------------------------

func check_server_apply(warband, controller, merc_ids: Array[int]) -> void:
	var sync = controller.sync
	check(sync != null, "the controller owns the netcode half")
	warband.souls.release_peer(1, "test")
	warband.souls.release_peer(2, "test")
	var host_entry: Dictionary = controller.activate(1, merc_ids[0])
	check(bool(host_entry.get("ok", false)), "the host soul is inside body A")

	var steal: Dictionary = sync.server_apply(2, merc_ids[0])
	check(not bool(steal.get("ok", false)), "a remote peer cannot steal an occupied body")
	check(str(steal.get("reason", "")) == SoulRouter.REASON_OCCUPIED,
		"the steal is refused as occupied")
	check(warband.souls.body_of(1) == merc_ids[0], "the host's own soul is unchanged")
	check(warband.souls.occupied_by(merc_ids[0]) == 1, "the host still owns body A")
	check(warband.souls.body_of(2) == -1, "the thief gained nothing")
	check(controller.active_actor == controller.body_of(merc_ids[0]),
		"the host still controls its own body")

	var granted: Dictionary = sync.server_apply(2, merc_ids[1])
	check(bool(granted.get("ok", false)), "a free body is granted over the same path")
	check(warband.souls.body_of(2) == merc_ids[1], "peer 2 now holds body B")
	check(warband.souls.body_of(1) == merc_ids[0], "the host keeps body A")
	var peer_two_body = controller.body_of(merc_ids[1])
	check(peer_two_body.peer_id == 2 and not peer_two_body.is_local,
		"the granted body belongs to the remote peer")
	check(controller.active_actor == controller.body_of(merc_ids[0]),
		"the host did not take control of a peer's body")

# --- input reaches the possessed body -------------------------------------

func check_live_input(warband, controller, merc_ids: Array[int]) -> void:
	warband.souls.release_peer(2, "test")
	controller.activate(1, merc_ids[0])
	var before: int = warband.souls.body_of(1)
	controller._unhandled_input(key_event(KEY_BRACKETRIGHT))
	var after: int = warband.souls.body_of(1)
	check(after != before, "']' cycles the local soul through the real input handler")
	check(warband.souls.occupied_by(after) == 1, "']' moved the soul, it did not copy it")

	var ids: Array[int] = controller.living_merc_ids()
	check(ids.size() == 8, "all eight bodies are living and direct-selectable")
	controller._unhandled_input(key_event(KEY_F1))
	check(warband.souls.body_of(1) == ids[0], "F1 enters the first living body")
	controller._unhandled_input(key_event(KEY_F8))
	check(warband.souls.body_of(1) == ids[7], "F8 enters the eighth living body")
	check(controller.active_actor == controller.body_of(ids[7]),
		"F8 retargeted the camera and the input")

	# A bow body draws on LMB through the same handler the mode calls. What is in
	# its hands comes from its gear: `refresh_gear` re-dresses it from the roster,
	# and 1..5 - an admin leftover that spawned a bow, a sword, a shield and a
	# second blade out of nothing - must not answer at all.
	var bow_id := merc_ids[0]
	controller.set_bot(bow_id, false)
	controller.activate(1, bow_id)
	for tick in 8:
		await physics_frame
	check(controller.active_actor != null and controller.active_actor.is_on_floor(),
		"the possessed body is standing before it draws")
	check(controller.refresh_gear(bow_id), "the roster kit re-dresses the body on demand")
	check(controller.active_actor.rig.weapon == "bow",
		"the shortbow is in its hands because its gear put it there")
	# 1/2/3 are the warband's ability slots now (deliberately not weapon keys);
	# 4 and 5 remain the admin leftovers this check exists to keep inert.
	for keycode in [KEY_4, KEY_5]:
		controller._unhandled_input(key_event(keycode))
	check(controller.active_actor.rig.weapon == "bow",
		"4-5 put no weapon on the possessed body")
	check(not controller.active_actor.rig.shield_equipped,
		"and no shield either")
	controller._unhandled_input(mouse_event(MOUSE_BUTTON_LEFT, true))
	check(controller.active_actor.rig.phase in ["DRAWING", "HOLDING"],
		"a left click starts a real bow draw on the possessed body")
	# Presses go through `_unhandled_input`, releases through `_input`, exactly
	# as the arena splits them.
	controller._input(mouse_event(MOUSE_BUTTON_LEFT, false))
	check(controller.active_actor.rig.phase != "DRAWING",
		"releasing the click leaves the draw")
	await physics_frame

# --- movement arrives from the wire path ----------------------------------

func check_wire_movement(warband, controller, merc_ids: Array[int]) -> void:
	var entry: Dictionary = controller.activate(1, merc_ids[6])
	check(bool(entry.get("ok", false)), "peer 1 enters the staff body")
	var actor = controller.active_actor
	check(actor != null and actor.authoritative, "the driven body is authoritative")
	# A menu is up, so no keyboard intent competes with the wire: this loop
	# injects the same frame a client would send, one per physics tick.
	controller.input_enabled = false
	var start: Vector3 = actor.global_position
	for tick in 12:
		controller.apply_move(merc_ids[6], Vector2(0, -1), false)
		await physics_frame
	controller.input_enabled = true
	var travelled: Vector3 = actor.global_position - start
	check(travelled.length() > 0.15, "a wired movement frame walks the possessed body (%.2f m)" % travelled.length())
	check(travelled.z < -0.1, "the body walks along the frame's direction, z=%.2f" % travelled.z)

	# The admin arena steps the squad itself, so `auto_simulate` must let it and
	# a same-tick double call must not integrate the bodies twice.
	controller.auto_simulate = false
	var frozen: Vector3 = actor.global_position
	for tick in 3:
		controller.apply_move(merc_ids[6], Vector2(0, -1), false)
		await physics_frame
	check(actor.global_position.distance_to(frozen) < 0.001,
		"auto_simulate off leaves stepping to the mode")
	var before_step: Vector3 = actor.global_position
	controller.physics_step(1.0 / 60.0)
	check(actor.global_position.distance_to(before_step) > 0.0,
		"physics_step advances the squad for the mode")
	var after_step: Vector3 = actor.global_position
	controller.physics_step(1.0 / 60.0)
	check(actor.global_position.distance_to(after_step) < 0.000001,
		"a second physics_step in the same tick does nothing")
	controller.auto_simulate = true
