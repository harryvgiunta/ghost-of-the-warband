extends SceneTree

const Actor = preload("res://scripts/arena_actor.gd")
const Archer = preload("res://scripts/archer.gd")
const Arrow = preload("res://scripts/arrow.gd")
const Combat = preload("res://scripts/combat.gd")
const Shield = preload("res://scripts/shield.gd")

var checks := 0
var failures := 0
var world: Node3D
var victim

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func make_actor(index: int, at: Vector3):
	var actor := Actor.new()
	actor.slot = index
	actor.authoritative = true
	world.add_child(actor)
	actor.configure(index + 1, false, "Shield Regression", at)
	actor.set_physics_process(false)
	actor.rig.set_process(false)
	actor.rig.set_physics_process(false)
	actor.combat.set_motion(Vector3.ZERO, false, true)
	return actor

func fire(at: Vector3, direction: Vector3, damage: float = 20.0) -> Arrow:
	var arrow := Arrow.new()
	world.add_child(arrow)
	arrow.source_id = 1
	arrow.hit_mask = 1 | 4 | 8
	arrow.authoritative_damage = true
	arrow.launch(at,direction.normalized(),40.0,damage,[])
	return arrow

func check_shield_clear(rig, label: String) -> void:
	# Scan the actual skinned character surfaces against the shield's physical
	# disc volume. A carried shield centered on the wrist with its face forward
	# slices through the forearm; the same pose crouched cuts the torso/legs.
	var inverse: Transform3D = rig.active_shield.global_transform.affine_inverse()
	if rig.active_shield.global_position.is_zero_approx():
		check(false, "%s shield pose is uninitialized" % label)
		return
	var overlap := 0
	var where := ""
	for child in rig.find_children("*","MeshInstance3D",true,false):
		if child.skin == null or child.mesh == null:
			continue
		var transforms: Array[Transform3D] = []
		for index in child.skin.get_bind_count():
			var bone: int = rig.skeleton.find_bone(child.skin.get_bind_name(index))
			transforms.append(rig.skeleton.global_transform*rig.skeleton.get_bone_global_pose(bone)*child.skin.get_bind_pose(index))
		for surface in child.mesh.get_surface_count():
			var arrays: Array = child.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			if vertices.is_empty() or joints.is_empty():
				continue
			var influences := joints.size()/vertices.size()
			for vertex_index in vertices.size():
				var point := Vector3.ZERO
				for influence in influences:
					var slot := vertex_index*influences+influence
					if weights[slot] > 0.0:
						point += (transforms[joints[slot]]*vertices[vertex_index])*weights[slot]
				var local := inverse*point
				if Vector2(local.x,local.y).length() <= Shield.RADIUS and absf(local.z) <= Shield.THICKNESS*0.5+0.002:
					overlap += 1
					where = str(child.name)
					break
			if overlap > 0:
				break
		if overlap > 0:
			break
	check(overlap == 0, "%s shield clears the character mesh (%s)" % [label, where])

func run() -> void:
	world = Node3D.new()
	world.name = "ShieldWorld"
	root.add_child(world)
	victim = make_actor(0, Vector3.ZERO)
	await physics_frame
	await physics_frame

	# Equip rules: dagger and the medium arming sword only.
	victim.rig.set_weapon("dagger")
	check(victim.rig.set_shield(true), "The dagger accepts a shield")
	check(victim.rig.shield_equipped and victim.rig.active_shield.visible, "The equipped shield is visible")
	check(victim.rig.active_shield.collision_layer == Shield.SHIELD_LAYER, "The shield occupies the shield collision layer")
	victim.rig.set_weapon("sword")
	victim.rig.set_sword(1)
	check(victim.rig.set_shield(true), "The medium arming sword accepts a shield")
	victim.rig.set_sword(0)
	check(not victim.rig.shield_equipped, "Changing to the shortsword stows the shield")
	check(not victim.rig.set_shield(true), "The shortsword cannot raise the shield")
	victim.rig.set_sword(2)
	check(not victim.rig.shield_equipped, "The greatsword cannot carry the shield")
	victim.rig.set_weapon("bow")
	check(not victim.rig.set_shield(true), "The bow cannot carry the shield")
	victim.rig.set_weapon("dagger")

	# Full front block with the shield; no parry and the shield stamina cost.
	check(victim.rig.set_shield(true), "The dagger shield is equipped for the block")
	victim.combat.set_motion(Vector3.ZERO,false,true)
	check(victim.combat.start_block(Vector3(0,0,1)), "RMB raises the shield")
	await physics_frame
	await physics_frame
	var forward := Vector3(0,0,1)
	var shield_center: Vector3 = victim.rig.active_shield.global_position
	check((shield_center-victim.global_position).dot(forward) > 0.3, "The shield is raised in front of the chest")
	check(victim.rig.active_shield.collision_layer == Shield.SHIELD_LAYER, "The raised shield intercepts arrows")
	var attacker_at: Vector3 = victim.global_position+Vector3(0,0,1)
	check(victim.combat.resolve_melee_defense(attacker_at) == Combat.DEFENSE_BLOCK, "The shield is a full front block, not a dagger weak block")
	check(is_equal_approx(victim.combat.block_stamina_cost(), Combat.SHIELD_BLOCK_STAMINA), "The shield uses the shield stamina cost")
	victim.health = 100.0
	victim.stamina = 100.0
	var outcome: int = victim.receive_melee(20.0,1,attacker_at,false)
	check(outcome == Combat.DEFENSE_BLOCK, "Arena melee reports the shield block")
	check(is_equal_approx(victim.health,100.0), "A shield block takes no damage")
	check(is_equal_approx(victim.stamina,100.0-Combat.SHIELD_BLOCK_STAMINA), "A shield block spends the shield stamina chunk")

	# An arrow into the raised shield stops with no damage and sticks.
	var shield_hit := fire(shield_center+forward*1.5,-forward)
	await create_timer(0.25).timeout
	check(is_equal_approx(victim.health,100.0), "An arrow into the shield deals no damage")
	check(shield_hit.get_parent() == victim.rig.active_shield, "The arrow sticks into the raised shield")
	check(shield_hit.visible, "The shield-stuck arrow stays visible")
	check(not shield_hit.flying, "The shield-stuck arrow stops flying")

	# Passive shield hit without raising it.
	victim.combat.stop_block()
	victim.rig.set_shield(true)
	await physics_frame
	await physics_frame
	var rest_center: Vector3 = victim.rig.active_shield.global_position
	var rest_hit := fire(rest_center+Vector3(0,0,1.5),Vector3(0,0,-1))
	await create_timer(0.25).timeout
	check(is_equal_approx(victim.health,100.0), "An arrow hitting the carried shield deals no damage")
	check(rest_hit.get_parent() == victim.rig.active_shield, "The arrow sticks into the carried shield")

	# An arrow into the body damages the player and sticks in the player.
	victim.rig.set_shield(false)
	victim.combat.stop_block()
	victim.health = 100.0
	await physics_frame
	await physics_frame
	var body_center: Vector3 = victim.global_position+Vector3(0,1.2,0)
	var body_hit := fire(body_center+Vector3(0,0,1.5),Vector3(0,0,-1))
	await create_timer(0.25).timeout
	check(victim.health < 100.0, "An arrow into an unshielded player deals damage")
	check(body_hit.get_parent() == victim, "The arrow sticks into the player body")
	check(body_hit.visible, "The body-stuck arrow stays visible")

	# Arena host action path.
	var arena = load("res://arena.tscn").instantiate()
	root.add_child(arena)
	await create_timer(0.3).timeout
	arena.host_game(7898, "Shield Regression")
	await create_timer(0.2).timeout
	arena.send_action("weapon","dagger")
	await create_timer(0.1).timeout
	arena.send_action("shield",true)
	await create_timer(0.1).timeout
	check(arena.actors[0].rig.shield_equipped, "The arena host applies the shield action")
	check((int(arena.actors[0].snapshot().get("armor",0)) & 4) != 0, "The arena snapshot carries the shield state")
	arena.send_action("block",{"pressed":true,"forward":Vector3(0,0,-1)})
	await create_timer(0.1).timeout
	check(arena.actors[0].combat.blocking, "The arena host raises the shield block")
	arena.send_action("stop")
	arena.leave_game()
	arena.queue_free()
	await process_frame

	# Frontier controller path: equipment and the raised shield pose.
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.4).timeout
	game.archer.set_weapon("dagger")
	game.equip_shield(true)
	check(game.archer.shield_equipped, "The frontier equips the shield with the dagger")
	game.combat.set_motion(Vector3.ZERO,false,true)
	check(game.combat.start_block(Vector3(0,0,-1)), "The frontier raises the shield guard")
	await physics_frame
	await physics_frame
	var chest: Vector3 = game.archer._bone_world(game.archer._bones.spine_03).origin
	var raised: Vector3 = game.archer.active_shield.global_position
	check((raised-chest).dot(Vector3(0,0,-1)) > 0.25, "The frontier shield pose covers the front")
	game.queue_free()
	await process_frame

	# The shield pose must keep the physical disc out of the skinned character
	# in both carried and raised states, including while crouched.
	var clearance: Archer = Archer.new()
	world.add_child(clearance)
	clearance.set_physics_process(false)
	await physics_frame
	clearance.set_weapon("dagger")
	clearance.set_shield(true)
	clearance.advance_animation(0.6)
	await physics_frame
	await physics_frame
	check_shield_clear(clearance,"Carried")
	clearance.set_cover(false,Vector3.ZERO,1.0,false,Vector3.ZERO)
	clearance.advance_animation(0.6)
	await physics_frame
	await physics_frame
	check_shield_clear(clearance,"Crouched carried")
	clearance.set_blocking(true,Vector3(0,0,-1))
	clearance.advance_animation(0.6)
	await physics_frame
	await physics_frame
	check_shield_clear(clearance,"Crouched raised")
	clearance.set_cover(false,Vector3.ZERO,0.0,false,Vector3.ZERO)
	clearance.set_blocking(false)
	clearance.advance_animation(0.6)
	await physics_frame
	await physics_frame
	check_shield_clear(clearance,"Raised")
	clearance.queue_free()
	await process_frame

	world.queue_free()
	await process_frame
	print("SHIELD_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
