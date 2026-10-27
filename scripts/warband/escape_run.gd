extends Node3D
## GHOST OF THE WARBAND: the trail through the wood, from the camp to the town.
##
## The trail is the middle of one continuous world and has no doors of its own.
## It begins at the camp clearing's mouth - the lane's first waypoint *is* that
## mouth, so there is no seam and no wall between them - and it ends where the
## town's gate stands. Walking it is the only way between the two, and walking it
## is dangerous: two armed cultists start on the soul's own body and a pair waits
## in each clearing, so the escape is a running fight the whole way.
##
## The lane and every prop on it are `run_forest.gd`'s, built out of the world's
## own art kits; the bodies, the camera, the HUD, the loot vacuum and the squad
## are the world's. This node owns the lane's *occupants*: the eight cultists, the
## weapons they drop, and the lane's own numbers for whoever asks.
##
## There is no scene request here and no wipe beat. In the one world a wipe is not
## a hand-off to somewhere else - it is eight bodies lying in the mud and the
## roster left exactly as it fell, which the world records.

const RunForestScript = preload("res://scripts/warband/run_forest.gd")
const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")

## What each cultist carries, in spawn order. Every one of them drops it.
const CULTIST_ARMS := [
	"sword_arming", "dagger_iron", "sword_short", "sword_short",
	"dagger_iron", "sword_arming", "sword_short", "dagger_iron",
]
## The cultists' damage source id, so a blow is booked against the wood and never
## against a squadmate's slot.
const WATCHER_SOURCE := 91

## The world scene that embeds this trail. Required: the trail has no standalone
## scene, because the trail with no camp at one end and no town at the other is
## not a place, it is a corridor.
var host: Node3D = null

## The lane: `{root, lane, length, width, torches, clearings, arch, path,
## pursuer_posts, clearing_posts, stats}`. Every number the world and the
## regression read comes from here.
var forest: Dictionary = {}
## The road's own cultists. `host.guards` is the world's single hostile list.
var guards: Array = []

var _kills := 0
## True once the road has been put on the squad's heels (`wake_road`).
var _woken := false


## Build the lane under this node and put the cult on it. `options` is handed
## straight to `run_forest.gd`: the offset that moves the lane to the clearing's
## mouth, and the two ends left open.
func attach(world: Node3D, options: Dictionary = {}) -> void:
	host = world
	forest = RunForestScript.build(self, options)
	_build_cultists()


## The point the town gate stands at, which is the lane's far end.
func town_gate() -> Vector3:
	return forest.get("arch", Vector3.ZERO)


## Flat metres from a point to the town gate: what the world's prompt counts down.
func metres_to_town(point: Vector3) -> float:
	return _flat(point, town_gate())


func cultist_count() -> int:
	return guards.size()


func cultists_alive() -> int:
	var alive := 0
	for watcher in guards:
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			alive += 1
	return alive


func cultist_kills() -> int:
	return _kills


## Weapons of the road's that are still lying on it.
func pickups_left() -> int:
	var left := 0
	for pickup in host.pickups:
		if is_instance_valid(pickup) and not bool(pickup.collected):
			left += 1
	return left


# --- the cult on the road --------------------------------------------------

## Ten times the road's first eight: ten cultists at each of the eight posts,
## ringed so the trail is thick with the cult from the mouth to the town. They all
## hunt, they all drop what they carry.
const ROAD_PER_POST := 10

## Two behind the squad at the mouth of the lane and a pair in each clearing: one
## ring per post, all armed. Nobody is handed a quarry here - a cultist that
## started hunting from its spawn point would run the 90 m back into the camp and
## turn the opening's own fight into a massacre. The road answers the leaving
## (`wake_road`), and after that the wood's own senses do the noticing.
func _build_cultists() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7717
	for post in forest.get("pursuer_posts", []) as Array:
		_spawn_ring(post as Vector3, rng)
	for post in forest.get("clearing_posts", []) as Array:
		_spawn_ring(post as Vector3, rng)


## A post's worth of cult, packed around the post but inside the walkable band:
## the ring never reaches past the lane's walls, so nobody spawns inside a trunk.
func _spawn_ring(at: Vector3, rng: RandomNumberGenerator) -> void:
	for index in ROAD_PER_POST:
		var angle := TAU * float(index) / float(ROAD_PER_POST)
		var radius := rng.randf_range(1.0, 3.2)
		var point := at + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		_spawn_cultist(point)


func _spawn_cultist(at: Vector3) -> void:
	var watcher := WatcherScript.new()
	watcher.name = "RoadWatcher%d" % (guards.size() + 1)
	watcher.mob_id = "hollow_warden"
	add_child(watcher)
	watcher.global_position = at
	# The town end of the lane is safe ground: a cultist never hunts a body that
	# has already reached the gate.
	watcher.safe_center = town_gate()
	watcher.defeated.connect(_on_cultist_defeated)
	watcher.attacked.connect(_on_cultist_attack)
	watcher.arm(str(CULTIST_ARMS[guards.size() % CULTIST_ARMS.size()]))
	guards.append(watcher)
	host.guards.append(watcher)


## The road answers the leaving: the moment the squad steps out of the clearing a
## third of every ring takes the soul and comes up the lane after it, and the rest
## have to notice the squad by sight - which is what makes the trail feel hunted
## rather than scripted. Called by the camp on ESCAPING; a campaign that starts in
## the town never calls it, and the road is then just a road with a cult on it.
func wake_road(prey) -> void:
	if _woken or not is_instance_valid(prey):
		return
	_woken = true
	for index in guards.size():
		if index % 3 != 0:
			continue
		var watcher = guards[index]
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			watcher.hunt(prey)


## Each one drops the weapon it held, exactly as the camp's watchers do.
func _on_cultist_defeated(enemy, _reward: int) -> void:
	_kills += 1
	if is_instance_valid(enemy) and enemy.has_method("take_weapon_item"):
		var item_id := str(enemy.take_weapon_item())
		if not item_id.is_empty():
			host.spawn_pickup(item_id, enemy.global_position + Vector3(0.3, 0.0, 0.2))
	if host.hud != null and not guards.is_empty():
		host.hud.set_status("A cultist falls on the trail (%d of %d)." % [_kills, guards.size()], 2.0)


## A watcher's swing lands on the warband body it was hunting. The mob emits the
## blow; the scene applies it through the body's own guard, like every scene.
func _on_cultist_attack(attacker, amount: float, victim) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(victim):
		return
	if victim.has_method("receive_melee"):
		victim.receive_melee(amount, WATCHER_SOURCE, attacker.global_position)
	elif victim.has_method("take_damage"):
		victim.take_damage(amount, WATCHER_SOURCE)


func _flat(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()
