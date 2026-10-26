extends SceneTree
## Crimson ranger clones: random kits, tint, arena-style AI, guard reaction,
## death reward and snapshot round-trip in both scene shapes.

const TestSave := "user://ranger_clone_regression_state.json"
const Clone = preload("res://scripts/ranger_clone.gd")
const CombatScript = preload("res://scripts/combat.gd")
const CorpsePhysics = preload("res://scripts/corpse_physics.gd")
const CloneActor = preload("res://scripts/arena_actor.gd")
const ArrowScript = preload("res://scripts/arrow.gd")


class DummyTarget:
	extends Node3D
	var combat
	var alive := true

var failures := 0
var checks := 0
var state
var game

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("RANGER_CLONE_FAIL  ",message)

func _wait_until(predicate: Callable, timeout: float = 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())

func _remove_test_save() -> void:
	if FileAccess.file_exists(TestSave):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TestSave))

func run() -> void:
	_remove_test_save()
	state = root.get_node("PlayerState")
	state.save_path = TestSave
	state.reset(false)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.5).timeout

	var clones: Array = []
	for enemy in game.enemies:
		if int(enemy.get("kind")) == 8:
			clones.append(enemy)
	check(clones.size() == 4,"The frontier fields four ranger clones")
	check(game._enemies_by_index.size() == game.enemies.size(),"Clones join the replicated enemy list")

	var main_items := {}
	var armor_bits := {}
	var tinted := 0
	for clone in clones:
		check(clone.collision_layer == 2,"A clone stands on the enemy body layer")
		check(clone.health == 100.0 and clone.max_health == 100.0,"A clone carries ranger health")
		check(is_instance_valid(clone.rig) and clone.rig.weapon != "","A clone carries a player rig and weapon")
		main_items[str(clone.held_weapon_id())] = true
		armor_bits[int(clone.rig.armor_bits())] = true
		if _is_tinted(clone):
			tinted += 1
	check(main_items.size() >= 2,"Clones roll different main weapons")
	check(armor_bits.size() >= 2,"Clones roll different armor")
	check(tinted == clones.size(),"Every clone is red-black tinted")

	# AI: put one clone in sword range of the ranger and watch it swing.
	var fighter = clones[0]
	fighter.global_position = game.player.global_position + Vector3(2.0,0.1,6.0)
	fighter.home = fighter.global_position
	fighter.velocity = Vector3.ZERO
	if fighter.attacked.is_connected(game._on_enemy_attack):
		fighter.attacked.disconnect(game._on_enemy_attack)
	var swung := await _wait_until(func(): return str(fighter.rig.phase).begins_with("MELEE") \
		or fighter.combat.attack_progress < 0.999,6.0)
	check(swung,"The clone closes and swings like an arena bot")
	check(fighter.rig.weapon == "sword" or fighter.rig.weapon == "dagger","The clone picks the blade inside nine metres")

	# Guard reaction: an incoming swing makes the clone raise its guard. A stub
	# target owns a Combat clock at 0.2, so the AI's threat read is stable.
	fighter.combat.stop()
	fighter.combat.attack_progress = 1.0
	fighter._guard_cooldown = 0.0
	var dummy := DummyTarget.new()
	dummy.combat = CombatScript.new()
	dummy.combat.attack_progress = 0.2
	dummy.add_child(dummy.combat)
	root.add_child(dummy)
	dummy.global_position = fighter.global_position + Vector3(0.0,0.0,1.4)
	fighter.targets = [dummy]
	var guarded := false
	var guard_deadline := Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < guard_deadline:
		fighter.combat.stop()
		fighter.combat.attack_progress = 1.0
		fighter._guard_cooldown = 0.0
		await physics_frame
		if fighter.combat.blocking:
			guarded = true
			break
	fighter.targets = []
	fighter.fallback_target = game.player
	dummy.queue_free()
	check(guarded,"The clone reacts to an incoming swing with a guard")

	# Bow discipline: a distant clone draws and releases a real arrow while it
	# walks the gap down. Outside `BLADE_RANGE` the bow is the weapon; inside it
	# the clone puts the blade away and closes, which is the whole point.
	var archer = clones[1]
	archer.global_position = game.player.global_position + Vector3(0.0,0.1,20.0)
	archer.home = archer.global_position
	archer.combat.stop()
	archer._attack_cooldown = 0.0
	var arrows := [0]
	archer.arrow_fired.connect(func(_origin: Vector3, _direction: Vector3, _speed: float, _damage: float) -> void:
		arrows[0] += 1)
	var shot := await _wait_until(func(): return arrows[0] > 0,6.0)
	check(shot,"A distant clone draws and releases an arrow")
	check(archer.rig.weapon == "bow","The clone fights with the bow outside blade range")
	var closed := await _wait_until(func(): return _gap(archer) <= Clone.BLADE_RANGE,8.0)
	check(closed,"A clone that shoots from range still walks the gap down")
	check(archer.rig.weapon != "bow" or archer.combat.attack_progress < 0.999,
		"The clone leaves the bow behind once it is inside blade range")
	archer.global_position = game.player.global_position + Vector3(-40.0,0.1,40.0)

	# A blow from far outside the aggro range still gives the clone the fight:
	# nothing escapes by running.
	var provoked = clones[2]
	provoked.global_position = game.player.global_position + Vector3(0.0,0.1,55.0)
	provoked.home = provoked.global_position
	provoked.targets = []
	provoked.fallback_target = game.player
	provoked._target = null
	check(not provoked._within_aggro(game.player),"A clone ignores a ranger beyond its aggro range")
	provoked.note_attacker(game.player)
	check(provoked._within_aggro(game.player),"A landed blow reaches a clone past its aggro range")
	var came := await _wait_until(func(): return _gap(provoked) < 45.0,8.0)
	check(came,"A struck clone walks the whole way to the ranger that shot it")
	provoked.global_position = game.player.global_position + Vector3(40.0,0.1,-40.0)
	provoked._senses.clear()

	# A crimson clone's arrow is an ordinary shaft: a raised shield stops it.
	# The lane is built on a bare platform well above the frontier so the shot
	# is judged by the guard and the body, never by scenery between them.
	var lane_root := Node3D.new()
	lane_root.position = Vector3(0.0,300.0,0.0)
	root.add_child(lane_root)
	var plate := StaticBody3D.new()
	plate.collision_layer = 1
	var plate_shape := CollisionShape3D.new()
	var plate_box := BoxShape3D.new()
	plate_box.size = Vector3(60.0,1.0,60.0)
	plate_shape.shape = plate_box
	plate.add_child(plate_shape)
	plate.position = Vector3(0.0,-0.5,0.0)
	lane_root.add_child(plate)
	await physics_frame
	var shield_target = CloneActor.new()
	lane_root.add_child(shield_target)
	shield_target.slot = 9
	shield_target.authoritative = true
	shield_target.configure(9,false,"Shield Probe",Vector3(0.0,0.1,0.0))
	shield_target.set_process(false)
	shield_target.rig.set_process(false)
	shield_target.rig.set_physics_process(false)
	shield_target.combat.set_motion(Vector3.ZERO,false,true)
	shield_target.rig.set_weapon("sword")
	shield_target.rig.set_shield(true)
	shield_target.health = 100.0
	await physics_frame
	shield_target.set_block(true,Vector3(0,0,-1))
	await physics_frame
	await physics_frame
	var bow_clone = clones[3]
	bow_clone.rig.set_weapon("bow")
	var base: Vector3 = lane_root.global_position
	var lane: Vector3 = base + Vector3(0.0,1.18,-12.0)
	var chest: Vector3 = base + Vector3(0.0,1.18,0.0)
	bow_clone._on_bow_released(lane,(chest-lane).normalized(),80.0,1.0)
	await create_timer(0.4).timeout
	var stuck := 0
	for child in shield_target.rig.active_shield.get_children():
		if child is ArrowScript:
			stuck += 1
	check(is_equal_approx(shield_target.health,100.0),"A clone arrow stops on a raised shield without damage")
	check(stuck > 0,"The clone arrow sticks into the raised shield")
	shield_target.queue_free()
	await process_frame
	# The same shot down the same lane on a body with no shield: the arrow is
	# an ordinary shaft, not something the guard merely failed to notice.
	var bare_target = CloneActor.new()
	lane_root.add_child(bare_target)
	bare_target.slot = 10
	bare_target.authoritative = true
	bare_target.configure(10,false,"Bare Probe",Vector3(0.0,0.1,0.0))
	bare_target.set_process(false)
	bare_target.rig.set_process(false)
	bare_target.rig.set_physics_process(false)
	bare_target.combat.set_motion(Vector3.ZERO,false,true)
	await physics_frame
	await physics_frame
	bare_target.health = 100.0
	bow_clone._on_bow_released(lane,(chest-lane).normalized(),80.0,1.0)
	await create_timer(0.4).timeout
	check(bare_target.health < 100.0,"The same clone arrow damages an unguarded ranger")
	lane_root.queue_free()
	await process_frame

	# Death: one reward, one corpse, no second payout.
	var doomed = clones[2]
	var rewards := [0]
	doomed.defeated.connect(func(_enemy: Node3D, amount: int) -> void: rewards[0] += amount)
	doomed.take_damage(999.0,-1)
	check(not doomed.alive and doomed.collision_layer == 0,"A lethal hit kills the clone")
	check(int(rewards[0]) == Clone.GOLD,"The clone pays its reward once")
	doomed.take_damage(999.0,-1)
	check(int(rewards[0]) == Clone.GOLD,"A dead clone cannot pay twice")
	check(CorpsePhysics.is_limp(doomed._body),"The clone corpse goes limp in a physical ragdoll")
	var corpse_arm: int = doomed.rig.skeleton.find_bone("hand_r")
	var corpse_bone: PhysicalBone3D = null
	var simulator := doomed.rig.skeleton.get_node_or_null("CorpseRagdoll") as PhysicalBoneSimulator3D
	if simulator != null:
		for child in simulator.get_children():
			if child is PhysicalBone3D and (child as PhysicalBone3D).get_bone_id() == corpse_arm:
				corpse_bone = child as PhysicalBone3D
	check(corpse_bone != null,"The clone's arm is part of its ragdoll")
	var hand_start := corpse_bone.global_position.y if corpse_bone != null else 0.0
	await create_timer(1.5).timeout
	if corpse_bone != null:
		check(corpse_bone.global_position.y < hand_start - 0.2,"A limp clone falls under gravity")
	check(doomed.collision_mask == 1,"A clone corpse still catches the world floor")

	# Snapshot round-trip for the frontier shape and the delve shape.
	var source = clones[3]
	var snapshot: Dictionary = source.snapshot()
	var replica = Clone.new()
	root.add_child(replica)
	replica.configure(source.clone_id,1,false,"scene")
	replica.apply_snapshot(snapshot)
	check(replica.replica and not replica.authoritative,"The clone replica is presentation-only")
	check(replica.global_position.distance_to(source.global_position) < 0.05,"The replica lands on the host position")
	check(absf(replica.health - source.health) < 0.01,"The replica copies health")
	check(str(replica.rig.weapon) == str(source.rig.weapon),"The replica copies the active weapon")
	check(str(replica.role()) == "ranger","The replica reports the ranger role")
	replica.queue_free()

	var delver = Clone.new()
	root.add_child(delver)
	delver.configure(77,3,true,"direct")
	delver.spawn_at(Vector3(0,0.1,0),Vector3.FORWARD)
	var delve_snapshot: Dictionary = delver.snapshot()
	check(int(delve_snapshot.get("kind",0)) == Clone.KIND and str(delve_snapshot.get("role","")) == "ranger","The delve snapshot names the clone")
	var delver_replica = Clone.new()
	root.add_child(delver_replica)
	delver_replica.configure(77,3,false,"direct")
	delver_replica.apply_snapshot(delve_snapshot)
	check(delver_replica.global_position.distance_to(delver.global_position) < 0.05,"The delve replica lands on the host position")
	check(absf(delver_replica.max_health - delver.max_health) < 0.01,"The delve replica copies the depth health")
	delver.queue_free()
	delver_replica.queue_free()

	game.queue_free()
	await process_frame
	_remove_test_save()
	print("RANGER_CLONE_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func _gap(clone) -> float:
	return clone.global_position.distance_to(game.player.global_position)

func _is_tinted(clone) -> bool:
	for node in clone.rig.find_children("*","MeshInstance3D",true,false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var material = mesh.get_surface_override_material(surface)
			if material is StandardMaterial3D:
				var color: Color = material.albedo_color
				if color.r > 0.2 and color.g < 0.06 and color.b < 0.06:
					return true
	return false
