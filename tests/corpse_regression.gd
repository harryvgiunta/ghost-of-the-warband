extends SceneTree
## Corpse regression: every mob kind keeps its corpse where it fell for the
## shared five-minute default instead of vanishing after a few seconds, falls
## under gravity, settles into a held pose, stops blocking collision, and still
## dissolves and frees through the one shared hold path when its clock runs out.

var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("CORPSE_FAIL  ", message)


func pause(seconds: float) -> void:
	await create_timer(seconds).timeout


func run() -> void:
	var watchdog := create_timer(90.0)
	watchdog.timeout.connect(_on_watchdog)
	var CorpseHold = load("res://scripts/corpse_hold.gd")
	var CorpsePhysics = load("res://scripts/corpse_physics.gd")
	var ImpactRules = load("res://scripts/impact_rules.gd")
	var Enemy = load("res://scripts/enemy.gd")
	var Mob = load("res://scripts/devil_mob.gd")
	var DelveDevil = load("res://scripts/delve_devil.gd")
	var ForestMob = load("res://scripts/forest_mob.gd")
	var CageWatcher = load("res://scripts/warband/cage_watcher.gd")

	check(is_equal_approx(CorpseHold.SECONDS, 300.0),
		"A corpse lies in the world for five minutes by default")
	check(CorpseHold.DISSOLVE_SECONDS > 0.0 and CorpseHold.DISSOLVE_SECONDS < 2.0,
		"The corpse frees itself through a short dissolve, never a pop")

	# Attack-style force: a right diagonal sends the victim left across the
	# blade travel, its mirror sends it right, overhead pushes away and an
	# arrow keeps its flight direction.
	var forward := Vector3(0.0, 0.0, -1.0)
	var right := forward.cross(Vector3.UP)
	var contact := Vector3.ZERO + forward * 1.5
	var right_cut: Vector3 = ImpactRules.melee_force(Vector3.ZERO, forward, right,
		contact, "diagonal_right", 1.0)
	var left_cut: Vector3 = ImpactRules.melee_force(Vector3.ZERO, forward, right,
		contact, "diagonal_left", -1.0)
	var overhead: Vector3 = ImpactRules.melee_force(Vector3.ZERO, forward, right,
		contact, "overhead", 1.0)
	var arrow: Vector3 = ImpactRules.projectile_force(Vector3(1.0, 0.0, 0.0))
	check(right_cut.dot(right) < -0.5,
		"A right-hand diagonal shoves the victim left across the swing")
	check(left_cut.dot(right) > 0.5,
		"A left-hand diagonal shoves the victim right across the swing")
	check(overhead.dot(forward) > 0.8,
		"An overhead shoves the victim away from the attacker")
	check(arrow.length() > 0.1 and arrow.normalized().x > 0.9,
		"A projectile keeps its travel direction as the corpse force")

	var fixture := Node3D.new()
	fixture.name = "CorpseFixture"
	root.add_child(fixture)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(60.0, 1.0, 60.0)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(floor_shape)
	fixture.add_child(floor_body)
	await physics_frame

	var wolf = Enemy.new()
	wolf.kind = 0
	var cinder = Enemy.new()
	cinder.kind = 2
	cinder.devil_weapon = "claw"
	var pack = Mob.new()
	pack.mob_id = "hell_goat"
	var delve = DelveDevil.new()
	delve.configure(1, "claw", 1)
	var delve_species = DelveDevil.new()
	delve_species.configure(2, "claw", 1, "hell_goat")
	pack.note_impact(Vector3(1.0, 0.0, 0.0))
	var corpses := [
		["Briar wolf", wolf, Vector3(-6.0, 0.12, 0.0)],
		["Cinder devil", cinder, Vector3(0.0, 0.12, 0.0)],
		["Hellish goat man", pack, Vector3(3.0, 0.12, 0.0)],
		["Delve devil", delve, Vector3(6.0, 0.12, 0.0)],
		["Delve goat", delve_species, Vector3(9.0, 0.12, 0.0)],
	]
	for entry in corpses:
		var body = entry[1]
		body.position = entry[2]
		fixture.add_child(body)
	await physics_frame
	await physics_frame

	for entry in corpses:
		var label := str(entry[0])
		var body = entry[1]
		check(body.alive, label + " starts alive")
		body.take_damage(99999.0, 0, false)
		await physics_frame
		check(not body.alive, label + " dies")
		check(body.collision_layer == 0, label + " corpse stops colliding")
		check(body.collision_mask == 1, label + " corpse still catches the world floor")
		check((body as Node3D).scale.is_equal_approx(Vector3.ONE),
			label + " corpse root keeps its scale while it is held")
		if body == pack:
			var goat_sim := pack._visual.find_child("CorpseRagdoll", true, false) as PhysicalBoneSimulator3D
			var goat_pelvis_body: PhysicalBone3D = null
			if goat_sim != null:
				for child in goat_sim.get_children():
					if child is PhysicalBone3D \
							and str((child as PhysicalBone3D).bone_name).to_lower() == "pelvis":
						goat_pelvis_body = child as PhysicalBone3D
			check(goat_pelvis_body != null
					and (goat_pelvis_body.linear_velocity.x > 0.05
						or goat_pelvis_body.angular_velocity.z < -0.05),
				"A killing blow's force drives the corpse along its direction")
	# Rigged mobs hand their skeleton to the shared ragdoll; only the procedural
	# depth-role devils keep their authored collapse and fall by root.
	check(CorpsePhysics.is_limp(wolf._wolf), "The wolf corpse is a physical ragdoll")
	check(CorpsePhysics.is_limp(cinder._devil), "The cinder corpse is a physical ragdoll")
	check(CorpsePhysics.is_limp(pack._visual), "An imported devil corpse is a physical ragdoll")
	check(CorpsePhysics.is_limp(delve_species._visual), "A delve species corpse is a physical ragdoll")
	check(not CorpsePhysics.is_limp(delve._visual), "A procedural corpse keeps its authored collapse")
	var wolf_sim := wolf._wolf.find_child("CorpseRagdoll", true, false) as PhysicalBoneSimulator3D
	var wolf_bones := wolf_sim.get_child_count() if wolf_sim != null else 0
	check(wolf_bones >= 10, "The wolf ragdoll builds its driven bone chain")
	var goat_skeleton := pack._visual.find_child("Skeleton3D", true, false) as Skeleton3D
	var eye_bone := goat_skeleton.find_bone("neutral_bone")
	var eye_parent := goat_skeleton.get_bone_name(goat_skeleton.get_bone_parent(eye_bone)) \
		if eye_bone >= 0 else ""
	check(eye_parent in ["Head", "head"],
		"The goat's stray eye bone is adopted by the head before simulation")
	if wolf_sim != null:
		var first_bone := wolf_sim.get_child(0) as PhysicalBone3D
		check(first_bone.collision_layer == 0 and first_bone.collision_mask == 1,
			"Corpse bones stop blocking fighters while still colliding with the world")

	# The authored poses are held, not reset by a fake delete.
	check(wolf._wolf.is_dead(), "The wolf enters its corpse ragdoll")
	check(cinder._devil.is_dead(), "The cinder devil enters its corpse ragdoll")
	check(pack._visual.is_dead(), "An imported devil enters its corpse ragdoll")
	check(delve._visual.is_dead(), "A delve devil holds its death pose")

	# Corpses obey gravity even when killed in the air: the primitive root and
	# the rigged limbs both reach the floor instead of hanging at the death spot.
	var falling_proc = DelveDevil.new()
	falling_proc.configure(9, "claw", 1)
	falling_proc.position = Vector3(-9.0, 5.0, 0.0)
	fixture.add_child(falling_proc)
	await physics_frame
	await physics_frame
	falling_proc.take_damage(99999.0, 0, false)
	await pause(1.6)
	check(falling_proc.global_position.y < 0.6,
		"A procedural devil killed in the air falls to the ground")
	check(not CorpsePhysics.is_limp(falling_proc._visual),
		"The procedural delve corpse has no physical skeleton")

	# --- A killing arrow takes the head with it. ---
	# Five bodies: one whose headshot is survivable, one killed by a plain blow,
	# one killed by a headshot, one procedural devil killed by a headshot, and one
	# replica told about a decapitation by the wire.
	var spared = Mob.new()
	spared.mob_id = "hell_goat"
	spared.position = Vector3(-12.0, 0.12, 0.0)
	fixture.add_child(spared)
	var plain = Mob.new()
	plain.mob_id = "hell_goat"
	plain.position = Vector3(-15.0, 0.12, 0.0)
	fixture.add_child(plain)
	var cut = Mob.new()
	cut.mob_id = "hell_goat"
	cut.position = Vector3(-18.0, 0.12, 0.0)
	fixture.add_child(cut)
	var cut_proc = DelveDevil.new()
	cut_proc.configure(3, "claw", 1)
	cut_proc.position = Vector3(-21.0, 0.12, 0.0)
	fixture.add_child(cut_proc)
	var beheaded_replica = Mob.new()
	beheaded_replica.mob_id = "hell_goat"
	beheaded_replica.position = Vector3(-24.0, 0.12, 0.0)
	fixture.add_child(beheaded_replica)
	await physics_frame
	await physics_frame

	spared.note_arrow_headshot(Vector3(0.0, 0.0, -45.0), 5.0)
	spared.take_damage(5.0, 0, true)
	check(spared.alive, "A headshot that does not kill leaves the head on the body")
	spared.take_damage(999.0, 0, false)
	check(spared._visual.find_child("SeveredHead", true, false) == null,
		"A headshot a body survived is never spent on a later kill")

	plain.take_damage(999.0, 0, false)
	check(plain._visual.find_child("SeveredHead", true, false) == null,
		"A body kill leaves the head on the corpse")
	var plain_skeleton := plain._visual.find_child("Skeleton3D", true, false) as Skeleton3D
	var plain_head := plain_skeleton.find_bone("Head")
	check(plain_skeleton.get_bone_pose(plain_head).basis.get_scale().x > 0.5,
		"An untouched head bone keeps its volume")

	# The real thing: a live arrow at the head, the blow kills, the head goes.
	var Arrow = load("res://scripts/arrow.gd")
	var aim: Vector3 = cut.head_hitbox_center()
	var facing: Vector3 = aim - cut.global_position
	facing.y = 0.0
	facing = facing.normalized()
	var shot: Node3D = Arrow.new()
	fixture.add_child(shot)
	var excluded: Array[RID] = []
	shot.launch(aim + facing * 0.9, -facing, 32.0, 60.0, excluded)
	await pause(0.3)
	var cut_skeleton := cut._visual.find_child("Skeleton3D", true, false) as Skeleton3D
	var cut_head := cut_skeleton.find_bone("Head")
	check(not cut.alive, "The killing headshot kills the body")
	check(cut_skeleton.get_bone_pose(cut_head).basis.get_scale().x < 0.05,
		"The corpse keeps a head bone with no volume left")
	check(cut_skeleton.get_bone_parent(cut_head) >= 0,
		"The stump stays jointed on the neck instead of flying with the head")
	var flight = cut._visual.find_child("SeveredHead", true, false)
	check(flight != null, "A killing headshot throws a head into the world")
	if flight != null:
		var piece := flight.find_child("GorePiece", true, false) as MeshInstance3D
		check(piece != null and piece.mesh != null
				and piece.mesh.get_surface_count() > 0
				and piece.mesh.surface_get_array_len(0) > 0,
			"The thrown piece is a mesh of its own, carrying the rig's surfaces")
		check(flight.get_child_count() == 2,
			"The arrow that killed it leaves the body with the head")
	await pause(1.2)
	if flight != null and is_instance_valid(flight):
		check((flight as Node3D).global_position.distance_to(cut.global_position) > 0.6,
			"The thrown head travels clear of the corpse")
		check((flight as Node3D).global_position.y < 0.9,
			"The thrown head comes down to the ground")
	await pause(1.4)
	if flight != null and is_instance_valid(flight):
		check(not flight.is_physics_processing(),
			"A head that has come to rest stops being simulated")

	cut_proc.note_arrow_headshot(Vector3(0.0, 0.0, -45.0), 60.0)
	cut_proc.take_damage(60.0, 0, true)
	var proc_head: Node3D = cut_proc._visual._head
	check(cut_proc._visual._severed,
		"A procedural devil stops posing the head it lost")
	check(proc_head.get_parent() != null
			and str(proc_head.get_parent().name) == "SeveredHead",
		"A procedural devil's head node is cut loose and thrown")

	var death_state := {
		"p": beheaded_replica.global_position, "y": 0.0, "v": Vector3.ZERO,
		"g": true, "s": "DEAD", "t": 0.0, "h": 0.0, "a": false,
		"x": Vector4.ZERO, "k": Vector4(0.0, 0.0, -45.0, 1.0),
	}
	beheaded_replica.apply_snapshot(death_state, 1)
	check(not beheaded_replica.alive, "A replica dies from the death snapshot")
	check(beheaded_replica._visual.find_child("SeveredHead", true, false) != null,
		"A replica throws the head its death snapshot names")


	# --- every rig family loses the head that flew -------------------------
	# The stump is only believable if the corpse draws nothing where the head was:
	# each species poses its own skeleton, and one that wrote the head back after
	# the sever would leave a face on the corpse with a head in the air beside it.
	var rest := []
	var slots := ["succubus", "spawn", "beast", "gargoyle"]
	for index in slots.size():
		var body = Mob.new()
		body.mob_id = slots[index]
		rest.append([slots[index], body, Vector3(-24.0, 0.12, 10.0 + 3.0 * index)])
	for index in 2:
		var species: String = ["ossuary_stalker", "gallowsroot"][index]
		var body = ForestMob.new()
		body.mob_id = species
		rest.append([species, body, Vector3(-24.0, 0.12, 22.0 + 3.0 * index)])
	var watcher = CageWatcher.new()
	watcher.mob_id = "hollow_warden"
	rest.append(["cage_watcher", watcher, Vector3(-24.0, 0.12, 28.0)])
	for entry in rest:
		entry[1].position = entry[2]
		fixture.add_child(entry[1])
	await physics_frame
	await physics_frame
	for entry in rest:
		entry[1].note_arrow_headshot(Vector3(0.0, 0.0, -45.0), 200.0)
		entry[1].take_damage(200.0, 0, true)
	await physics_frame
	await physics_frame
	for entry in rest:
		var label := str(entry[0])
		var visual: Node3D = entry[1]._visual
		var skeleton := visual.find_child("Skeleton3D", true, false) as Skeleton3D
		var head := _head_bone(skeleton)
		check(not entry[1].alive, label + " dies to the arrow")
		check(head >= 0 and skeleton.get_bone_pose(head).basis.get_scale().x < 0.05,
			label + " corpse keeps no head where the head was")
		check(visual.find_child("SeveredHead", true, false) != null,
			label + " threw the head into the world")

	# --- a two-handed overhead takes the body in two ----------------------
	# `SeveredBody`: the bones above the cut own the piece, the corpse keeps its
	# lower half, the guts spill under the cut, and the piece lands beside it.
	var cleaved = Mob.new()
	cleaved.mob_id = "hell_goat"
	cleaved.position = Vector3(-18.0, 0.12, 12.0)
	fixture.add_child(cleaved)
	var cleaved_proc = DelveDevil.new()
	cleaved_proc.configure(1, "claw", 1)
	cleaved_proc.position = Vector3(-18.0, 0.12, 18.0)
	fixture.add_child(cleaved_proc)
	var stabbed = Mob.new()
	stabbed.mob_id = "hell_goat"
	stabbed.position = Vector3(-18.0, 0.12, 24.0)
	fixture.add_child(stabbed)
	var bisected = Mob.new()
	bisected.mob_id = "hell_goat"
	bisected.position = Vector3(-12.0, 0.12, 12.0)
	fixture.add_child(bisected)
	var low_cut = Enemy.new()
	low_cut.kind = 0
	low_cut.position = Vector3(-12.0, 0.12, 18.0)
	fixture.add_child(low_cut)
	await physics_frame
	await physics_frame
	cleaved.note_cleave(Vector3(0.0, 0.0, -1.0))
	cleaved.take_damage(999.0, 0, false)
	cleaved_proc.note_cleave(Vector3(0.0, 0.0, -1.0))
	cleaved_proc.take_damage(999.0, 0, false)
	stabbed.take_damage(999.0, 0, false)
	bisected.note_cleave(Vector3(0.0, 0.0, -1.0), "vertical")
	bisected.take_damage(999.0, 0, false)
	low_cut.note_cleave(Vector3(0.0, 0.0, -1.0), "vertical")
	low_cut.take_damage(999.0, 0, false)
	await physics_frame
	await physics_frame
	var cleaved_skeleton := cleaved._visual.find_child("Skeleton3D", true, false) as Skeleton3D
	var collapsed := 0
	var solid := 0
	for index in cleaved_skeleton.get_bone_count():
		if cleaved_skeleton.get_bone_pose(index).basis.get_scale().x < 0.05:
			collapsed += 1
		else:
			solid += 1
	var holder = cleaved._visual.find_child("SplitBody", true, false)
	var piece := holder.find_child("GorePiece", true, false) as MeshInstance3D \
		if holder != null else null
	check(not cleaved.alive, "The two-handed chop kills the body")
	check(holder != null and piece != null and piece.mesh != null
			and piece.mesh.get_surface_count() > 0,
		"A two-handed overhead takes the upper body off as a piece")
	check(collapsed > 0 and solid > 0,
		"The corpse keeps its lower half and loses the bones above the cut")
	check(cleaved._visual.find_child("Entrails", true, false) != null,
		"The guts spill on the floor under the cut")
	check(stabbed._visual.find_child("SplitBody", true, false) == null,
		"A blow that is not a two-handed overhead does not split the body")
	check(cleaved_proc._visual.find_child("SplitBody", true, false) == null,
		"A body with no skeleton is not cut in two")
	var halves_holder = bisected._visual.find_child("SplitBody", true, false)
	var halves: Array = halves_holder.find_children("*", "MeshInstance3D", true, false) \
		if halves_holder != null else []
	check(halves.size() == 2, "An overhead slices the body into two halves")
	check(bisected._visual.find_child("BodyStump", true, false) == null,
		"A sliced body is replaced by its halves instead of keeping a stump")
	check(low_cut._wolf.find_child("SplitBody", true, false) == null,
		"A body with no third of itself to cut is not split")
	await pause(0.9)
	if holder != null and is_instance_valid(holder):
		check((holder as Node3D).global_position.y < 1.2,
			"The upper body comes down to the floor")

	# The old four-second corpse is the exact behavior this replaces: every
	# body must still be lying there well past it.
	await pause(5.2)
	for entry in corpses:
		var label := str(entry[0])
		var body = entry[1]
		check(is_instance_valid(body) and not body.is_queued_for_deletion(),
			label + " corpse is still lying there after five seconds")
		check(is_instance_valid(body) and body.is_inside_tree(),
			label + " corpse stays in the scene instead of being unparented")
		check(is_instance_valid(body) and body.collision_layer == 0,
			label + " corpse never re-enables collision")
	# The ragdoll retires after settling and leaves its baked pose in place.
	check(not CorpsePhysics.is_limp(wolf._wolf), "The wolf ragdoll retires after settling")
	check(not CorpsePhysics.is_limp(pack._visual), "The imported devil ragdoll retires after settling")
	var baked_head := _bone_world(wolf._wolf, "head")
	var baked_pelvis := _bone_world(wolf._wolf, "pelvis")
	check(baked_head.y < 0.8 and baked_pelvis.y < 0.8,
		"The settled wolf corpse lies on the ground")
	var wolf_spread := Vector2(baked_head.x - baked_pelvis.x,
		baked_head.z - baked_pelvis.z).length()
	check(wolf_spread > 0.3,
		"The wolf torso stays extended instead of folding into a pile")
	var goat_head_world := _bone_world(pack._visual, "Head")
	var goat_pelvis_world := _bone_world(pack._visual, "pelvis")
	check(goat_head_world.y < 0.6 and goat_pelvis_world.y < 0.6,
		"The goat corpse lies on the ground")
	var goat_spread := Vector2(goat_head_world.x - goat_pelvis_world.x,
		goat_head_world.z - goat_pelvis_world.z).length()
	check(goat_spread > 0.35,
		"The goat torso topples as one body instead of melting in place")

	await pause(0.4)
	var held_head := _bone_world(wolf._wolf, "head")
	check(held_head.distance_to(baked_head) < 0.05, "The settled limp pose is held for the corpse lifetime")

	# The shared hold dissolves and frees at the end of its clock.
	var stand_in := Node3D.new()
	var shrink := Node3D.new()
	stand_in.name = "CorpseStandIn"
	stand_in.add_child(shrink)
	fixture.add_child(stand_in)
	CorpseHold.hold(stand_in, shrink, 0.15)
	await pause(1.2)
	check(not is_instance_valid(stand_in),
		"The shared corpse hold dissolves and frees the body when the clock runs out")
	check(is_instance_valid(fixture), "The fixture survives its own corpse tear-down")

	fixture.queue_free()
	await process_frame
	print("CORPSE_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


## The deforming head bone of a rig, the same rule `SeveredHead` uses: the outer
## bone wins where a rig carries an empty `head` helper under `Head`.
func _head_bone(skeleton: Skeleton3D) -> int:
	if skeleton == null:
		return -1
	var found := -1
	for index in skeleton.get_bone_count():
		if skeleton.get_bone_name(index).to_lower() != "head":
			continue
		if found < 0:
			found = index
			continue
		var parent := skeleton.get_bone_parent(found)
		while parent >= 0:
			if parent == index:
				found = index
				break
			parent = skeleton.get_bone_parent(parent)
	return found


func _bone_world(visual: Node3D, bone_name: String) -> Vector3:
	var skeleton := visual.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return Vector3.ZERO
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		return Vector3.ZERO
	return skeleton.get_global_transform() * skeleton.get_bone_global_pose(bone).origin


func _on_watchdog() -> void:
	print("CORPSE_WATCHDOG failures=", failures, " checks=", checks)
	quit(2)
