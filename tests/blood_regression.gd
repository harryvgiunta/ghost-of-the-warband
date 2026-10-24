extends SceneTree
## Blood presentation regression: 60 s stains, body/weapon/floor coverage,
## projectile and melee hooks, per-owner and world budgets, death pools, and
## the replicated weapon-blood tally.

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("BLOOD_FAIL  ", message)

func pause(seconds: float) -> void:
	await create_timer(seconds).timeout

func run() -> void:
	var watchdog := create_timer(60.0)
	watchdog.timeout.connect(_on_watchdog)
	var BloodFx = load("res://scripts/blood_fx.gd")
	var FieldScript = load("res://scripts/blood_field.gd")
	var Enemy = load("res://scripts/enemy.gd")
	var Sword = load("res://scripts/sword.gd")
	check(is_equal_approx(BloodFx.LIFETIME, 60.0), "A blood stain lives for sixty seconds")

	# --- isolated lifetime, owner budget and severity shape -----------------
	var fixture := Node3D.new()
	root.add_child(fixture)
	var panel := StaticBody3D.new()
	panel.collision_layer = 1
	panel.collision_mask = 0
	var panel_shape := CollisionShape3D.new()
	var panel_box := BoxShape3D.new()
	panel_box.size = Vector3(40.0, 1.0, 40.0)
	panel_shape.shape = panel_box
	panel_shape.position = Vector3(0.0, -0.5, 0.0)
	panel.add_child(panel_shape)
	fixture.add_child(panel)
	var stub := Node3D.new()
	fixture.add_child(stub)
	# A primitive body for the stain to lie on: the fixture rig has no skeleton,
	# which is exactly the devil/sentinel path.
	var stub_body := MeshInstance3D.new()
	var stub_sphere := SphereMesh.new()
	stub_sphere.radius = 1.0
	stub_sphere.height = 2.0
	stub_sphere.radial_segments = 12
	stub_sphere.rings = 8
	stub_body.mesh = stub_sphere
	stub_body.position = Vector3(0.0, 1.0, 0.0)
	stub.add_child(stub_body)
	var stub_sword = Sword.new()
	stub_sword.sword_kind = 1
	stub.add_child(stub_sword)
	await physics_frame
	await physics_frame

	var lone = FieldScript.new()
	lone.name = "BloodFieldLone"
	lone.set_process(false)
	root.add_child(lone)
	var at := stub.global_position + Vector3(0.0, 1.0, 0.0)
	lone.wound(stub, at, 30.0, false, false, 1.0)
	check(lone.stain_count() == 2, "A body hit leaves a wound and a floor splat")
	check(lone.surface_stain_count() == 1, "The floor splat is registered as a surface stain")
	check(_count_meta(stub, "wound") == 1, "The wound is parented to the target rig")
	var normal_vertices := _latest_wound_vertices(stub)
	lone.clear_all()
	await process_frame
	lone.wound(stub, at, 30.0, true, false, 1.0)
	var head_vertices := _latest_wound_vertices(stub)
	check(head_vertices > normal_vertices, "A head hit adds more body blood")
	check(is_equal_approx(lone.lifetime, 60.0), "The field uses the sixty-second lifetime")

	# Owner budget: a single rig never accumulates unbounded coatings.
	lone.clear_all()
	await process_frame
	for index in 14:
		lone.wound(stub, at, 20.0, false, false, 1.0)
	await process_frame
	check(_count_meta(stub, "wound") == 10,
		"Only the ten newest per-rig wounds survive the cap")

	# Exact fade window: alive through 59.9 s, gone after 60 s.
	lone.clear_all()
	await process_frame
	lone.wound(stub, at, 30.0, false, false, 1.0)
	var stain: Dictionary = lone._stains[0]
	var stain_node: Node3D = stain.node
	check(is_equal_approx(float(stain.life), 60.0), "The registered stain records a 60 s life")
	lone.advance(56.9)
	check(lone.stain_count() == 2 and stain_node.visible, "Blood is fully present before the fade window")
	check(is_equal_approx((stain_node as GeometryInstance3D).transparency, 0.0),
		"Blood is fully opaque before the fade window")
	lone.advance(2.0)
	check((stain_node as GeometryInstance3D).transparency > 0.0,
		"Blood fades over the final three seconds")
	lone.advance(1.0)
	check(lone.stain_count() == 2, "Blood survives at 59.9 seconds")
	lone.advance(0.2)
	check(lone.stain_count() == 0, "Blood is released after sixty seconds")
	check(stain_node.is_queued_for_deletion(), "The expired stain node is queued for deletion")

	# --- weapon coating ------------------------------------------------------
	await process_frame
	BloodFx.stain_weapon_node(stub_sword, 44.0, 1.0)
	var stub_coating = stub_sword.get_node_or_null("BloodCoating")
	check(stub_coating != null, "A blade hit coats the weapon")
	check(stub_coating != null and _mesh_vertices(stub_coating) > 0,
		"A high-damage hit leaves droplets and a smear")
	var coating_box := (stub_coating as MeshInstance3D).get_aabb()
	check(coating_box.size.length() < 0.8,
		"A blade coating stays on the blade instead of ballooning")

	# --- bow smear -----------------------------------------------------------
	var arrow_visual = load("res://scripts/bow.gd").create_arrow_visual()
	fixture.add_child(arrow_visual)
	await process_frame
	BloodFx.stain_projectile(arrow_visual, 22.0)
	await process_frame
	var smear = arrow_visual.get_node_or_null("BloodSmear")
	check(smear != null, "An arrow carries a smear where it stuck")
	if smear != null:
		var smear_box := (smear as MeshInstance3D).get_aabb()
		check(smear_box.size.x <= 0.03 and smear_box.size.y <= 0.03,
			"The arrow smear never fattens past the shaft")
		check(smear_box.size.z <= 0.09,
			"The arrow smear stays a short wet streak, not a coating")

	# --- projectile hook -----------------------------------------------------
	var field = root.get_node_or_null("BloodField")
	check(field != null, "The first real blood event creates the scene field")
	var arrow_target = Enemy.new()
	arrow_target.kind = 2
	arrow_target.devil_weapon = "sword"
	arrow_target.position = Vector3(3.0, 0.12, 0.0)
	fixture.add_child(arrow_target)
	await physics_frame
	await process_frame
	var target_health: float = arrow_target.health
	var arrow = load("res://scripts/arrow.gd").new()
	fixture.add_child(arrow)
	var origin := Vector3(3.0, 1.0, 4.0)
	var aim: Vector3 = arrow_target.get_aim_position()
	arrow.hit_mask = 1 | 2 | 8
	var excluded: Array[RID] = []
	arrow.launch(origin, (aim - origin).normalized(), 40.0, 20.0, excluded, origin)
	var bursts_before: int = field.burst_count()
	await pause(0.4)
	check(arrow_target.health < target_health, "The projectile fixture damages its target")
	check(_count_meta(arrow_target, "wound") > 0, "A projectile wound leaves body blood")
	check(field.burst_count() != bursts_before, "A projectile contact sprays droplets")

	# --- frontier player and enemy hooks ------------------------------------
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await pause(0.8)
	field = root.get_node_or_null("BloodField")
	check(field != null, "The frontier shares the scene blood field")
	var stains_before: int = field.surface_stain_count()
	game.health = 100.0
	game.take_damage(17.0)
	await process_frame
	check(_count_meta(game.archer, "wound") > 0, "Player damage coats the ranger")
	check(field.surface_stain_count() > stains_before, "Player damage spatters the ground")
	game.archer.set_weapon("sword")
	await process_frame
	var weapon_anchor = game.archer.blood_weapon_anchor("right")
	check(weapon_anchor != null, "The drawn sword is the weapon blood anchor")
	BloodFx.stain_weapon(game.archer, 38.0, "right")
	await process_frame
	check(weapon_anchor.get_node_or_null("BloodCoating") != null,
		"Frontier melee blood reaches the ranger's blade")

	var devil = Enemy.new()
	devil.kind = 2
	devil.devil_weapon = "dagger"
	devil.position = game.player.global_position + Vector3(1.6, 0.12, 0.0)
	game.add_child(devil)
	await physics_frame
	await process_frame
	var devil_stains: int = field.stain_count()
	devil.take_damage(12.0, -1)
	await process_frame
	check(field.stain_count() > devil_stains, "A devil wound adds field stains")
	BloodFx.stain_weapon(devil, 12.0)
	var devil_weapon = devil.blood_weapon_anchor()
	check(devil_weapon != null, "An armed devil exposes its held weapon")
	check(devil_weapon.get_node_or_null("BloodCoating") != null,
		"Blood reaches the devil's held weapon")
	devil.take_damage(999.0, -1)
	await process_frame
	check(_count_meta(field, "pool") >= 1, "A lethal hit leaves a persistent pool")
	check(_count_meta(devil, "wound") >= 2, "A lethal hit floods the body with wounds")

	# World budget recycles oldest splats instead of growing without bound.
	field.max_surface_stains = 4
	for index in 8:
		field.wound(game.archer, game.player.global_position + Vector3(0.0, 1.0, 0.0),
			10.0, false, false, 1.0)
	check(field.surface_stain_count() <= 4, "Surface stains honour the render budget")

	# --- replicated weapon tally --------------------------------------------
	var socket := PacketPeerUDP.new()
	check(socket.bind(0) == OK, "The blood fixture gets a free UDP port")
	var port := socket.get_local_port()
	socket.close()
	var arena = load("res://arena.tscn").instantiate()
	root.add_child(arena)
	arena.host_game(port, "Blood Regression")
	await pause(0.4)
	var source = arena.actors[0]
	var replica = arena.actors[1]
	source.rig.set_weapon("sword")
	replica.authoritative = false
	await pause(0.2)
	var replica_state: Dictionary = source.snapshot()
	replica_state.peer = replica.peer_id
	replica_state.bot = replica.is_bot
	replica.apply_snapshot(replica_state)
	await process_frame
	replica_state.weapon_blood = float(replica.weapon_blood) + 25.0
	replica.apply_snapshot(replica_state)
	await process_frame
	check(float(source.snapshot().get("weapon_blood", -1.0)) >= 0.0,
		"Snapshots carry the weapon blood tally")
	check(replica.weapon_blood >= 25.0, "The replica accepts the host tally")
	if replica.rig.blood_weapon_anchor() != null:
		check(replica.rig.blood_weapon_anchor().get_node_or_null("BloodCoating") != null,
			"A replicated tally coats the rendered weapon")

	# --- delve compiles and builds its HUD with inherited blood helpers -------
	var delve = load("res://delve.tscn").instantiate()
	root.add_child(delve)
	await pause(0.5)
	check(delve.hud != null, "The delve scene builds its HUD")
	check(delve.actors[0].has_method("note_weapon_blood"),
		"The delve actor inherits the weapon blood tally")

	# --- cleanup -------------------------------------------------------------
	delve.queue_free()
	arena.queue_free()
	game.queue_free()
	lone.queue_free()
	await process_frame
	print("BLOOD_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _on_watchdog() -> void:
	print("BLOOD_WATCHDOG failures=", failures, " checks=", checks)
	quit(2)

func _count_meta(node: Node, kind: String) -> int:
	var count := 0
	for child in node.find_children("*", "", true, false):
		if child.is_queued_for_deletion():
			continue
		if child.has_meta("blood_stain") and str(child.get_meta("blood_stain")) == kind:
			count += 1
	return count

func _latest_wound_vertices(rig: Node) -> int:
	var latest := 0
	for child in rig.find_children("*", "", true, false):
		if child.is_queued_for_deletion():
			continue
		if child.has_meta("blood_stain") and str(child.get_meta("blood_stain")) == "wound":
			latest = _mesh_vertices(child)
	return latest

func _mesh_vertices(node: Node) -> int:
	if node is not MeshInstance3D or (node as MeshInstance3D).mesh == null:
		return 0
	var mesh := (node as MeshInstance3D).mesh
	if mesh.get_surface_count() == 0:
		return 0
	var arrays = mesh.surface_get_arrays(0)
	var vertices = arrays[Mesh.ARRAY_VERTEX]
	return vertices.size() if vertices != null else 0
