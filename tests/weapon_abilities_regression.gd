extends SceneTree
## Item skills: every catalog weapon wakes into exactly one ability once it is
## anointed and grants nothing while plain, the two hand slots resolve from the
## held kit, effects carry the requested damage/spread, radial strikes and
## blasts damage the right bodies, and the planted effect cues, projectile and
## HUD work.

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
	["dagger_iron", 0, "backstab"],
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


## Dresses the rig. Both held pieces are anointed unless `anoint` is false: a
## stock weapon carries no skill, and this harness exercises the skills.
func equip(rig, main_id: String, off_id: String = "", anoint: bool = true) -> void:
	rig.apply_loadout(State.build_loadout(main_id,off_id,ARMOR,{},[main_id,off_id] if anoint else []))


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


## The frontier reads held physical keys, so a test must press them the way a
## player does rather than poking the controller.
func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


## Ticks one authoritative arena fighter the way the host loop does: a fresh
## movement intent every frame, then the seat's own step.
func drive_fighter(actor, frames: int, motion: Vector2 = Vector2.ZERO) -> void:
	for frame in frames:
		await physics_frame
		actor.move_direction = motion
		actor.run_requested = false
		actor.input_age = 0.0
		actor.step(1.0/60.0,[actor])


## Frontier skills fire down the live crosshair, so a test that wants a shot on
## a body points the camera at it exactly as a player would: the centre ray has
## to pass through the target. The camera orbits the focus, so solve the yaw and
## pitch from the resolved camera position and iterate until it settles.
func aim_camera_at(game, point: Vector3) -> void:
	for _attempt in 3:
		game._update_camera(1.0)
		var offset: Vector3 = point - game.camera.global_position
		game.camera_yaw = atan2(-offset.x,-offset.z)
		game.camera_pitch = atan2(-offset.y,Vector2(offset.x,offset.z).length())
	game._update_camera(1.0)
	game.update_crosshair_aim()


## The heading the archer currently faces, flattened.
func facing(game) -> Vector3:
	var forward: Vector3 = -game.archer.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3.FORWARD
	return forward.normalized()


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
		check(definition.has("move"), "%s declares whether the owner can walk" % item_id)
		check(not seen.has(expected), "%s has a unique id" % item_id)
		seen[expected] = true
		var icon: Texture2D = AbilityRules.icon_texture(expected)
		check(icon != null and icon.get_width() == 128, "%s icon loads at 128 px" % item_id)
		# Rig resolution: a legal hand pair must expose the same grant once the
		# piece is anointed, and nothing in that slot while it is plain.
		var main_id := item_id if slot == 0 else "sword_arming"
		var off_id := "" if slot == 0 else item_id
		equip(rig,main_id,off_id,false)
		check(AbilityRules.granted(rig)[slot].is_empty(), "The plain %s grants nothing from the rig" % item_id)
		if slot == 1:
			check(AbilityRules.granted(rig)[0].is_empty(), "A plain arming sword beside the shield grants nothing")
		equip(rig,main_id,off_id)
		var grants: Array = AbilityRules.granted(rig)
		check(str(grants[slot].get("id","")) == expected, "The anointed %s resolves its grant from the rig" % item_id)
		if slot == 1:
			check(str(grants[0].get("id","")) == "lunge_thrust", "A shield leaves the main-hand skill intact")
	# Every catalog weapon and shield, makeshift tier included: the skill the
	# catalog says a piece wakes into is the one its dressed rig grants from the
	# piece's hand, and the other hand stays empty. Shields are held beside a
	# plain arming sword; every other piece is held alone.
	var catalog_pieces := 0
	for catalog_id: String in State.ITEMS:
		var entry: Dictionary = State.ITEMS[catalog_id]
		if not ["1h","2h","bow","staff","shield"].has(str(entry.get("category",""))) \
				or not ["sword","dagger","bow","staff","shield"].has(str(entry.get("kind",""))):
			continue
		catalog_pieces += 1
		var hand := AbilityRules.hand_slot(entry)
		var skill: Dictionary = AbilityRules.skill_for(entry)
		check(not skill.is_empty(), "%s wakes into a skill" % catalog_id)
		check(hand == (1 if str(entry.category) == "shield" else 0), "%s looses its skill from its own hand" % catalog_id)
		var loadout: Dictionary = State.build_loadout(catalog_id if hand == 0 else "sword_arming",
			catalog_id if hand == 1 else "",ARMOR,{},[catalog_id])
		check(str(loadout.anointed["main" if hand == 0 else "off"]) == str(skill.get("id","")),
			"%s carries its skill onto the loadout" % catalog_id)
		rig.apply_loadout(loadout)
		var catalog_grants: Array = AbilityRules.granted(rig)
		check(str(catalog_grants[hand].get("id","")) == str(skill.get("id","")),
			"The anointed %s grants %s from the rig, got %s" % [catalog_id,skill.get("id",""),catalog_grants[hand].get("id","")])
		check(catalog_grants[1-hand].is_empty(), "The anointed %s leaves the other hand without a skill" % catalog_id)
	check(catalog_pieces >= WEAPONS.size(), "The catalog sweep covers every weapon and shield")
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
	var backstab: Dictionary = AbilityRules.by_item("dagger_iron",0)
	check(str(backstab.get("id","")) == "backstab", "The iron dagger grants Backstab")
	check(str(backstab.effect.kind) == "backstab", "Backstab owns its effect kind")
	check(is_equal_approx(float(backstab.effect.damage_scale),2.0), "Backstab doubles the dagger")
	check(is_equal_approx(AbilityRules.damage_for(backstab,rig),28.0), "Backstab deals 28 from a 14-damage dagger")
	check(is_equal_approx(float(backstab.get("travel_seconds",-1.0)),0.0), "Backstab does not travel")
	check(is_equal_approx(float(backstab.get("speed_scale",-1.0)),0.0), "Backstab carries no speed")
	check(is_equal_approx(float(backstab.get("duration",0.0)),0.9), "Backstab lasts 0.9 s")
	check(str(backstab.get("sound","")) == "backstab", "Backstab declares its own sound")
	check(str(backstab.get("animation","")) == "Dagger_Backstab", "Backstab names its authored clip")
	check(int(backstab.cues.size()) == 2, "Backstab has two cues")
	check(str(backstab.cues[0].cue) == "blink" and str(backstab.cues[1].cue) == "stab", "Backstab blinks then stabs")
	check(is_equal_approx(float(backstab.cues[0].at),0.20), "The blink lands at 0.2 s")
	check(is_equal_approx(float(backstab.cues[1].at),0.50), "The stab lands at 0.5 s")
	check(is_equal_approx(float(backstab.effect.radius),1.2), "Backstab reaches 1.2 m")
	check(is_equal_approx(float(backstab.effect.stagger),0.35), "Backstab staggers the victim")
	check(AbilityRules.by_id("dash_stab").is_empty(), "The old dash stab is gone")
	var lunge: Dictionary = AbilityRules.by_item("sword_arming",0)
	check(is_equal_approx(float(lunge.get("duration",0.0)),0.95), "Lunge lasts 0.95 s")
	check(is_equal_approx(float(lunge.get("travel_seconds",0.0)),0.24), "Lunge steps for 0.24 s")
	check(is_equal_approx(float(lunge.get("speed_scale",0.0)),4.05), "Lunge dashes at 405%")
	check(is_equal_approx(float(lunge.get("speed_scale",0.0)) * 5.5 * float(lunge.get("travel_seconds",0.0)),5.346),
		"The long lunge covers its authored 5.34 m")
	check(lunge.cues.size() == 2, "The lunge wakes the dash then thrusts")
	check(str(lunge.cues[0].cue) == "dash" and is_equal_approx(float(lunge.cues[0].at),0.0), "The lunge wakes at the takeoff")
	check(str(lunge.cues[1].cue) == "arc" and is_equal_approx(float(lunge.cues[1].at),0.42), "The lunge thrust lands at 0.42 s")
	check(bool(lunge.effect.get("path_damage",false)), "The lunge damages the lane it crosses")
	check(is_equal_approx(float(lunge.effect.get("path_radius",0.0)),1.35), "The lunge lane is 1.35 m wide")
	check(is_equal_approx(float(lunge.effect.get("path_arc_degrees",0.0)),170.0), "The lunge lane sweeps a wide front")
	check(is_equal_approx(float(lunge.effect.get("dash_distance",0.0)),5.34), "The lunge declares its dash distance")
	check(is_equal_approx(float(lunge.effect.damage_scale),1.8), "Lunge keeps its 1.8x damage")
	check(is_equal_approx(float(lunge.effect.arc_degrees),55.0), "Lunge keeps its narrow arc")
	check(is_equal_approx(float(lunge.effect.radius),2.45), "Lunge keeps its reach")
	check(is_equal_approx(AbilityRules.damage_for(lunge,rig),68.4), "The lunge hits for 68.4")
	var twin: Dictionary = AbilityRules.by_item("sword_short",0)
	check(is_equal_approx(float(twin.get("duration",0.0)),1.0), "Double slash lasts 1.0 s")
	check(twin.cues.size() == 2, "Double slash keeps both cuts")
	check(is_equal_approx(float(twin.cues[0].at),0.26) and is_equal_approx(float(twin.cues[1].at),0.52), "Double slash cuts at 0.26 and 0.52 s")
	# The buckler shove reads as a headbutt, and every travelling skill follows
	# the crosshair instead of the heading the key was pressed from.
	check(str(AbilityRules.by_item("shield_buckler",1).get("name","")) == "HEADBUTT", "The buckler skill is the headbutt")
	check(str(AbilityRules.by_id("shield_bash").get("name","")) == "HEADBUTT", "The headbutt keeps its slot id")
	for aimed_id in ["lunge_thrust","shield_bash","shield_charge"]:
		check(AbilityRules.follows_aim(AbilityRules.by_id(str(aimed_id))), "%s travels down the crosshair" % aimed_id)
	for planted_id in ["double_slash","spin_slash","shield_slam","barrage","fireball"]:
		check(not AbilityRules.follows_aim(AbilityRules.by_id(str(planted_id))), "%s is not an aim dash" % planted_id)
	for melee_id in ["double_slash","lunge_thrust","spin_slash","backstab","shield_bash","shield_charge","shield_slam"]:
		check(AbilityRules.is_melee(AbilityRules.by_id(str(melee_id))), "%s swings the equipped blade" % melee_id)
	for standing_id in ["double_slash","lunge_thrust","spin_slash","backstab","shield_bash","shield_charge","shield_slam","charge"]:
		check(AbilityRules.needs_standing(AbilityRules.by_id(str(standing_id))), "%s needs the standing stance" % standing_id)
	for cast_id in ["barrage","triple_volley","piercing_shot","fireball","bone_spear"]:
		check(not AbilityRules.needs_standing(AbilityRules.by_id(str(cast_id))), "%s may layer over a crouch" % cast_id)
	var reel: Dictionary = AbilityRules.by_item("sword_great",0)
	check(is_equal_approx(float(reel.get("duration",0.0)),0.3166667), "The spin lasts a third of its old time")
	check(is_equal_approx(float(reel.get("cooldown",0.0)),1.0), "The spin cools for 1.0 s")
	check(is_equal_approx(float(reel.get("spin",0.0)),1.0), "The spin keeps its full turn")
	check(reel.cues.size() == 2, "The spin winds then rings")
	check(str(reel.cues[0].cue) == "wind" and is_equal_approx(float(reel.cues[0].at),0.06), "The spin winds at 0.06 s")
	check(str(reel.cues[1].cue) == "ring" and is_equal_approx(float(reel.cues[1].at),0.16), "The spin rings at 0.16 s")
	# Feet: melee skills keep the walk; ranged casts and the committed charge
	# and backstab stay planted.
	for walking_id in ["double_slash","lunge_thrust","spin_slash","shield_bash","shield_charge","shield_slam"]:
		check(bool(AbilityRules.by_id(str(walking_id)).get("move",false)), "%s keeps the owner walking" % walking_id)
	for planted_id in ["barrage","triple_volley","piercing_shot","fireball","bone_spear","charge","backstab"]:
		check(not bool(AbilityRules.by_id(str(planted_id)).get("move",true)), "%s keeps the owner planted" % planted_id)

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

	# Feet, arena host: a melee skill keeps the walking intent and a bow cast
	# plants the fighter. Fighters never hard-collide with each other and the
	# seat mask only sees the world, so the travel measured here is pure walk.
	var motion_world := Node3D.new()
	root.add_child(motion_world)
	var ground_body := StaticBody3D.new()
	ground_body.collision_layer = 1
	ground_body.collision_mask = 0
	ground_body.position = Vector3(0,-0.5,0)
	var ground_collider := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(160,1,160)
	ground_collider.shape = ground_box
	ground_body.add_child(ground_collider)
	motion_world.add_child(ground_body)
	var walker := fighter(motion_world,20,Vector3.ZERO)
	var bowman := fighter(motion_world,21,Vector3(0,0,30))
	equip(walker.rig,"sword_short")
	equip(bowman.rig,"bow_short")
	await drive_fighter(walker,4)
	await drive_fighter(bowman,4)
	walker.combat.grounded = true
	bowman.combat.grounded = true
	var walk_start: Vector3 = walker.global_position
	check(bool(walker.try_ability(0).get("ok",false)), "A grounded fighter starts Double Slash")
	check(walker.ability.allows_movement(), "Double Slash lets the fighter walk")
	await drive_fighter(walker,24,Vector2(1,0))
	var walked: float = Vector2(walker.global_position.x-walk_start.x,
		walker.global_position.z-walk_start.z).length()
	check(walker.ability.active, "Double Slash still runs after 0.4 s")
	check(walked > 0.7, "A melee skill keeps the fighter walking")
	walker.ability.reset()
	await drive_fighter(walker,4)
	var plant_start: Vector3 = bowman.global_position
	check(bool(bowman.try_ability(0).get("ok",false)), "A grounded fighter starts Barrage")
	check(not bowman.ability.allows_movement(), "Barrage keeps the fighter planted")
	await drive_fighter(bowman,24,Vector2(1,0))
	var planted: float = Vector2(bowman.global_position.x-plant_start.x,
		bowman.global_position.z-plant_start.z).length()
	check(bowman.ability.active, "Barrage still runs after 0.4 s")
	check(planted < 0.05, "A bow skill keeps the fighter planted")
	bowman.ability.reset()
	await drive_fighter(bowman,4)

	# Lunge, arena host: the dash cuts every body in its lane exactly once and
	# the closing thrust cannot hit those bodies again.
	var lunger := fighter(motion_world,22,Vector3(0,0,10))
	var near_body := fighter(motion_world,23,Vector3(2,0,10))
	var far_body := fighter(motion_world,24,Vector3(4,0,10))
	equip(lunger.rig,"sword_arming")
	await drive_fighter(lunger,4)
	lunger.combat.grounded = true
	lunger.rig.global_rotation.y = atan2(-1.0,0.0)
	lunger.combat.set_aim(Vector3(60,1.2,10))
	var dash_start: Vector3 = lunger.global_position
	check(bool(lunger.try_ability(0).get("ok",false)), "The fighter starts the long lunge")
	await drive_fighter(lunger,18)
	var dashed: float = Vector2(lunger.global_position.x-dash_start.x,
		lunger.global_position.z-dash_start.z).length()
	check(lunger.ability.active, "The lunge still runs after the dash")
	check(dashed >= 3.5 and dashed < 7.0, "The lunge carries the fighter down its 5.34 m lane")
	check(is_equal_approx(near_body.health,31.6), "The lane cuts the near body once")
	check(is_equal_approx(far_body.health,31.6), "The lane cuts the far body once")
	await drive_fighter(lunger,20)
	check(is_equal_approx(near_body.health,31.6) and is_equal_approx(far_body.health,31.6),
		"The closing thrust does not hit the passed bodies again")
	lunger.ability.reset()
	await drive_fighter(lunger,4)

	# The dash follows the crosshair, not the heading the key was pressed from.
	lunger.rig.global_rotation.y = 0.0
	lunger.combat.grounded = true
	lunger.combat.set_aim(lunger.global_position+Vector3(-12.0,1.2,0.0))
	check(bool(lunger.try_ability(0).get("ok",false)), "The fighter starts an off-axis lunge")
	var dash: Vector3 = lunger.ability.direction
	check(dash.x < -0.995 and absf(dash.z) < 0.02, "The lunge dashes down the crosshair")
	check(absf(wrapf(lunger.rig.global_rotation.y-atan2(12.0,0.0),-PI,PI)) < deg_to_rad(5.0),
		"The lunge turns the body onto the crosshair")
	lunger.ability.reset()
	await drive_fighter(lunger,4)

	# A melee skill cancels a crouch and plays standing; the cast keeps the
	# crouch layer because its arms are solved separately.
	var slasher := fighter(motion_world,25,Vector3(-6,0,10))
	equip(slasher.rig,"sword_short")
	await drive_fighter(slasher,10)
	slasher.combat.grounded = true
	slasher.set_crouch(true)
	await drive_fighter(slasher,40)
	check(slasher.cover.crouch_requested and slasher.cover.crouch_amount > 0.9, "The fighter crouches first")
	check(bool(slasher.try_ability(0).get("ok",false)), "A melee skill starts from a crouch")
	check(not slasher.cover.crouch_requested and not slasher.cover.crouched, "The melee skill cancels the crouch")
	check(slasher.cover.crouch_amount < 0.001, "The stance snaps upright for the skill")
	check(slasher.rig._crouch_amount < 0.001, "The rig drops the crouch blend")
	check(slasher.rig.phase == "ABILITY" and slasher.rig.ability_clip == "Sword_Double_Slash",
		"The authored clip owns the standing pose")
	slasher.ability.reset()
	await drive_fighter(slasher,4)
	motion_world.queue_free()
	await process_frame

	# Effect helpers stay constructible in a live tree.
	var fx := Node3D.new()
	root.add_child(fx)
	AbilityFx.slash_arc(fx,caster.global_position,Vector3.FORWARD,2.0,120.0)
	AbilityFx.spin_dust(fx,caster.global_position,2.6)
	AbilityFx.ground_shockwave(fx,caster.global_position,2.8)
	AbilityFx.burst(fx,caster.global_position,AbilityFx.BONE,1.0)
	AbilityFx.explosion(fx,caster.global_position,3.0)
	check(fx.get_child_count() == 5, "Every ability effect builds its presentation node")
	# The cue-driven effects replace the static crescent for blades and shields.
	var cue_fx := Node3D.new()
	root.add_child(cue_fx)
	AbilityFx.blade_trail(cue_fx,caster.rig,0.24)
	check(cue_fx.get_child_count() == 1, "The blade trail rides the equipped blade")
	AbilityFx.spin_burst(cue_fx,caster.global_position,2.6)
	AbilityFx.shield_impact(cue_fx,caster.global_position + Vector3.UP*1.05,Vector3.FORWARD,1.7,true)
	AbilityFx.smoke_puff(cue_fx,caster.global_position,1.0,true)
	AbilityFx.backstab_flash(cue_fx,caster.global_position,Vector3.FORWARD)
	check(cue_fx.get_child_count() >= 5, "The spin burst, shield impact, smoke and backstab flash build their nodes")
	var blink: Node = cue_fx.get_node_or_null("AbilityBlinkBurst")
	check(blink != null and blink.get_child_count() >= 130,
		"The backstab blink builds five times the original 26 billboards")

	# End-to-end frontier wiring: a spin cue damages a real mob, Barrage spawns
	# arrows, and the fireball's blast hurts a body at the impact.
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.8).timeout
	var mob := Enemy.new()
	mob.kind = 0
	mob.player = game.player
	mob.safe_center = game.world.player_spawn
	mob.position = game.player.global_position + facing(game) * 2.2 + Vector3(0, 0.1, 0)
	game.add_child(mob)
	# The spin lands 70, well past a wolf's 38, so give this body room to take
	# the blow whole instead of letting the health clamp swallow the number.
	mob.max_health = 200.0
	mob.health = 200.0
	mob.set_physics_process(false)
	mob.set_process(false)
	equip(game.archer, "sword_great")
	game._update_loadout()
	game.combat.set_aim(mob.get_aim_position())
	game.archer.aim_at(mob.get_aim_position())
	await physics_frame
	var health_before: float = mob.health
	var spin_outcome: Dictionary = game.ability.activate(0)
	check(bool(spin_outcome.get("ok", false)), "The frontier starts the greatsword spin")
	await create_timer(0.45).timeout
	check(mob.health < health_before, "The spin cue damages a frontier mob")
	check(is_equal_approx(health_before - mob.health, 70.0), "The spin lands its full 70 on an unarmored mob")
	mob.queue_free()
	await process_frame

	var wolf := Enemy.new()
	wolf.kind = 0
	wolf.player = game.player
	wolf.safe_center = game.world.player_spawn
	wolf.position = game.player.global_position + facing(game) * 4.0 + Vector3(0, 0.1, 0)
	game.add_child(wolf)
	wolf.set_physics_process(false)
	wolf.set_process(false)
	equip(game.archer, "bow_short")
	game._update_loadout()
	game.ability.reset()
	aim_camera_at(game, wolf.get_aim_position())
	await physics_frame
	await physics_frame
	var wolf_health: float = wolf.health
	var arrows_before: int = game.arrows.size()
	game.activate_ability(0)
	check(game.ability.active, "The frontier starts Barrage")
	await create_timer(1.05).timeout
	check(game.arrows.size() >= arrows_before, "Barrage keeps spawning arrows")
	check(wolf.health < wolf_health, "A Barrage arrow damages the frontier wolf")
	wolf.queue_free()
	await process_frame

	# Off-axis: the body turns onto the crosshair, so a target ninety degrees
	# off the heading that began the skill still takes arrows. Turn the camera a
	# quarter turn, then stand the target on the centre ray itself instead of
	# trusting a solved aim: the crosshair has to really cover the body.
	equip(game.archer, "bow_short")
	game._update_loadout()
	game.ability.reset()
	var start_yaw: float = game.archer.global_rotation.y
	var flank_side: Vector3 = facing(game).cross(Vector3.UP).normalized()
	game.camera_yaw = atan2(-flank_side.x, -flank_side.z)
	game.camera_pitch = 0.0
	game._update_camera(1.0)
	var view_center: Vector2 = game.get_viewport().get_visible_rect().size * 0.5
	var ray_origin: Vector3 = game.camera.project_ray_origin(view_center)
	var ray_normal: Vector3 = game.camera.project_ray_normal(view_center)
	var flank := Enemy.new()
	flank.kind = 0
	flank.player = game.player
	flank.safe_center = game.world.player_spawn
	# The wolf capsule rises 0.95 m from its origin, so 0.475 m below the ray
	# centres the body on the crosshair. Its aim point sits at +0.68 m, leaving
	# 0.205 m of that metre the crosshair check allows.
	flank.position = ray_origin + ray_normal * 6.0 - Vector3(0.0, 0.475, 0.0)
	game.add_child(flank)
	flank.set_physics_process(false)
	flank.set_process(false)
	await physics_frame
	await physics_frame
	game.update_crosshair_aim()
	check(game.combat.aim_point.distance_to(flank.get_aim_position()) <= 1.0,
		"The off-axis body sits on the centre crosshair")
	var flank_health: float = flank.health
	game.activate_ability(0)
	check(game.ability.active, "The frontier starts an off-axis Barrage")
	await create_timer(0.6).timeout
	var live_aim: Vector3 = game.combat.aim_point
	var to_aim: Vector3 = live_aim - game.archer.global_position
	to_aim.y = 0.0
	var aim_yaw := atan2(-to_aim.x, -to_aim.z)
	var yaw_error := absf(wrapf(game.archer.global_rotation.y - aim_yaw, -PI, PI))
	check(absf(wrapf(start_yaw - aim_yaw, -PI, PI)) > deg_to_rad(60.0), "The off-axis body sits well away from the starting heading")
	check(yaw_error < deg_to_rad(10.0), "A bow skill turns the body onto the crosshair")
	check(flank.health < flank_health, "An off-axis arrow lands on the aimed target")
	await create_timer(0.6).timeout
	flank.queue_free()
	await process_frame

	var blast_target := Enemy.new()
	blast_target.kind = 0
	blast_target.player = game.player
	blast_target.safe_center = game.world.player_spawn
	blast_target.position = game.player.global_position + facing(game) * 4.5 + Vector3(0, 0.1, 0)
	game.add_child(blast_target)
	blast_target.set_physics_process(false)
	blast_target.set_process(false)
	equip(game.archer, "staff_fire")
	game._update_loadout()
	game.ability.reset()
	aim_camera_at(game, blast_target.get_aim_position())
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
	var pike_line: Vector3 = facing(game)
	var pike_near := Enemy.new()
	pike_near.kind = 0
	pike_near.player = game.player
	pike_near.safe_center = game.world.player_spawn
	pike_near.position = game.player.global_position + pike_line * 4.0 + Vector3(0, 0.1, 0)
	game.add_child(pike_near)
	pike_near.set_physics_process(false)
	pike_near.set_process(false)
	var pike_far := Enemy.new()
	pike_far.kind = 0
	pike_far.player = game.player
	pike_far.safe_center = game.world.player_spawn
	pike_far.position = game.player.global_position + pike_line * 6.0 + Vector3(0, 0.1, 0)
	game.add_child(pike_far)
	pike_far.set_physics_process(false)
	pike_far.set_process(false)
	equip(game.archer, "bow_long")
	game._update_loadout()
	game.ability.reset()
	# A wolf capsule tops out at 1.05 m, so a crosshair line over the far body
	# skims the near one's crown. Take the near wolf instead and let the shot
	# pierce through to the far wolf standing in the same line.
	aim_camera_at(game, pike_near.get_aim_position())
	game.combat.set_aim(pike_near.get_aim_position())
	game.archer.aim_at(pike_near.get_aim_position())
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

	# Backstab: the caster blinks behind the aimed body on the authority and the
	# stab spends twice the dagger damage on the back it is now facing.
	var stalked := Enemy.new()
	stalked.kind = 0
	stalked.player = game.player
	stalked.safe_center = game.world.player_spawn
	var stalk_line: Vector3 = facing(game)
	stalked.position = game.player.global_position + stalk_line * 2.5 + Vector3(0, 0.1, 0)
	game.add_child(stalked)
	# A wolf's 38 already covers the 28 the stab lands, but pin the body higher
	# still so no clamp can shorten the asserted number.
	stalked.max_health = 200.0
	stalked.health = 200.0
	stalked.set_physics_process(false)
	stalked.set_process(false)
	# Looking away: its back is toward the archer, which is where the blink fits.
	stalked.global_rotation.y = atan2(-stalk_line.x, -stalk_line.z)
	equip(game.archer, "dagger_iron")
	game._update_loadout()
	game.ability.reset()
	await physics_frame
	aim_camera_at(game, stalked.get_aim_position())
	game.combat.set_aim(stalked.get_aim_position())
	game.archer.aim_at(stalked.get_aim_position())
	await physics_frame
	await physics_frame
	var stalked_health: float = stalked.health
	game.activate_ability(0)
	check(game.ability.active and str(game.ability.active_id) == "backstab", "The frontier starts Backstab on an aimed body")
	await create_timer(1.0).timeout
	var behind_offset: Vector3 = game.player.global_position - stalked.global_position
	behind_offset.y = 0.0
	check(behind_offset.length() <= 1.1, "The caster blinks to the backstab distance")
	var stalked_forward: Vector3 = -stalked.global_basis.z
	stalked_forward.y = 0.0
	check(behind_offset.dot(stalked_forward.normalized()) < 0.0, "The caster lands behind the target")
	check(is_equal_approx(stalked_health - stalked.health, 28.0), "The stab lands 28 on an unarmored wolf")
	check(not game.ability.active, "Backstab finishes on its own clock")
	stalked.queue_free()
	await process_frame

	# Frontier feet: a held walk keeps going through a melee skill and stops
	# dead for a bow cast. The spawn is the one spot these tests know is open,
	# so the walk is measured from there with the camera back on its start yaw.
	game.ability.reset()
	game.stamina = Stamina.MAX
	equip(game.archer, "sword_short")
	game._update_loadout()
	key(KEY_W, false)
	game.player.global_position = game.world.player_spawn
	game.player.velocity = Vector3.ZERO
	game.camera_yaw = 0.22
	game.camera_pitch = 0.08
	await create_timer(0.2).timeout
	key(KEY_W, true)
	await create_timer(0.25).timeout
	var walk_anchor: Vector3 = game.player.global_position
	game.activate_ability(0)
	check(game.ability.active and str(game.ability.active_id) == "double_slash",
		"The frontier starts Double Slash while walking")
	check(game.ability.allows_movement(), "Double Slash allows frontier movement")
	await create_timer(0.4).timeout
	var melee_travel: float = Vector2(game.player.global_position.x-walk_anchor.x,
		game.player.global_position.z-walk_anchor.z).length()
	check(game.ability.active, "Double Slash still runs after 0.4 s")
	check(melee_travel > 0.5, "A melee skill keeps the frontier walk")
	key(KEY_W, false)
	game.ability.reset()
	await physics_frame

	equip(game.archer, "bow_short")
	game._update_loadout()
	game.ability.reset()
	game.stamina = Stamina.MAX
	await physics_frame
	key(KEY_W, true)
	await create_timer(0.25).timeout
	var plant_anchor: Vector3 = game.player.global_position
	game.activate_ability(0)
	check(game.ability.active and not game.ability.allows_movement(),
		"Barrage keeps the frontier ranger planted")
	await create_timer(0.4).timeout
	var planted_travel: float = Vector2(game.player.global_position.x-plant_anchor.x,
		game.player.global_position.z-plant_anchor.z).length()
	check(game.ability.active, "Barrage still runs after 0.4 s")
	check(planted_travel < 0.05, "A bow skill keeps the frontier ranger planted")
	key(KEY_W, false)
	game.ability.reset()
	await physics_frame

	# Frontier lunge: the dash passes a lane of bodies and cuts each exactly
	# once. Bodies stop blocking the lane (the skill cuts through them) while
	# terrain still does, so take the flattest heading around the spawn.
	game.ability.reset()
	game.stamina = Stamina.MAX
	equip(game.archer, "sword_arming")
	game._update_loadout()
	game.player.global_position = game.world.player_spawn
	game.player.velocity = Vector3.ZERO
	await create_timer(0.2).timeout
	var lane_start: Vector3 = game.player.global_position
	var lane: Vector3 = Vector3.FORWARD
	var flattest := INF
	for heading_step in 12:
		var heading: Vector3 = Basis(Vector3.UP,TAU*float(heading_step)/12.0) * Vector3.FORWARD
		var spread := 0.0
		for sample in 6:
			var probe_point: Vector3 = lane_start + heading * (float(sample+1) * 1.2)
			spread = maxf(spread,absf(game.world.terrain_height(probe_point.x,probe_point.z) - lane_start.y))
		if spread < flattest:
			flattest = spread
			lane = heading
	var lane_yaw := atan2(-lane.x,-lane.z)
	var lane_near := Enemy.new()
	lane_near.kind = 0
	lane_near.player = game.player
	lane_near.safe_center = game.world.player_spawn
	lane_near.position = lane_start + lane * 2.0 + Vector3(0, 0.1, 0)
	game.add_child(lane_near)
	# The lane cuts 68.4 from each body, past a wolf's 38, so both need room to
	# report the whole hit instead of clamping at zero.
	lane_near.max_health = 200.0
	lane_near.health = 200.0
	lane_near.set_physics_process(false)
	lane_near.set_process(false)
	var lane_far := Enemy.new()
	lane_far.kind = 0
	lane_far.player = game.player
	lane_far.safe_center = game.world.player_spawn
	lane_far.position = lane_start + lane * 4.0 + Vector3(0, 0.1, 0)
	game.add_child(lane_far)
	lane_far.max_health = 200.0
	lane_far.health = 200.0
	lane_far.set_physics_process(false)
	lane_far.set_process(false)
	await physics_frame
	game.camera_yaw = lane_yaw
	game.camera_pitch = 0.0
	game._update_camera(1.0)
	game.update_crosshair_aim()
	game.archer.global_rotation.y = lane_yaw
	game.player.collision_mask = 1
	var lane_before: Vector3 = game.player.global_position
	var lane_near_before: float = lane_near.health
	var lane_far_before: float = lane_far.health
	game.activate_ability(0)
	check(game.ability.active and str(game.ability.active_id) == "lunge_thrust",
		"The frontier starts the long lunge")
	await create_timer(0.3).timeout
	var lane_travel: float = Vector2(game.player.global_position.x-lane_before.x,
		game.player.global_position.z-lane_before.z).length()
	check(game.ability.active, "The lunge still runs after the dash")
	check(lane_travel >= 3.5, "The long lunge carries the ranger down its lane")
	check(is_equal_approx(lane_near_before - lane_near.health,68.4),
		"The pass-through cuts the near body once")
	check(is_equal_approx(lane_far_before - lane_far.health,68.4),
		"The pass-through cuts the far body once")
	await create_timer(0.7).timeout
	check(is_equal_approx(lane_near_before - lane_near.health,68.4)
		and is_equal_approx(lane_far_before - lane_far.health,68.4),
		"The closing thrust does not hit the passed bodies again")
	game.player.collision_mask = 1 | 2
	lane_near.queue_free()
	lane_far.queue_free()
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
