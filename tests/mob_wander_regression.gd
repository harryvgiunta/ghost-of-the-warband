extends SceneTree
## Idle wandering and the pack concept: lone roamers keep to the patch they
## spawned in, packed species share one territory and move as one band, and a
## pack answers a blow together however far apart its members have strayed.

const DevilMob = preload("res://scripts/devil_mob.gd")
const MobSenses = preload("res://scripts/mob_senses.gd")
const MobWander = preload("res://scripts/mob_wander.gd")

const PACK_RADIUS := 14.0
const SETTLE_LIMIT := 4.2
const WANDER_WINDOW := 7.0

var world_root: Node3D
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("MOB_WANDER_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _frames(count: int) -> void:
	for frame in count:
		await physics_frame

func _wait(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await physics_frame

func run() -> void:
	world_root = Node3D.new()
	world_root.name = "WanderWorld"
	root.add_child(world_root)
	_build_floor()
	await _check_solitary_roam()
	await _check_pack_cohesion()
	await _check_species_never_merge()
	await _check_pack_alarm_out_of_earshot()
	await _check_return_to_patch()
	await _check_frontier_wiring()
	world_root.queue_free()
	await process_frame
	print("MOB_WANDER_REGRESSION checks=", checks, " failures=", failures)
	quit(1 if failures > 0 else 0)


## A species that does not pack walks its own disc: it rests for the settle
## window, then moves, and never leaves the patch it was given.
func _check_solitary_roam() -> void:
	var mob = _spawn("gargoyle", Vector3(0.0, 0.05, 0.0))
	MobWander.assign_all([mob], PACK_RADIUS)
	var wander = mob._wander
	check(wander.territory != null, "a placed mob owns a territory")
	check(wander.group == "", "a non-packing species has no pack group")
	check(is_equal_approx(wander.territory.radius, mob.wander_radius()),
		"a lone roamer's disc is its own roam radius")
	var start: Vector3 = mob.global_position
	await _frames(int(SETTLE_LIMIT * 0.5 * 60.0))
	check(mob.global_position.distance_to(start) < 0.2,
		"a freshly placed mob settles before it wanders")
	var travelled := 0.0
	var furthest := 0.0
	var last: Vector3 = mob.global_position
	var deadline := Time.get_ticks_msec() + int(WANDER_WINDOW * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		travelled += mob.global_position.distance_to(last)
		last = mob.global_position
		furthest = maxf(furthest, wander.distance_from_center(mob))
	check(travelled > 1.5, "a calm mob wanders instead of standing still (walked %.2f m)" % travelled)
	check(furthest <= wander.territory.radius + 1.2,
		"a roamer never leaves its patch (%.2f m of %.2f m)" % [furthest, wander.territory.radius])
	_clear(mob)


## Packed bodies that spawned together share one territory: one goal, ring
## slots around it, and the versioned group the alarm uses.
func _check_pack_cohesion() -> void:
	var pack := []
	for index in 3:
		pack.append(_spawn("spawn", Vector3(4.0 * float(index) - 4.0, 0.05, 30.0)))
	MobWander.assign_all(pack, PACK_RADIUS)
	var first = pack[0]
	check(first._wander.group != "", "packed bodies join a pack")
	var shared = true
	var slots := {}
	for mob in pack:
		if mob._wander.territory != first._wander.territory:
			shared = false
		slots[int(mob._wander.slot)] = true
		check(mob.is_in_group(first._wander.group), "every pack member carries the group")
	check(shared, "a pack shares one territory")
	check(slots.size() == 3, "pack members take separate ring slots")
	check(first._wander.territory.slots == 3, "the territory knows its pack size")
	var centroid_before := _centroid(pack)
	await _wait(WANDER_WINDOW)
	var centroid_after := _centroid(pack)
	var spread := 0.0
	var outside := 0
	for a in pack:
		for b in pack:
			if a != b:
				spread = maxf(spread, a.global_position.distance_to(b.global_position))
		if a._wander.outside(a):
			outside += 1
	check(centroid_before.distance_to(centroid_after) > 0.4,
		"a pack moves as one band (centroid drifted %.2f m)" %
			centroid_before.distance_to(centroid_after))
	check(spread < 12.0, "pack members stay together (widest gap %.2f m)" % spread)
	check(outside == 0, "the band stays inside its territory")
	var group_members := get_nodes_in_group(first._wander.group)
	check(group_members.size() == 3, "the pack group holds every member")
	_clear_pack(pack)


## A sentinel that spawned beside a band keeps its own post: proximity alone
## never merges it into the pack.
func _check_species_never_merge() -> void:
	var devils := []
	for index in 2:
		devils.append(_spawn("gargoyle", Vector3(6.0 * float(index), 0.05, -26.0)))
	var beast = _spawn("beast", Vector3(3.0, 0.05, -26.0))
	MobWander.assign_all(devils + [beast], PACK_RADIUS)
	check(devils[0]._wander.territory != devils[1]._wander.territory,
		"two sentinels never share a territory")
	check(devils[0]._wander.group == "" and devils[1]._wander.group == "",
		"a sentinel has no pack to answer")
	check(beast._wander.group == "", "a lone beast beside sentinels stays solo")
	_clear(devils[0])
	_clear(devils[1])
	_clear(beast)


## A blow on one member pulls the whole pack in, past the 12 m shout radius,
## while an unrelated mob out of earshot stays calm.
func _check_pack_alarm_out_of_earshot() -> void:
	var player = _player(Vector3(0.0, 0.0, -40.0))
	var pack := []
	for index in 3:
		pack.append(_spawn("hell_goat", Vector3(float(index) * 3.0, 0.05, 0.0), player))
	var stranger = _spawn("hell_goat", Vector3(0.0, 0.05, 60.0), player)
	MobWander.assign_all(pack + [stranger], PACK_RADIUS)
	check(pack[0]._wander.group == pack[2]._wander.group, "the three goats form one pack")
	check(stranger._wander.group == "", "the far goat roams alone")
	# Strand one member 40 m away: beyond the earshot cry, still in the pack.
	pack[2].global_position = Vector3(0.0, 0.05, 40.0)
	pack[2].home = pack[2].global_position
	var struck = pack[0]
	struck.note_attacker(player)
	struck.take_damage(6.0, 0)
	await _frames(4)
	check(bool(struck._senses.aggressive()), "the struck packmate turns on its attacker")
	check(bool(pack[1]._senses.aggressive()), "the near packmate joins from earshot")
	check(bool(pack[2]._senses.aggressive()),
		"the stranded packmate joins from across the field")
	check(pack[2]._senses.target == player, "the stranded packmate hunts the same ranger")
	check(not bool(stranger._senses.aggressive()), "an unrelated mob stays calm")
	_clear_pack(pack)
	_clear(stranger)
	_clear(player)


## Chased out of its patch, a calm body walks back inside it.
func _check_return_to_patch() -> void:
	var mob = _spawn("succubus", Vector3(0.0, 0.05, -60.0))
	MobWander.assign_all([mob], PACK_RADIUS)
	var wander = mob._wander
	mob.global_position = Vector3(0.0, 0.05, -78.0)
	mob.home = wander.territory.center
	check(wander.outside(mob), "a shove past the patch edge is noticed")
	var before: float = wander.distance_from_center(mob)
	await _wait(8.0)
	var after: float = wander.distance_from_center(mob)
	check(after < before - 3.0, "a displaced body walks back toward its patch (%.1f m to %.1f m)" % [before, after])
	check(after <= wander.territory.radius + 1.2, "and arrives inside the territory (%.1f m)" % after)
	_clear(mob)


## The frontier hands every wilderness body a patch at load: packs where the
## species packs, a private post where it does not.
func _check_frontier_wiring() -> void:
	var packed_scene := load("res://main.tscn") as PackedScene
	check(packed_scene != null, "main.tscn loads")
	if packed_scene == null:
		return
	state_reset()
	var frontier := packed_scene.instantiate()
	world_root.add_child(frontier)
	await process_frame
	await process_frame
	var mobs: Array = []
	for enemy in frontier.enemies:
		mobs.append(enemy)
	var missing := 0
	var packs := {}
	var solo_gargoyle := false
	var court_packs := 0
	var wild_nest := 0
	for mob in mobs:
		if not mob.has_method("wanders_packed"):
			missing += 1
			continue
		var wander = mob._wander
		if wander.territory == null:
			missing += 1
			continue
		if wander.group.is_empty():
			if str(mob.get("mob_id")) == "gargoyle" and \
					MobSenses.in_safe_ring(frontier.world.player_spawn, mob.global_position):
				solo_gargoyle = true
		else:
			packs[wander.group] = int(packs.get(wander.group, 0)) + 1
			if MobSenses.in_safe_ring(frontier.world.player_spawn, mob.global_position):
				court_packs += 1
			if str(mob.get("mob_id")) == "spawn":
				wild_nest = maxi(wild_nest, int(packs[wander.group]))
		var ring: Vector3 = frontier.world.player_spawn
		var inside := Vector2(wander.territory.center.x - ring.x,
			wander.territory.center.z - ring.z).length()
		if inside < MobSenses.SAFE_RING:
			check(wander.territory.radius <= MobSenses.SAFE_RING - inside,
				"a territory inside the safe ring stays inside it")
	check(missing == 0, "every wilderness body in the frontier owns a patch (%d missing)" % missing)
	check(not packs.is_empty(), "the frontier fields at least one pack")
	var largest := 0
	for group in packs:
		largest = maxi(largest, int(packs[group]))
	check(largest >= 2, "a pack holds more than one body (largest %d)" % largest)
	check(solo_gargoyle, "the court's sentinel keeps its own post")
	check(court_packs == 0, "bodies in the safe-ring court keep their own posts")
	check(wild_nest >= 3, "the devil nest in the eastern crossroads roams as one pack")
	frontier.queue_free()
	await process_frame


# --- helpers ---------------------------------------------------------------

func state_reset() -> void:
	var state = root.get_node_or_null("PlayerState")
	if state != null:
		state.reset(false)

func _centroid(mobs: Array) -> Vector3:
	var total := Vector3.ZERO
	for mob in mobs:
		total += mob.global_position
	return total / float(maxi(mobs.size(), 1))

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(shape)
	world_root.add_child(body)

func _spawn(mob_id: String, at: Vector3, player: Node3D = null):
	var mob = DevilMob.new()
	mob.mob_id = mob_id
	mob.position = at
	if player != null:
		mob.player = player
	mob.safe_center = Vector3(2000.0, 0.0, 2000.0)
	world_root.add_child(mob)
	return mob

func _player(at: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	body.position = at
	world_root.add_child(body)
	return body

func _clear(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()

func _clear_pack(mobs: Array) -> void:
	for mob in mobs:
		_clear(mob)
