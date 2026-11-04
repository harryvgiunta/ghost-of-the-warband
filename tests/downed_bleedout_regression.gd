extends SceneTree
## GHOST OF THE WARBAND - the body on the ground: the prone drag pose, the blood
## it drips and the death the bleed clock finally deals it.
##
## Everything runs on real `ArenaActor` bodies in a real scene tree through the
## real damage funnels (`receive_melee` -> `take_damage`), because what is being
## tested is where the state lands and what the body does with it, not what a
## helper returns. The clock is advanced through `step()`, the same physics tick
## `possession_controller` hands a warband body, and the drip runs on real physics
## frames so a pulse that never fires fails here instead of passing quietly.

const Actor = preload("res://scripts/warband/warband_body.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")
const ArmorData = preload("res://scripts/armor_data.gd")

## A blow the victim did not land itself: `receive_melee` refuses `source == slot`.
const KILLER_SLOT := 7
## The drip's slowest pulse is 1.2 s of physics clock; ninety frames is one and a
## half seconds, so a body that is going to drip has done it.
const PULSE_FRAMES := 90

var failures := 0
var checks := 0
var scene: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("DOWNED_BLEEDOUT_FAIL  ",message)

func _frames(count: int) -> void:
	for frame in count:
		await physics_frame

func box(size: Vector3, center: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	scene.add_child(body)
	return body

## A live authoritative fighter. `slot` must be set before the node enters the
## tree: the rig's armour and the combat source id are bound in `_ready`.
func make_actor(slot: int, peer: int, bot: bool, point: Vector3):
	var body = Actor.new()
	body.slot = slot
	body.authoritative = true
	scene.add_child(body)
	body.configure(peer,"Bleeding %d" % slot,point)
	return body

## A melee blow from five metres along +x, the same funnel the fight uses.
func hit_from_plus_x(actor, amount: float) -> int:
	return actor.receive_melee(amount,KILLER_SLOT,
		actor.global_position + Vector3(5.0,0.0,0.0))

## The drip node the body carries, or null when it carries none.
func drip_of(actor):
	return actor.get_node_or_null("BleedDrip")

## The head the body threw, or null while it still wears it.
func severed_of(actor):
	if not is_instance_valid(actor) or not is_instance_valid(actor.rig):
		return null
	return actor.rig.find_child("SeveredHead", true, false)

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	box(Vector3(80,1,180),Vector3(0,-0.5,20))

	# --- the fall puts the rig on the floor ---------------------------------
	var fallen = make_actor(1,1,false,Vector3(0,0,0))
	check(not fallen.rig.is_downed_pose(),"A standing body is not in the prone pose")
	hit_from_plus_x(fallen,100.0)
	check(fallen.downed and fallen.alive,"The fixture is downed, not dead")
	check(fallen.health_state == Contracts.HealthState.DOWNED,"A downed body is DOWNED")
	check(fallen.rig.is_downed_pose(),"A downed body puts the rig in the prone drag pose")
	check(is_zero_approx(fallen.rig.blood_loss),"A body that just fell has not bled yet")
	check(fallen.rig.visible,"A downed body keeps its model")
	var drip = drip_of(fallen)
	check(drip != null,"A body carries its own drip")
	check(drip != null and drip.attached(),"The drip runs on the frame the body falls")

	# The drip's own numbers: the contract's span, a quickening rate and a rising
	# volume, all read from the one clock the body runs.
	check(is_zero_approx(DownedRules.bleed_fraction(0.0))
		and is_equal_approx(DownedRules.bleed_fraction(Contracts.DOWNED_BLEED_SECONDS),1.0),
		"The bleed fraction spans the contract's thirty seconds")
	check(is_equal_approx(DownedRules.bleed_fraction(15.0),0.5),
		"Half the clock is half the blood")
	check(DownedRules.drip_interval(1.0) < DownedRules.drip_interval(0.0),
		"The drip quickens as the bleed runs out")
	check(DownedRules.drip_volume(1.0) > DownedRules.drip_volume(0.0),
		"The last drips carry more blood than the first")
	check(is_equal_approx(DownedRules.drip_interval(0.0),1.2)
		and is_equal_approx(DownedRules.drip_interval(1.0),0.6),
		"The drip beats every 1.2 s at the fall and every 0.6 s at the death")

	# --- the drip actually marks the ground --------------------------------
	var field = BloodFx.field_for(fallen)
	check(field != null,"A downed body's blood finds the scene's blood field")
	var stains_before := 0 if field == null else int(field.surface_stain_count())
	await _frames(PULSE_FRAMES)
	check(field != null and int(field.surface_stain_count()) > stains_before,
		"The drip lays blood on the ground under the body")

	# --- the clock drives the body's own blood loss ------------------------
	for tick in 30:
		fallen.step(0.1,[fallen])
	await _frames(2)
	check(fallen.downed and fallen.alive,"3 s on the ground does not kill a downed body")
	check(absf(fallen.rig.blood_loss - 0.1) < 0.02,
		"The rig's blood loss advances with the bleed clock")

	# --- 29.5 s is still a body on the ground ------------------------------
	for tick in 265:
		fallen.step(0.1,[fallen])
	check(absf(fallen.downed_seconds - 29.5) < 0.01,"295 tenths of a second is 29.5 s")
	check(fallen.downed and fallen.alive and fallen.rig.is_downed_pose(),
		"29.5 s down is still a live body lying on the ground")
	check(drip != null and drip.attached(),"The drip is still running at 29.5 s")

	# --- and the clock runs out -------------------------------------------
	# The clock lands a hair either side of 30.0, so the loop stops on the frame
	# the body dies instead of stepping a corpse (whose respawn clock runs).
	var died := false
	for tick in 6:
		fallen.step(0.1,[fallen])
		if not fallen.alive:
			died = true
			break
	check(died,"30 s of bleeding kills the body with no further hit")
	check(not fallen.downed,"A bled out body is no longer downed")
	check(is_zero_approx(fallen.health),"A bled out body sits at zero health")
	check(fallen.health_state == Contracts.HealthState.DEAD,"A bled out body is DEAD")
	check(fallen.rig.is_downed_pose(),"a bled-out campaign body keeps the lie it fell in")
	check(is_equal_approx(fallen.rig.blood_loss,1.0),
		"and the pool is the corpse's: the rig reads full blood loss")
	check(drip != null and not drip.attached(),"The death stops the drip")
	check(not fallen.alive and fallen.health_state == Contracts.HealthState.DEAD,
		"A campaign death stays on the ground: there is no respawn clock")
	for tick in 10:
		fallen.step(0.1,[fallen])
	check(not fallen.alive and fallen.health_state == Contracts.HealthState.DEAD,
		"A dead body stays dead on the ticks that follow")

	# --- a revive clears everything instantly ------------------------------
	var rescued = make_actor(2,2,false,Vector3(0,0,10))
	hit_from_plus_x(rescued,100.0)
	var rescue_drip = drip_of(rescued)
	for tick in 200:
		rescued.step(0.1,[rescued])
	await _frames(2)
	check(absf(rescued.rig.blood_loss - 20.0/Contracts.DOWNED_BLEED_SECONDS) < 0.02,
		"20 s down reads two thirds of the bleed on the rig")
	check(rescued.downed and rescued.alive,"20 s is still a reviveable body")
	rescued.revive_from_downed()
	check(not rescued.downed and rescued.alive,"A revive stands the body up")
	check(rescued.health_state == Contracts.HealthState.ALIVE,"A revived body is ALIVE")
	check(is_equal_approx(rescued.health, rescued.max_health * Contracts.REVIVE_HEALTH_FRACTION),
		"A revive restores the contract's twentieth of max health (%.1f)" % rescued.health)
	check(not rescued.rig.is_downed_pose(),"The revive clears the prone pose")
	check(is_zero_approx(rescued.rig.blood_loss),"The revive zeroes the blood loss")
	check(rescue_drip != null and not rescue_drip.attached(),"The revive stops the drip")
	var revived_stains := int(field.surface_stain_count())
	await _frames(PULSE_FRAMES)
	check(int(field.surface_stain_count()) == revived_stains,
		"A revived body stops dripping at once")
	check(absf(rescued.rig.blood_loss) < 0.0001,
		"The blood loss stays zero after the revive")

	# --- a replica lies down and bleeds off the wire -----------------------
	# The snapshot carries no downed flag: a zero health body that is still alive
	# is the wire's own wording for DOWNED, and the pose and drip follow it.
	var wire_source = make_actor(3,3,false,Vector3(0,0,20))
	var replica = make_actor(4,4,false,Vector3(0,0,26))
	replica.authoritative = false
	var wire: Dictionary = wire_source.snapshot()
	wire["health"] = 0.0
	wire["alive"] = true
	replica.apply_snapshot(wire,1,[])
	check(replica.downed and replica.alive,"A replica reads a zero health living body as downed")
	check(replica.health_state == Contracts.HealthState.DOWNED,"The replica's health state is DOWNED")
	check(replica.rig.is_downed_pose(),"A replicated downed body lies on the ground too")
	var replica_drip = drip_of(replica)
	check(replica_drip != null and replica_drip.attached(),"A replicated downed body drips too")
	wire["health"] = 50.0
	replica.apply_snapshot(wire,2,[])
	check(not replica.downed and replica.health_state == Contracts.HealthState.ALIVE,
		"A replicated revive stands the body back up")
	check(not replica.rig.is_downed_pose(),"A replicated revive clears the prone pose")
	check(replica_drip != null and not replica_drip.attached(),"A replicated revive stops the drip")

	# --- an arrow in the head of a player: a stump for a corpse ------------
	# A campaign body never dies from a blow, so the head leaves on the *finisher*:
	# an arrow in the head of a body already on the ground, whatever it is wearing.
	var plated = make_actor(5,5,false,Vector3(0,0,30))
	plated.rig.set_armor(ArmorData.SET_IDS.find("plate"))
	await _frames(2)
	plated.note_arrow_headshot(Vector3(0,0,-40),5.0)
	plated.take_damage(5.0,KILLER_SLOT,true)
	await _frames(1)
	check(plated.alive and not plated.downed,
		"A headshot the plate turns into a normal hit leaves the body standing")
	check(severed_of(plated) == null,"and takes no head with it")
	plated.note_arrow_headshot(Vector3(0,0,-40),200.0)
	plated.take_damage(200.0,KILLER_SLOT,true)
	await _frames(1)
	check(plated.downed and plated.alive,
		"A killing headshot only puts a campaign body on the ground")
	check(severed_of(plated) == null,"A downed body still wears its head")
	plated.note_arrow_headshot(Vector3(0,0,-40),60.0)
	plated.take_damage(60.0,KILLER_SLOT,true)
	await _frames(1)
	check(not plated.alive,"The finisher kills the downed body")
	var piece = severed_of(plated)
	check(piece != null,"An arrow in the head of a downed body takes the head off")
	var plated_skeleton := plated.rig.find_child("Skeleton3D", true, false) as Skeleton3D
	var plated_head := plated_skeleton.find_bone("Head")
	check(plated_skeleton.get_bone_pose(plated_head).basis.get_scale().x < 0.05,
		"The corpse keeps a head bone with no volume left")
	if piece != null:
		var piece_mesh := piece.find_child("HeadPiece", true, false) as MeshInstance3D
		check(piece_mesh != null and piece_mesh.mesh != null
				and piece_mesh.mesh.get_surface_count() > 0,
			"The thrown head is a mesh of its own")
		var helmet_nodes: Array = plated.rig._armor_meshes["head"][
			ArmorData.SET_IDS.find("plate")]
		var helmet_material = (helmet_nodes[0] as MeshInstance3D).get_active_material(0)
		var carries := false
		if piece_mesh != null and piece_mesh.mesh != null:
			for surface in piece_mesh.mesh.get_surface_count():
				if piece_mesh.mesh.surface_get_material(surface) == helmet_material:
					carries = true
		check(carries,"The plate helm is part of the head that flew")
		await _frames(90)
		check((piece as Node3D).global_position.distance_to(plated.global_position) > 0.4,
			"The head is thrown clear of the corpse")
		check(not piece.is_physics_processing(),"and comes to a rest on the ground")

	# A body that bled out, and one finished with a blade, keep their heads.
	check(severed_of(fallen) == null,"A body that bleeds out keeps its head")
	var struck = make_actor(6,6,false,Vector3(0,0,40))
	hit_from_plus_x(struck,100.0)
	hit_from_plus_x(struck,10.0)
	await _frames(1)
	check(not struck.alive,"A melee finisher kills a downed body")
	check(severed_of(struck) == null,"A melee finisher takes no head")

	# The wire carries the flight, so a guest sees the same decapitation.
	var cut_source = make_actor(7,7,false,Vector3(0,0,50))
	var cut_replica = make_actor(8,8,false,Vector3(0,0,56))
	cut_replica.authoritative = false
	var death_wire: Dictionary = cut_source.snapshot()
	death_wire["health"] = 0.0
	death_wire["alive"] = false
	death_wire["sever"] = Vector4(0.0,0.0,-40.0,1.0)
	cut_replica.apply_snapshot(death_wire,3,[])
	await _frames(1)
	check(severed_of(cut_replica) != null,
		"A replica throws the head its death snapshot carries")
	check(severed_of(cut_source) == null,
		"A living body's snapshot carries no flight")

	if failures == 0:
		print("DOWNED_BLEEDOUT_OK %d" % checks)
	else:
		print("DOWNED_BLEEDOUT_FAILED %d of %d checks" % [failures,checks])
	quit(0 if failures == 0 else 1)
