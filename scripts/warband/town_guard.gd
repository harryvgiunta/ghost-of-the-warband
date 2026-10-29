class_name TownGuard
extends Node3D
## One archer of the town watch, standing a post at the stockade gate.
##
## The town has no fight of its own - the square's bodies are fixtures - but the
## road in is the one place a hostile can walk up to the wall, and a settlement
## with a gate and no watch is a painted gate. So this is the smallest thing that
## answers it: a real `Archer` on a post, a real `arrow.gd` shaft on the mob
## layer, and no state of its own beyond a clock. A guard never moves, never
## chases, never speaks and never leaves the post it was given; if the wood gets
## past the treeline, the watch shoots it through the gap in the stakes.
##
## Where it looks is the host's business. Embedded, the town asks the world for
## its hostile list (`host.guards`); a town standing alone in its own preview has
## no world, so the pack is whatever is in the wilderness group. Either way the
## guard only ever reads it - the mobs belong to the world's own simulation.

const Archer = preload("res://scripts/archer.gd")
const State = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const WarbandLooks = preload("res://scripts/warband/warband_looks.gd")
const ArrowScript = preload("res://scripts/arrow.gd")
const CombatScript = preload("res://scripts/combat.gd")
const Senses = preload("res://scripts/mob_senses.gd")
const TerrainScript = preload("res://scripts/warband/terrain.gd")

## How often the post is asked whether anything is worth shooting. The same clock
## the town uses for the gold arrow: a mob's death is not a signal either.
const POLL := 0.35
## The draw a player can see and read as a bow coming up, then the shaft.
const DRAW_SECONDS := 0.9
const COOLDOWN := 1.6
## How far past its own feet a post will engage.
const REACH := 26.0
## Arrows are quick and flat: this is the world's own bow speed scale, and the
## shaft keeps the world's gravity, so a shot at this range is a straight line.
const SPEED := 46.0
## Full draw: the bow's own charge table decides the number.
const CHARGE := 1.0
## The mob collision layer. A watch arrow is for the things in the wood, not for
## the stakes it is shot over.
const HIT_MASK := 2
## The watch's look id, clear of the band's and of the keepers'.
const LOOK_SEED := 613
## The bow a watchman is handed: the oldest weapon in the setting, so the watch
## reads as part of the town and not as a squad of mercenaries.
const BOW := "bow_twig"

## Where the bow is when it lets go, in the guard's own frame (it faces -Z).
const MUZZLE := Vector3(0.10, 1.42, -0.36)

## The post, in world space, and the body standing on it.
var post := Vector3.ZERO
var rig = null
## How many shafts this post has actually let go. The regression reads it; the
## town never does.
var shots := 0

var _host: Node3D = null
var _poll := 0.0
var _draw := 0.0
var _cooldown := 0.0
var _target: Node3D = null
var _ray := PhysicsRayQueryParameters3D.new()


## Take the post. `host` is the world that owns the hostiles, or null for a town
## standing in its own scene; `at` is the post in the town's own space and carries
## its own height, so a post can be raised onto the gate frame when the field
## under it is not the ground the body stands on. Call it after the guard is in
## the tree: the body is dressed here and the post is measured on the field the
## town stands on.
func setup(host_or_null, at: Vector3, yaw: float) -> void:
	_host = host_or_null
	position = at
	rotation.y = yaw
	_ray.collision_mask = 1
	_ray.collide_with_areas = false
	rig = Archer.new()
	rig.name = "WatchBody"
	rig.appearance = WarbandLooks.profile_for(LOOK_SEED)
	add_child(rig)
	var set_index := ArmorData.SET_IDS.find("leather")
	var pieces := {}
	for slot in ArmorData.SLOTS:
		pieces[slot] = set_index if set_index >= 0 else ArmorData.NONE
	rig.apply_loadout(State.build_loadout(BOW, "", pieces))
	rig.set_weapon("bow")
	# The wall line is the field's own ground, not the flat pad the square sits
	# on: a post on the shoulder of the gate follows the slope it was built on.
	if _host != null:
		position.y += TerrainScript.height_at(global_position.x, global_position.z)
	post = global_position


func _physics_process(delta: float) -> void:
	if rig == null:
		return
	if _cooldown > 0.0:
		_cooldown = maxf(_cooldown - delta, 0.0)
	if _draw > 0.0:
		_draw -= delta
		if _draw <= 0.0:
			_release()
		return
	if _cooldown > 0.0:
		return
	_poll += delta
	if _poll < POLL:
		return
	_poll = 0.0
	var target := _nearest_hostile()
	if target == null:
		return
	_target = target
	# The draw is the whole tell: the watch turns, the bow comes up, and a body
	# on the road has a second to be somewhere else.
	rig.aim_at(_aim_point(target))
	rig.set_weapon("bow")
	rig.begin_draw()
	_draw = DRAW_SECONDS


## The post's own list of things to shoot, untouched.
func _hostiles() -> Array:
	if _host != null:
		var owned: Variant = _host.get("guards")
		return owned if owned is Array else []
	return get_tree().get_nodes_in_group(Senses.GROUP)


func _nearest_hostile() -> Node3D:
	var best: Node3D = null
	var best_distance := REACH
	for entry in _hostiles():
		if not (entry is Node3D) or not is_instance_valid(entry):
			continue
		var body := entry as Node3D
		if not _alive(body):
			continue
		var distance := post.distance_to(body.global_position)
		if distance > best_distance:
			continue
		if not _clear_line(body):
			continue
		best = body
		best_distance = distance
	return best


## Whether a body says it is still standing. A node that carries no such flag is
## the world's own scenery, not a target.
static func _alive(body: Node) -> bool:
	var flag: Variant = body.get("alive")
	return flag == null or bool(flag)


## Whether the shaft would reach: one ray to the body's aim point against the
## solid world (layer 1) - the stakes, the gate, the halls. The bow does not
## shoot through its own wall.
func _clear_line(target: Node3D) -> bool:
	_ray.from = _muzzle()
	_ray.to = _aim_point(target)
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	return hit.is_empty()


func _release() -> void:
	var target := _target
	_target = null
	_cooldown = COOLDOWN
	if target == null or not is_instance_valid(target):
		rig.cancel_draw()
		return
	var muzzle := _muzzle()
	var aim := _aim_point(target)
	var direction := (aim - muzzle).normalized()
	var damage := float(CombatScript.damage_for(int(rig.bow_index), CHARGE, 1.0))
	var arrow := ArrowScript.new()
	arrow.shooter = self
	arrow.hit_mask = HIT_MASK
	arrow.authoritative_damage = true
	add_child(arrow)
	arrow.launch(muzzle, direction, SPEED, damage, [], Vector3.INF, 0)
	shots += 1
	# The draw is spent: the body comes back to its rest pose over the recover
	# the rig already owns, rather than staying bent at full draw forever.
	rig.cancel_draw()


## The bow's own hand, in world space. The guard faces -Z, so the muzzle is a
## step in front of its chest in its own frame.
func _muzzle() -> Vector3:
	return global_transform * MUZZLE


## Where a shaft is aimed: the body's own aim point when it has one (the mobs
## answer with the height their mass actually is), the chest otherwise.
func _aim_point(target: Node3D) -> Vector3:
	if target.has_method("aim_point"):
		return target.aim_point()
	return target.global_position + Vector3(0.0, 0.9, 0.0)
