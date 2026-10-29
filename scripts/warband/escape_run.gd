extends Node3D
## GHOST OF THE WARBAND: the trail through the wood, from the camp to the town.
##
## The trail is the middle of one continuous world and has no doors of its own.
## It begins a long run of ordinary wood past the camp's mouth - the lane's first
## waypoint is `cage_escape.gd`'s `CAMP_TO_ROAD_METRES` away from it, and the camp
## plants the wood between the two - and it ends where the town's gate stands.
## Walking it is the only way between the two, and walking it is dangerous: two
## armed cultists start on the soul's own body and a pair waits in each clearing,
## so the escape is a running fight the whole way.
##
## The lane and every prop on it are `run_forest.gd`'s, built out of the world's
## own art kits; the bodies, the camera, the HUD, the loot vacuum and the squad
## are the world's. This node owns the lane's *occupants*: the twenty cultists, the
## weapons and rags they carry, the corpses they leave, and the lane's own numbers
## for whoever asks.
##
## There is no scene request here and no wipe beat. In the one world a wipe is not
## a hand-off to somewhere else - it is every body lying in the mud and the
## roster left exactly as it fell, which the world records.

const RunForestScript = preload("res://scripts/warband/run_forest.gd")
const TerrainScript = preload("res://scripts/warband/terrain.gd")
const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const CombatScript = preload("res://scripts/combat.gd")
const SfxScript = preload("res://scripts/audio/sfx.gd")

## What each cultist carries, in spawn order. Every one of them drops it.
## What a road cultist wears under its blade: cult rags the warband can take.
const CULTIST_RAGS := ["armor_makeshift_chest", "armor_leather_chest",
	"armor_mail_chest", "armor_cloth_chest"]
## The road's cultists carry the salvage tier, not forged steel: a road that hands
## every fanatic a smithed arming sword makes a mob into a knight, and a knight's
## blade off a murdered cultist is worth more than the whole camp put together.
const CULTIST_ARMS := [
	"club_makeshift", "dagger_ironwood", "branch_heavy", "club_makeshift",
	"dagger_ironwood", "club_makeshift", "branch_heavy", "dagger_ironwood",
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


# --- the cult on the road --------------------------------------------------

## Two cultists at each post, posts a long way apart. A nine-hundred-metre road
## does not need a crowd at every metre: the ambush is the point, and twenty of them
## spread over that distance means every engagement is a small, spaced one. (Four
## a post was forty full ranger rigs in one scene - the single dearest thing in the
## world to simulate, for a road that reads the same with half of them.)
const ROAD_PER_POST := 2

## Two behind the squad at the head of the lane and a pair in each clearing: one
## ring per post, all armed. Nobody is handed a quarry here - a cultist that
## started hunting from its spawn point would run the whole wood back into the camp
## and turn the opening's own fight into a massacre. The road answers the leaving
## (`wake_road`), and after that the wood's own senses do the noticing.
func _build_cultists() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7717
	for post in forest.get("pursuer_posts", []) as Array:
		_spawn_ring(post as Vector3, rng)
	for post in forest.get("clearing_posts", []) as Array:
		_spawn_ring(post as Vector3, rng)


## A post's worth of cult, packed around the post inside the clear line: the ring
## stays within `RunForestScript.CLEAR_HALF`, which is the band the wood keeps free
## of trunks, so nobody spawns inside a tree. The post's own height is discarded -
## the ring is placed on the ground once, never on top of an already-grounded post.
func _spawn_ring(at: Vector3, rng: RandomNumberGenerator) -> void:
	var centre := Vector3(at.x, 0.0, at.z)
	for index in ROAD_PER_POST:
		var angle := TAU * float(index) / float(ROAD_PER_POST) + rng.randf_range(-0.4, 0.4)
		var radius := rng.randf_range(0.8, 2.2)
		var point := centre + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		_spawn_cultist(TerrainScript.grounded(point))


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
	# A rag on its back, so a corpse is worth crossing the road for.
	watcher.armor_items = [str(CULTIST_RAGS[guards.size() % CULTIST_RAGS.size()])]
	guards.append(watcher)
	host.guards.append(watcher)


## The road answers the leaving: the moment the squad steps out of the camp a third
## of every ring takes the soul and comes up the lane after it, and the rest have
## to notice the squad by sight - which is what makes the trail feel hunted rather
## than scripted. Called by the camp on ESCAPING - it is the ambush, not the start
## of the road, which has been lying there a hundred and seventy metres away the
## whole time. A campaign that starts in the town never calls it, and the road is
## then just a road with a cult on it.
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


## The body stays on the trail as a lootable corpse - registered with the vacuum,
## which reads the blade and the rag off the enemy as it fell. Nothing is dumped on
## the ground as well, and nothing is taken out of its hand: the corpse screen
## lists what the body was carrying.
func _on_cultist_defeated(enemy, _reward: int) -> void:
	_kills += 1
	# The blade it was swinging falls out of its hand and lies where a body can
	# take it: the trail's cultists feed the squad's arming and the player's K.
	if is_instance_valid(enemy) and host != null:
		if host.has_method("drop_held_weapon"):
			host.drop_held_weapon(enemy)
		if host.loot != null and host.loot.has_method("register_corpse"):
			host.loot.register_corpse(enemy)
	if host.hud != null and not guards.is_empty():
		host.hud.set_status("A cultist falls on the trail (%d of %d)." % [_kills, guards.size()], 2.0)


## A watcher's swing lands on the warband body it was hunting. The mob emits the
## blow; the scene applies it through the body's own guard, like every scene.
func _on_cultist_attack(attacker, amount: float, victim) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(victim):
		return
	var outcome := -1
	if victim.has_method("receive_melee"):
		outcome = int(victim.receive_melee(amount, WATCHER_SOURCE, attacker.global_position))
	elif victim.has_method("take_damage"):
		victim.take_damage(amount, WATCHER_SOURCE)
		outcome = CombatScript.DEFENSE_NONE
	if outcome == CombatScript.DEFENSE_NONE:
		SfxScript.landed(attacker, victim.global_position + Vector3.UP)
	elif outcome > CombatScript.DEFENSE_NONE:
		SfxScript.defense(attacker.global_position,
			outcome == CombatScript.DEFENSE_PARRY)


func _flat(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()
