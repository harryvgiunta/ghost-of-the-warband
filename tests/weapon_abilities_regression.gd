extends SceneTree
## Item skills: every catalog weapon grants exactly one ability, the two hand
## slots resolve from the held kit, effects carry the requested damage/spread,
## radial strikes and blasts damage the right bodies, and the planted effect
## cues, projectile and HUD work.

const Actor = preload("res://scripts/arena_actor.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const AbilityFx = preload("res://scripts/ability_fx.gd")
const Spell = preload("res://scripts/spell_projectile.gd")
const Enemy = preload("res://scripts/enemy.gd")
const Audio = preload("res://scripts/range_audio.gd")
const State = preload("res://scripts/player_state.gd")
const Stamina = preload("res://scripts/stamina.gd")

const WEAPONS := [
	["bow_short", 0, "barrage"],
	["bow_recurve", 0, "triple_volley"],
	["bow_long", 0, "piercing_shot"],
	["sword_short", 0, "double_slash"],
	["sword_arming", 0, "lunge_thrust"],
	["sword_great", 0, "spin_slash"],
	["dagger_iron", 0, "dash_stab"],
	["staff_fire", 0, "fireball"],
	["staff_bone", 0, "bone_spear"],
	["shield_buckler", 1, "shield_bash"],
	["shield_kite", 1, "shield_charge"],
	["shield_tower", 1, "shield_slam"],
]
const ARMOR := {"head":0,"chest":0,"hands":0,"legs":0,"feet":0}

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WEAPON_ABILITY_FAIL  ", message)


func equip(rig, main_id: String, off_id: String = "") -> void:
	rig.apply_loadout(State.build_loadout(main_id,off_id,ARMOR))


func fighter(parent: Node3D, index: int, at: Vector3) -> Node3D:
	var actor := Actor.new()
	actor.slot = index
	actor.authoritative = true
	parent.add_child(actor)
	actor.configure(index+1,false,"Weapon %d" % index,at)
	actor.set_process(false)
	actor.rig.set_physics_process(false)
	actor.set_physics_process(false)
	actor.combat.set_motion(Vector3.ZERO,false,true)
	actor.combat.target_mask = 4
	actor.combat.damage_enabled = true
	return actor


func run() -> void:
	var watchdog := create_timer(60.0)
	watchdog.timeout.connect(_on_watchdog)
	var world := Node3D.new()
	root.add_child(world)
	var probe := fighter(world,0,Vector3.ZERO)
	var rig = probe.rig
	var seen := {}
	for entry in WEAPONS:
		var item_id := str(entry[0])
		var slot := int(entry[1])
		var expected := str(entry[2])
		var definition: Dictionary = AbilityRules.by_item(item_id,slot)
		check(not definition.is_empty(), "%s grants a skill" % item_id)
		check(str(definition.get("id","")) == expected, "%s grants %s" % [item_id,expected])
		check(str(definition.get("item","")) == item_id, "%s owns its definition" % item_id)
		check(int(definition.get("slot",-1)) == slot, "%s declares the right hand slot" % item_id)
		check(str(definition.get("key","")) == ("SHIFT + 1" if slot == 0 else "SHIFT + 2"), "%s declares its key" % item_id)
		check(is_equal_approx(float(definition.get("stamina_cost",-1.0)),AbilityRules.TEST_STAMINA_COST), "%s costs a trivial stamina sliver" % item_id)
		check(float(definition.get("cooldown",0.0)) > 0.0, "%s has a cooldown" % item_id)
		check(float(definition.get("duration",0.0)) > 0.2, "%s has a real duration" % item_id)
		check(not str(definition.get("animation","")).is_empty(), "%s names its clip" % item_id)
		check(not str(definition.get("sound","")).is_empty(), "%s names its sound" % item_id)
		check(not str(definition.get("description","")).is_empty(), "%s describes itself" % item_id)
		check(not seen.has(expected), "%s has a unique id" % item_id)
		seen[expected] = true
		var icon: Texture2D = AbilityRules.icon_texture(expected)
		check(icon != null and icon.get_width() == 128, "%s icon loads at 128 px" % item_id)
		# Rig resolution: a legal hand pair must expose the same grant.
		if slot == 0:
			equip(rig,item_id,"")
		else:
			equip(rig,"sword_arming",item_id)
		var grants: Array = AbilityRules.granted(rig)
		check(str(grants[slot].get("id","")) == expected, "The held %s resolves its grant from the rig" % item_id)
		if slot == 1:
			check(str(grants[0].get("id","")) == "lunge_thrust", "A shield leaves the main-hand skill intact")
	# Duplicate shortbow: the starter spare is the same grant.
	equip(rig,"bow_short")
	check(str(AbilityRules.granted(rig)[0].get("id","")) == "barrage", "Both shortbows grant Barrage")

	var barrage: Dictionary = AbilityRules.by_item("bow_short",0)
	var barrage_effect: Dictionary = barrage.effect
	check(str(barrage_effect.kind) == "barrage", "Barrage is a barrage effect")
	check(int(barrage_effect.shots) == 6, "Barrage fires six arrows")
	check(is_equal_approx(float(barrage_effect.damage_scale),0.5), "Barrage deals 50% per arrow")
	check(float(barrage_effect.spread_degrees) > 0.0, "Barrage has a horizontal spread")
	check(int(barrage.cues.size()) == 6, "Barrage has six release cues")
	check(is_equal_approx(AbilityRules.damage_for(barrage,rig),15.0), "Barrage arrows deal 15 from a 30-damage shortbow")
	check(barrage.has("bow_draw") and float(barrage.bow_draw[-1][1]) == 0.0, "Barrage ends with the string relaxed")
	var offsets := AbilityFx.shot_offsets(barrage,1)
	check(absf(offsets.x) > 0.001, "The barrage spread offsets the second shot")
	check(is_equal_approx(offsets.x,AbilityFx.shot_offsets(barrage,1).x), "The barrage spread is deterministic")
	var wide := AbilityFx.rotate_direction(Vector3.FORWARD,offsets.x,offsets.y)
	check(wide.dot(Vector3.FORWARD) < 0.999, "The spread rotates the shot direction")

	var fireball: Dictionary = AbilityRules.by_item("staff_fire",0)
	check(str(fireball.effect.projectile) == "fireball", "The ember staff launches a fireball")
	check(is_equal_approx(float(fireball.effect.radius),3.0), "The fireball blast radius is three metres")
	check(is_equal_approx(float(fireball.effect.damage_scale),1.6), "The fireball scales the staff damage")
	check(is_equal_approx(float(fireball.cues[0].at),0.5), "The fireball releases halfway through the cast")
	check(is_equal_approx(AbilityRules.damage_for(fireball,rig),80.0), "The fireball blast deals 80")
	var spin: Dictionary = AbilityRules.by_item("sword_great",0)
	check(float(spin.get("spin",0.0)) > 0.0, "The greatsword spin declares its turn")
	check(str(spin.effect.kind) == "melee_ring", "The greatsword spin is a ring")
	check(is_equal_approx(float(spin.effect.radius),2.9), "The spin reaches the greatsword radius")
	check(is_equal_approx(AbilityRules.damage_for(spin,rig),70.0), "The spin deals 70")
	var spear: Dictionary = AbilityRules.by_item("staff_bone",0)
	check(int(spear.effect.pierce) == 3, "The bone spear pierces three bodies")
	check(is_equal_approx(AbilityRules.damage_for(spear,rig),90.0), "The bone spear deals 90")

	var audio := Audio.new()
	root.add_child(audio)
	for definition: Dictionary in AbilityRules.ABILITIES:
		if str(definition.get("item","")).is_empty():
			continue
		check(audio.sounds.has(str(definition.sound)), "The %s sound exists" % definition.sound)

	# Radial damage: a spin hits front and back; an arc does not hit behind.
	var spinner := fighter(world,1,Vector3(0,0,-8))
	var front := fighter(world,2,Vector3(0,0,-10))
	var behind := fighter(world,3,Vector3(0,0,-6))
	equip(spinner.rig,"sword_great")
	spinner.combat.aim_point = spinner.global_position + Vector3(0,1,-5)
	await physics_frame
	await physics_frame
	spinner.combat.ability_strike(2.9,360.0,70.0,0.2,true,false)
	check(is_equal_approx(front.health,30.0), "The spin damages the body in front")
	check(is_equal_approx(behind.health,30.0), "The spin damages the body behind")
	check(front.combat.stagger_time > 0.0 and behind.combat.stagger_time > 0.0, "The spin staggers both victims")
	front.health = 100.0
	behind.health = 100.0
	front.combat.stagger_time = 0.0
	behind.combat.stagger_time = 0.0
	spinner.combat.ability_strike(2.9,90.0,30.0,0.0,false,false)
	check(is_equal_approx(front.health,70.0), "A frontal arc hits the front body")
	check(is_equal_approx(behind.health,100.0), "A frontal arc spares the body behind")
	# A raised shield absorbs the arc without health loss.
	front.health = 100.0
	front.combat.stagger_time = 0.0
	equip(front.rig,"sword_short","shield_buckler")
	front.set_block(true,Vector3(0,0,1))
	spinner.combat.ability_strike(2.9,90.0,30.0,0.0,false,false)
	check(is_equal_approx(front.health,100.0), "A raised shield blocks a skill arc")
	front.set_block(false,Vector3.ZERO)

	# Blast: only bodies inside the radius take the explosion damage.
	var near := fighter(world,4,Vector3(10,0,-8))
	var far := fighter(world,5,Vector3(14,0,-8))
	await physics_frame
	spinner.combat.ability_blast(Vector3(10,1,-8),3.0,80.0,0.0)
	check(is_equal_approx(near.health,20.0), "The blast damages a body inside its radius")
	check(is_equal_approx(far.health,100.0), "The blast spares a body outside its radius")

	# The spell projectile sweeps, detonates and reports its centre.
	var blast_world := Node3D.new()
	root.add_child(blast_world)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4,4,0.5)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0,2,-3)
	blast_world.add_child(wall)
	await physics_frame
	var spell := Spell.new()
	spell.kind = "fireball"
	blast_world.add_child(spell)
	var detonations: Array = []
	spell.detonated.connect(func(centre: Vector3, direction: Vector3): detonations.append(centre))
	spell.launch(Vector3(0,1.5,0),Vector3(0,-0.2,-1),22.0,80.0,[],1,true,Vector3.ZERO,3.0)
	for frame in 30:
		await physics_frame
	check(detonations.size() == 1, "The fireball detonates once on a world contact")
	check(detonations.size() > 0 and Vector3(detonations[0]).z < -2.6, "The fireball detonates at the wall")
	check(not is_instance_valid(spell) or spell.flying == false, "The fireball stops after detonating")

	# Planted cues: the staff release beat reaches the effect listener.
	var caster := fighter(world,6,Vector3(20,0,-8))
	equip(caster.rig,"staff_fire")
	caster.stamina = Stamina.MAX
	var cues: Array = []
	caster.ability.cue.connect(func(id: String, cue: String, index: int): cues.append([id,cue,index]))
	check(bool(caster.try_ability(0).get("ok",false)), "The ember staff casts")
	caster.ability.advance(0.51)
	check(cues.size() == 1 and str(cues[0][1]) == "cast", "The fireball release cue fires at 0.5 s")
	caster.ability.advance(1.0)

	# Effect helpers stay constructible in a live tree.
	var fx := Node3D.new()
	root.add_child(fx)
	AbilityFx.slash_arc(fx,caster.global_position,Vector3.FORWARD,2.0,120.0)
	AbilityFx.spin_dust(fx,caster.global_position,2.6)
	AbilityFx.ground_shockwave(fx,caster.global_position,2.8)
	AbilityFx.burst(fx,caster.global_position,AbilityFx.BONE,1.0)
	AbilityFx.explosion(fx,caster.global_position,3.0)
	check(fx.get_child_count() == 5, "Every ability effect builds its presentation node")

	# End-to-end frontier wiring: a spin cue damages a real mob, Barrage spawns
	# arrows, and the fireball's blast hurts a body at the impact.
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.8).timeout
	var forward: Vector3 = -game.archer.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var sentinel := Enemy.new()
	sentinel.kind = 1
	sentinel.player = game.player
	sentinel.safe_center = game.world.player_spawn
	sentinel.position = game.player.global_position + forward * 2.2 + Vector3(0, 0.1, 0)
	game.add_child(sentinel)
	sentinel.set_physics_process(false)
	sentinel.set_process(false)
	equip(game.archer, "sword_great")
	game._update_loadout()
	game.combat.set_aim(sentinel.get_aim_position())
	game.archer.aim_at(sentinel.get_aim_position())
	await physics_frame
	var health_before: float = sentinel.health
	var spin_outcome: Dictionary = game.ability.activate(0)
	check(bool(spin_outcome.get("ok", false)), "The frontier starts the greatsword spin")
	await create_timer(0.85).timeout
	check(sentinel.health < health_before, "The spin cue damages a frontier mob")
	check(is_equal_approx(health_before - sentinel.health, 70.0), "The spin lands its full 70 on an unarmored mob")
	sentinel.queue_free()
	await process_frame

	var wolf := Enemy.new()
	wolf.kind = 0
	wolf.player = game.player
	wolf.safe_center = game.world.player_spawn
	wolf.position = game.player.global_position + forward * 4.0 + Vector3(0, 0.1, 0)
	game.add_child(wolf)
	wolf.set_physics_process(false)
	wolf.set_process(false)
	equip(game.archer, "bow_short")
	game._update_loadout()
	game.ability.reset()
	game.combat.set_aim(wolf.get_aim_position())
	game.archer.aim_at(wolf.get_aim_position())
	await physics_frame
	var wolf_health: float = wolf.health
	var arrows_before: int = game.arrows.size()
	var barrage_outcome: Dictionary = game.ability.activate(0)
	check(bool(barrage_outcome.get("ok", false)), "The frontier starts Barrage")
	await create_timer(1.05).timeout
	check(game.arrows.size() >= arrows_before, "Barrage keeps spawning arrows")
	check(wolf.health < wolf_health, "A Barrage arrow damages the frontier wolf")
	wolf.queue_free()
	await process_frame

	var blast_target := Enemy.new()
	blast_target.kind = 1
	blast_target.player = game.player
	blast_target.safe_center = game.world.player_spawn
	blast_target.position = game.player.global_position + forward * 4.5 + Vector3(0, 0.1, 0)
	game.add_child(blast_target)
	blast_target.set_physics_process(false)
	blast_target.set_process(false)
	equip(game.archer, "staff_fire")
	game._update_loadout()
	game.ability.reset()
	game.combat.set_aim(blast_target.get_aim_position())
	game.archer.aim_at(blast_target.get_aim_position())
	await physics_frame
	var blast_before: float = blast_target.health
	var fire_outcome: Dictionary = game.ability.activate(0)
	check(bool(fire_outcome.get("ok", false)), "The frontier starts the fireball")
	await create_timer(1.15).timeout
	check(blast_target.health < blast_before, "The fireball blast damages a frontier mob")
	blast_target.queue_free()
	await process_frame

	# Piercing shot: one arrow damages two bodies in line and keeps flying.
	var pike_near := Enemy.new()
	pike_near.kind = 1
	pike_near.player = game.player
	pike_near.safe_center = game.world.player_spawn
	pike_near.position = game.player.global_position + forward * 4.0 + Vector3(0, 0.1, 0)
	game.add_child(pike_near)
	pike_near.set_physics_process(false)
	pike_near.set_process(false)
	var pike_far := Enemy.new()
	pike_far.kind = 1
	pike_far.player = game.player
	pike_far.safe_center = game.world.player_spawn
	pike_far.position = game.player.global_position + forward * 6.0 + Vector3(0, 0.1, 0)
	game.add_child(pike_far)
	pike_far.set_physics_process(false)
	pike_far.set_process(false)
	equip(game.archer, "bow_long")
	game._update_loadout()
	game.ability.reset()
	game.combat.set_aim(pike_far.get_aim_position())
	game.archer.aim_at(pike_far.get_aim_position())
	await physics_frame
	var pike_near_health: float = pike_near.health
	var pike_far_health: float = pike_far.health
	var pierce_outcome: Dictionary = game.ability.activate(0)
	check(bool(pierce_outcome.get("ok", false)), "The frontier starts the piercing shot")
	await create_timer(1.1).timeout
	check(pike_near.health < pike_near_health, "The piercing arrow damages the near body")
	check(pike_far.health < pike_far_health, "The piercing arrow continues into the far body")
	pike_near.queue_free()
	pike_far.queue_free()
	await process_frame

	# Bone spear: the spell projectile punches through two actor bodies.
	var spear_near := fighter(blast_world,7,Vector3(10,0.08,-2))
	var spear_far := fighter(blast_world,8,Vector3(10,0.08,-4))
	await physics_frame
	await physics_frame
	var bone_lance := Spell.new()
	bone_lance.kind = "bone_spear"
	blast_world.add_child(bone_lance)
	var spear_hits: Array = []
	bone_lance.impacted.connect(func(enemy_hit: bool, position: Vector3): spear_hits.append(position))
	bone_lance.launch(Vector3(10,1.4,0),Vector3(0,-0.05,-1),28.0,90.0,[],1|4,true,Vector3(10,1.4,0.5),0.0,3)
	for frame in 20:
		await physics_frame
	check(is_equal_approx(spear_near.health,10.0), "The bone spear impales the first body")
	check(is_equal_approx(spear_far.health,10.0), "The bone spear continues through the second body")
	check(spear_hits.size() >= 2, "The bone spear reports both pierced contacts")
	game.queue_free()
	await process_frame

	# Snapshot budget with the longest names and both cooldowns in flight.
	equip(probe.rig,"sword_arming","shield_kite")
	var long_name_snapshot: Dictionary = probe.snapshot()
	check(JSON.stringify(long_name_snapshot).to_utf8_buffer().size() < 1100, "The weapon snapshot stays under the MTU budget")

	print("WEAPON_ABILITIES_REGRESSION checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)


func _on_watchdog() -> void:
	push_error("Weapon abilities regression timed out")
	quit(1)
