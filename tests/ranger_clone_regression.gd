extends SceneTree
## Crimson ranger clones: random kits, tint, arena-style AI, guard reaction,
## death reward and snapshot round-trip in both scene shapes.

const TestSave := "user://ranger_clone_regression_state.json"
const Clone = preload("res://scripts/ranger_clone.gd")
const CombatScript = preload("res://scripts/combat.gd")


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

	# Bow discipline: a distant clone draws and releases a real arrow.
	var archer = clones[1]
	archer.global_position = game.player.global_position + Vector3(0.0,0.1,14.0)
	archer.home = archer.global_position
	archer.combat.stop()
	archer._attack_cooldown = 0.0
	var arrows := [0]
	archer.arrow_fired.connect(func(_origin: Vector3, _direction: Vector3, _speed: float, _damage: float) -> void:
		arrows[0] += 1)
	var shot := await _wait_until(func(): return arrows[0] > 0,6.0)
	if shot:
		archer.global_position = game.player.global_position + Vector3(-40.0,0.1,40.0)
		archer.combat.stop()
	check(shot,"A distant clone draws and releases an arrow")
	check(archer.rig.weapon == "bow","The clone switches to the bow beyond nine metres")

	# Death: one reward, one corpse, no second payout.
	var doomed = clones[2]
	var rewards := [0]
	doomed.defeated.connect(func(_enemy: Node3D, amount: int) -> void: rewards[0] += amount)
	doomed.take_damage(999.0,-1)
	check(not doomed.alive and doomed.collision_layer == 0,"A lethal hit kills the clone")
	check(int(rewards[0]) == Clone.GOLD,"The clone pays its reward once")
	doomed.take_damage(999.0,-1)
	check(int(rewards[0]) == Clone.GOLD,"A dead clone cannot pay twice")

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
