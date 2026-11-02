extends SceneTree
## The garment measurement under body blood, on real watcher rigs.
##
## Measuring a body's cloth is the one cold cost a landed blow used to pay: eight
## watchers in one lunge lane measured eight bodies inside that frame. The
## measurement is now per *visible shell* - the cloth and armature a body wears -
## so a camp of seven identical watchers pays for one, and the profiles are
## rest-space numbers bound to each rig's own skeleton on the way out. This owns
## that share: identical bodies measure once, a measured body never measures
## again, a body that changes what it wears is measured again, and a rig with no
## armature still measures its own primitives.

const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const BloodSurface = preload("res://scripts/blood_surface.gd")

const BODIES := 6

var world: Node3D
var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("BLOOD_COST_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	world = Node3D.new()
	world.name = "BloodCostWorld"
	root.add_child(world)
	var mobs := _watchers()
	await _settle(12)
	_check_share(mobs)
	_check_rebind(mobs)
	_check_repeat(mobs)
	await _check_species(mobs)
	_check_invalidation(mobs)
	_check_primitives()
	world.queue_free()
	await process_frame
	print("BLOOD_COST_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


func _settle(frames: int) -> void:
	for _index in frames:
		await process_frame


## A camp of one species and one kit: the same cloth on the same armature.
func _watchers() -> Array:
	var mobs: Array = []
	for index in BODIES:
		var mob := WatcherScript.new()
		mob.name = "CostWatcher%d" % index
		mob.mob_id = WatcherScript.WARDEN_ID
		mob.health_pool = 5000.0
		mob.position = Vector3(float(index) * 1.4, 0.0, 0.0)
		world.add_child(mob)
		mobs.append(mob)
	return mobs


func _check_share(mobs: Array) -> void:
	var before := BloodSurface.measurements
	var bodies: Array = []
	for mob in mobs:
		bodies.append(BloodSurface.body_for(mob.blood_rig()))
	var spent := BloodSurface.measurements - before
	check(spent == 1, "%d identical bodies share one garment measurement (measured %d)"
		% [BODIES, spent])
	var measured := 0
	for body: Dictionary in bodies:
		if not (body.get("bones", {}) as Dictionary).is_empty():
			measured += 1
	check(measured == BODIES, "every body of the shell comes back measured (%d of %d)"
		% [measured, BODIES])


## A shell is one species' cloth: another species wearing a skin whose nodes carry
## the same names is a different shell, and must be measured on its own.
func _check_species(mobs: Array) -> void:
	var before := BloodSurface.measurements
	var other := WatcherScript.new()
	other.name = "CostStalker"
	other.mob_id = WatcherScript.SPECIES_IDS[1]
	other.health_pool = 5000.0
	other.position = Vector3(0.0, 0.0, 6.0)
	world.add_child(other)
	await _settle(6)
	var body: Dictionary = BloodSurface.body_for(other.blood_rig())
	check(not (body.get("bones", {}) as Dictionary).is_empty(),
		"the other species is measured too")
	var mine: Dictionary = BloodSurface.body_for(mobs[0].blood_rig())
	check(BloodSurface.measurements == before + 1,
		"a different species is its own shell (%d measurements)"
		% [BloodSurface.measurements - before])
	check(mine.bones.values()[0].skeleton != body.bones.values()[0].skeleton,
		"and its profiles are bound to its own armature, not the warden's")


## Rest-space profiles are safe to share only because each rig gets them bound to
## its own skeleton: a stain must ride the body that was hit.
func _check_rebind(mobs: Array) -> void:
	var skeletons := {}
	var bound := 0
	var carriers := 0
	for mob in mobs:
		var rig: Node3D = mob.blood_rig()
		var body: Dictionary = BloodSurface.body_for(rig)
		var armature := BloodSurface._find_skeleton(rig)
		for profile: Dictionary in (body.get("bones", {}) as Dictionary).values():
			carriers += 1
			if profile.get("skeleton") == armature:
				bound += 1
		skeletons[armature.get_instance_id()] = true
	check(carriers > 0, "a shell carries bone profiles (%d)" % carriers)
	check(bound == carriers,
		"every profile is bound to its own rig's skeleton (%d of %d)" % [bound, carriers])
	check(skeletons.size() == BODIES,
		"each body keeps its own armature, not a shared one (%d of %d)"
		% [skeletons.size(), BODIES])
	# A stain asked for on one body must land on that body's own bone.
	var first: Dictionary = BloodSurface.body_for(mobs[0].blood_rig())
	var last: Dictionary = BloodSurface.body_for(mobs[BODIES - 1].blood_rig())
	var first_carrier: Dictionary = first.bones.values()[0]
	var last_carrier: Dictionary = last.bones.values()[0]
	check(first_carrier.skeleton != last_carrier.skeleton,
		"two bodies of one shell do not share one armature")
	check(int(first_carrier.index) == int(last_carrier.index),
		"and they name the same bone of it (%d vs %d)"
		% [int(first_carrier.index), int(last_carrier.index)])


func _check_repeat(mobs: Array) -> void:
	var before := BloodSurface.measurements
	for _round in 3:
		for mob in mobs:
			BloodSurface.body_for(mob.blood_rig())
	check(BloodSurface.measurements == before,
		"a measured body is never measured again (%d new)"
		% [BloodSurface.measurements - before])


## What a body wears is what is measured: hiding a cloth surface is a different
## shell, so the profile is rebuilt instead of being reused off the old one.
func _check_invalidation(mobs: Array) -> void:
	var rig: Node3D = mobs[0].blood_rig()
	var cloth := _first_skinned(rig)
	check(cloth != null, "the watcher has a skinned cloth surface")
	if cloth == null:
		return
	var before := BloodSurface.measurements
	cloth.visible = false
	BloodSurface.body_for(rig)
	check(BloodSurface.measurements == before + 1,
		"a body whose cloth changed is measured again (%d new)"
		% [BloodSurface.measurements - before])
	cloth.visible = true
	BloodSurface.body_for(rig)
	check(BloodSurface.measurements == before + 1,
		"a shell already measured is reused, not measured again")


## A rig with no armature - a primitive-built body - has no shell to share and
## measures its own boxes.
func _check_primitives() -> void:
	var rig := Node3D.new()
	var patch := MeshInstance3D.new()
	patch.mesh = BoxMesh.new()
	patch.position = Vector3(0.0, 1.0, 0.0)
	rig.add_child(patch)
	world.add_child(rig)
	var body: Dictionary = BloodSurface.body_for(rig)
	check((body.get("bones", {}) as Dictionary).is_empty(),
		"a primitive rig has no bone profiles")
	check((body.get("primitives", []) as Array).size() == 1,
		"and measures its own box instead (%s)" % str(body.get("primitives", []).size()))
	var empty := BloodSurface.body_for(Node3D.new())
	check((empty.get("bones", {}) as Dictionary).is_empty()
			and (empty.get("primitives", []) as Array).is_empty(),
		"a rig with no visible mesh has nothing to paint")


func _first_skinned(rig: Node3D) -> MeshInstance3D:
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node != null and mesh_node.skin != null \
				and mesh_node.is_visible_in_tree():
			return mesh_node
	return null
