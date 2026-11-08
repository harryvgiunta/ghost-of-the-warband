extends Node3D
## GHOST OF THE WARBAND: the trail through the wood, from the camp to the town.
##
## The trail is the middle of one continuous world and has no doors of its own.
## It begins a long run of ordinary wood past the camp's mouth - the lane's first
## waypoint is `cage_escape.gd`'s `CAMP_TO_ROAD_METRES` away from it, and the camp
## plants the wood between the two - and it ends where the town's gate stands.
## Walking it is the only way between the two, and walking it is dangerous: the
## road is held by a **chain** - a small band every fifty-odd metres, all of them
## hollow runts with the makeshift tier in their hands and a disc to wander in
## (`CHAIN_*`, `RUNT_LOADS`) - plus two lone archers asleep in the tree rows, one
## watchman a post.
##
## The lane and every prop on it are `run_forest.gd`'s, built out of the world's
## own art kits; the bodies, the camera, the HUD, the loot vacuum and the squad
## are the world's. This node owns the lane's *occupants*: the cultists, the
## two groups of three hidden warden archers, the weapons and rags they carry, the
## corpses they leave, and the lane's own numbers for whoever asks.
##
## There is no scene request here and no wipe beat. In the one world a wipe is not
## a hand-off to somewhere else - it is every body lying in the mud and the
## roster left exactly as it fell, which the world records.

const RunForestScript = preload("res://scripts/warband/run_forest.gd")
const TerrainScript = preload("res://scripts/warband/terrain.gd")
const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const ArcherScript = preload("res://scripts/warband/watcher_archer.gd")
const CombatScript = preload("res://scripts/combat.gd")
const SfxScript = preload("res://scripts/audio/sfx.gd")
const Perf = preload("res://scripts/perf_probe.gd")
const MobWander = preload("res://scripts/mob_wander.gd")

## What a road cultist wears under its blade: a cult rag the warband can take. The
## trail is the first scenario and it pays in salvage - a makeshift chest and
## nothing above it - because a leather, cloth or mail rag off the first fanatic
## in reach outfits the squad before it has walked the lane's second torch.
const CULTIST_RAG := "armor_makeshift_chest"
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
## The name a road body is numbered under, by species: a guest builds the same
## lane in the same order, so the session's name-keyed snapshots land on it.
const NAME_PREFIX := {
	"hollow_warden": "RoadWatcher",
	"hollow_runt": "RoadRunt",
}
## A bow body's (or a lone archer's) name: it is fielded as `watcher_archer.gd`,
## which draws and looses, and it is never named as a blade.
const BOW_NAME := "RoadBow"

## **The chain.** The road is held by small bands a few dozen metres apart, not by
## four set-piece clearings every three hundred. The first band stands
## `CHAIN_FIRST` out of the town gate, the second `CHAIN_SECOND_STEP` beyond it,
## and every band after that is a seeded gap in `[CHAIN_GAP_MIN, CHAIN_GAP_MAX]`,
## so the wood reads as held ground instead of a long walk between stages.
const CHAIN_FIRST := 50.0
const CHAIN_SECOND_STEP := 75.0
const CHAIN_GAP_MIN := 55.0
const CHAIN_GAP_MAX := 115.0
const CHAIN_SEED := 6173
## How far short of the lane's dark end the chain stops: the last stretch is the
## Horned Thing's ground, and a running fight there would be the boss's fight.
const CHAIN_END := 170.0
## A ceiling on the walk. The gaps are drawn, so the loop is bounded by the lane;
## this is the belt to that brace - a bad `CHAIN_*` row must stop the build, never
## spin it.
const CHAIN_MAX_BANDS := 40
## The disc a band wanders in (`MobWander`): its bodies drift around their mark
## instead of standing to attention, so the wood moves and a squad can be met out
## on the road. Wide enough to read, narrow enough to stay a band.
const CHAIN_ROAM := 9.0
## How far either side of the lane's centre a band's bodies stand.
const CHAIN_SPREAD := [1.6, 2.8]
## One body a band for the town's end of the walk, two once the road is a third
## walked, and a full warden in front of its runt past `CHAIN_WARDEN_AFTER`.
const CHAIN_PAIR_AFTER := 0.34
const CHAIN_WARDEN_AFTER := 0.72
## What a runt of the chain is given, on the makeshift tier: a club, the
## makeshift cleaver, the ironwood shiv, a board and a club, a board and a
## cleaver, and the twig bow (which is fielded as an archer). `off` is the left
## hand; the rest is the right.
const RUNT_LOADS := [
	{"main": "club_makeshift", "off": ""},
	{"main": "sword_makeshift", "off": ""},
	{"main": "dagger_ironwood", "off": ""},
	{"main": "club_makeshift", "off": "shield_wood"},
	{"main": "sword_makeshift", "off": "shield_wood"},
	{"main": "bow_twig", "off": ""},
]

## The lone archers: **one body a group**, tucked into the near tree rows 5-9 m off
## the lane. A volley of three was three full 71-pool wardens at once with no blade
## to trade with, so each of the two posts now fields a single watchman - and that
## one fights like the arena's cloned ranger instead of standing in its trees
## (`WatcherArcher.elite`: a longer ring, a fresh spot after every shot, a break
## out of contact). It sleeps with no quarry until a live body comes within
## `AMBUSH_WAKE` of its trees.
const ARCHER_FRACTIONS := [0.30, 0.56]
## One a group: the group *is* the body, and the two groups are the two posts.
const ARCHER_COUNT := 2
## Off the lane: past the walkable band, inside the near tree rows.
const ARCHER_LATERAL := 7.4
const AMBUSH_WAKE := 21.0
const AMBUSH_POLL := 0.2
## Room a warden's body needs past a trunk's own bark at spawn.
const ARCHER_CLEAR := 0.85
## The same 12 cm every warband spawn is lifted by, so a body dropped on the
## analytic ground starts clear of its collider.
const SPAWN_LIFT := 0.12

## The world scene that embeds this trail. Required: the trail has no standalone
## scene, because the trail with no camp at one end and no town at the other is
## not a place, it is a corridor.
var host: Node3D = null

## The lane: `{root, lane, length, width, torches, clearings, arch, path,
## spawn_posts, trunks, stats}`. Every number the world and the regression read
## comes from here.
var forest: Dictionary = {}
## The road's own hostiles. `host.guards` is the world's single hostile list.
var guards: Array = []
## The road cultists proper, in spawn order: the archers are in `guards` too, but
## `wake_road` only ever hands a quarry to this many.
var cultists: Array = []
## The two hidden archer groups: `{anchor, archers, awake}`.
var ambushes: Array = []

var _kills := 0
## True once the road has been put on the squad's heels (`wake_road`).
var _woken := false
var _ambush_elapsed := 0.0
## False once every group has sprung; the poll then costs a branch.
var _ambush_hidden := true


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


## The blade cultists the road was built to hold - the road's garrison ledger. The
## archers are in `guards` too and are not counted here: they only ever spring.
func cultist_count() -> int:
	return cultists.size()


func cultists_alive() -> int:
	var alive := 0
	for watcher in guards:
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			alive += 1
	return alive


func cultist_kills() -> int:
	return _kills


## The ambush's only clock. Three hidden wardens do not each decide to wake: the
## group does, once, when the nearest standing body comes inside `AMBUSH_WAKE` of
## its trees - and then all three take that body at once. Two groups, polled five
## times a second, cost nothing at all.
func _process(delta: float) -> void:
	Perf.begin("trail")
	_poll_ambush(delta)
	Perf.end()


func _poll_ambush(delta: float) -> void:
	if not _ambush_hidden or host == null or ambushes.is_empty():
		return
	if host.get("_client") == true:
		# A guest sees the host's archers as snapshots; it never wakes them.
		return
	_ambush_elapsed += delta
	if _ambush_elapsed < AMBUSH_POLL:
		return
	_ambush_elapsed = 0.0
	var hidden := 0
	for group in ambushes:
		if bool(group.get("awake", false)):
			continue
		hidden += 1
		if not host.has_method("nearest_standing_body"):
			continue
		var anchor: Vector3 = group["anchor"]
		var prey = host.nearest_standing_body(anchor)
		if prey == null or not is_instance_valid(prey):
			continue
		if _flat(anchor, (prey as Node3D).global_position) > AMBUSH_WAKE:
			continue
		group["awake"] = true
		hidden -= 1
		for archer in group["archers"] as Array:
			if is_instance_valid(archer) and bool(archer.get("alive")):
				archer.begin_ambush(prey)
	_ambush_hidden = hidden > 0


## The two hidden groups, for the regression: `{anchor, archers, awake}` per
## `ARCHER_FRACTIONS` entry.
func archer_ambushes() -> Array:
	return ambushes.duplicate()


# --- the cult on the road --------------------------------------------------

## The road's garrison, off two tables: the chain (`CHAIN_*`, `RUNT_LOADS`), built
## out of the lane's own frames, and the two lone archers at `ARCHER_FRACTIONS`.
##
## Nobody is handed a quarry here - a cultist that started hunting from its spawn
## point would run the whole wood back into the party and turn the opening's own
## fight into a massacre. The road answers the leaving (`wake_road`), and after
## that the wood's own senses do the noticing.
func _build_cultists() -> void:
	_build_chain()
	# The archers come last: `wake_road` walks `cultists`, not `guards`, so the
	# leaving hands a quarry to the chain and never to the hidden watch.
	_build_ambushes()


## The chain: one band per gap, from `CHAIN_FIRST` metres off the town gate to
## `CHAIN_END` short of the lane's dark end. It is walked from the town's end
## (lane fraction 1.0) toward the wood, so the first band placed is the first one
## a party out of the gate meets.
func _build_chain() -> void:
	var path = forest.get("path")
	if path == null:
		return
	var total := float(path.total)
	var rng := RandomNumberGenerator.new()
	rng.seed = CHAIN_SEED
	var walked := CHAIN_FIRST
	var index := 0
	while walked < total - CHAIN_END and index < CHAIN_MAX_BANDS:
		var frame: Dictionary = path.sample(total - walked)
		_build_band(frame, index, rng, clampf(walked / maxf(total, 1.0), 0.0, 1.0))
		index += 1
		# Two written steps, not a ternary: `walked += a if c else b` is easy to
		# read as the assignment being the conditional, and a gap that never lands
		# is a build that never ends.
		if index == 1:
			walked += CHAIN_SECOND_STEP
		else:
			walked += rng.randf_range(CHAIN_GAP_MIN, CHAIN_GAP_MAX)


## One band: a single runt on the town's end of the walk, a pair past a third of
## it, and past `CHAIN_WARDEN_AFTER` a full warden in front of its runt. Every
## body is given a piece off `RUNT_LOADS`, and the band a disc to wander in, so the
## wood reads as held ground that moves instead of a line of posts.
func _build_band(frame: Dictionary, index: int, rng: RandomNumberGenerator,
		share: float) -> void:
	var centre: Vector3 = frame["position"]
	var right: Vector3 = frame["right"]
	var forward: Vector3 = frame["forward"]
	var size := 1 if share <= CHAIN_PAIR_AFTER else 2
	var led := share > CHAIN_WARDEN_AFTER
	var members: Array = []
	for slot in size:
		var species := WatcherScript.RUNT_ID
		var load := index + slot
		if led and slot == 0:
			species = WatcherScript.WARDEN_ID
			load = -1
		var side := 1.0 if (index + slot) % 2 == 0 else -1.0
		var offset := float(CHAIN_SPREAD[mini(slot, CHAIN_SPREAD.size() - 1)]) * side
		var at := TerrainScript.grounded(Vector3(centre.x + right.x * offset, 0.0,
			centre.z + right.z * offset))
		var spot := _clear_of_trees(Vector3(at.x, 0.0, at.z), right, forward) \
			+ Vector3(0.0, SPAWN_LIFT, 0.0)
		members.append(_spawn_cultist(spot, species, load))
	# One territory a band: bodies spawned inside `CHAIN_ROAM` of one another drift
	# around one shared goal instead of each walking its own way.
	MobWander.assign_all(members, CHAIN_ROAM)


## One of the two lone watchmen: a warden's body with a bow, asleep until a body
## comes inside `AMBUSH_WAKE` of its trees, and fighting like the arena's cloned
## ranger once it is up (`elite` - a longer ring, a fresh spot after every shot, a
## break out of contact). A group of three full wardens was three bodies of 71 pool
## at once with no blade to trade with; one watchman with a brain is the fight.
func _build_ambushes() -> void:
	var path = forest.get("path")
	if path == null:
		return
	for group_index in ARCHER_FRACTIONS.size():
		var side := -1.0 if group_index % 2 == 0 else 1.0
		var frame: Dictionary = path.sample(path.total * float(ARCHER_FRACTIONS[group_index]))
		var point := (frame["position"] as Vector3) \
			+ (frame["right"] as Vector3) * side * ARCHER_LATERAL
		var spot := _clear_of_trees(Vector3(point.x, 0.0, point.z),
			frame["right"] as Vector3, frame["forward"] as Vector3)
		var archer := _spawn_archer(spot)
		ambushes.append({"anchor": spot, "archers": [archer], "awake": false})


## One lone archer, standing in the near tree rows. Not in `cultists`: `wake_road`
## hands a quarry to the chain and the never-hidden, and this body is only ever
## sprung by a body coming close or by a blow.
func _spawn_archer(at: Vector3) -> Node:
	var archer := ArcherScript.new()
	archer.name = "WardenArcher%d" % (guards.size() + 1)
	archer.mob_id = WatcherScript.WARDEN_ID
	add_child(archer)
	archer.global_position = at
	archer.set_anchor(at)
	archer.host = host
	archer.elite = true
	# The town end of the lane is safe ground, exactly as it is for the chain:
	# nobody is hunted inside the gate's ring.
	archer.safe_center = town_gate()
	archer.defeated.connect(_on_cultist_defeated)
	archer.attacked.connect(_on_cultist_attack)
	# A rag and a quiver's worth of nothing: the corpse lists what it had.
	var rag: Array[String] = [CULTIST_RAG]
	archer.armor_items = rag
	guards.append(archer)
	host.guards.append(archer)
	return archer


## The first spot at or beside `point` where a warden's body clears every solid
## trunk. The wood keeps its trunk colliders in `forest["trunks"]`, so this is a
## geometry check rather than a physics query before the first frame.
func _clear_of_trees(point: Vector3, right: Vector3, forward: Vector3) -> Vector3:
	var trunks: Array = forest.get("trunks", [])
	if trunks.is_empty():
		return TerrainScript.grounded(Vector3(point.x, 0.0, point.z)) + Vector3(0.0, SPAWN_LIFT, 0.0)
	var candidates: Array[Vector3] = [Vector3.ZERO]
	for step in [0.9, 1.8, 2.7]:
		candidates.append(right * step)
		candidates.append(right * -step)
		candidates.append(forward * step)
		candidates.append(forward * -step)
	for offset in candidates:
		var at := point + offset
		var clear := true
		for trunk in trunks:
			var flat: Vector2 = trunk.get("at", Vector2.ZERO)
			var radius := float(trunk.get("radius", 0.0))
			if Vector2(at.x - flat.x, at.z - flat.y).length() < radius + ARCHER_CLEAR:
				clear = false
				break
		if clear:
			return TerrainScript.grounded(Vector3(at.x, 0.0, at.z)) + Vector3(0.0, SPAWN_LIFT, 0.0)
	return TerrainScript.grounded(Vector3(point.x, 0.0, point.z)) + Vector3(0.0, SPAWN_LIFT, 0.0)


## One body of the chain. A load whose right hand is a bow is fielded as
## `watcher_archer.gd` - it draws and looses, and it stands its watch in the open -
## and everything else is a watcher holding the pair of pieces the load names. A
## runt's pool, blow, build and guard share are the species' own
## (`cage_watcher.gd::_ready` and `_pick_variant`), so the caller only says which
## body stands there and what is in its hands.
func _spawn_cultist(at: Vector3, species: String, load_index: int = -1) -> Node:
	var load: Dictionary = {}
	if load_index >= 0:
		load = RUNT_LOADS[load_index % RUNT_LOADS.size()]
	var bow := str(load.get("main", "")) == ArcherScript.BOW_ITEM
	var watcher = ArcherScript.new() if bow else WatcherScript.new()
	# A typed row: the body's own field is `Array[String]`, and an untyped literal
	# assigned through a loosely-typed variable is refused at runtime.
	var rag: Array[String] = [CULTIST_RAG]
	watcher.name = "%s%d" % [BOW_NAME if bow else str(NAME_PREFIX.get(species,
		NAME_PREFIX[WatcherScript.WARDEN_ID])), guards.size() + 1]
	# Named, species'd and given its disc before the tree sees it: `_ready` picks
	# the variant, the pool, the build and the idle roam from these.
	watcher.mob_id = species
	watcher.patrol_radius = CHAIN_ROAM
	if bow:
		watcher.host = host
	add_child(watcher)
	watcher.global_position = at
	# The town end of the lane is safe ground: a cultist never hunts a body that
	# has already reached the gate.
	watcher.safe_center = town_gate()
	watcher.defeated.connect(_on_cultist_defeated)
	watcher.attacked.connect(_on_cultist_attack)
	if bow:
		watcher.set_anchor(at)
		watcher.stand_watch()
	else:
		watcher.arm(_arm_for(guards.size(), species, load))
		watcher.arm_off(str(load.get("off", "")))
	# A rag on its back, so a corpse is worth crossing the road for.
	watcher.armor_items = rag
	guards.append(watcher)
	cultists.append(watcher)
	host.guards.append(watcher)
	return watcher


## The right hand's piece: the load's own where it names one (the cleaver, the
## shiv, the board's club), else the species' tier - a runt takes the short list, a
## full body the road's whole makeshift set - with the ordinal down the lane
## deciding which, so no two bands stand the same fight.
func _arm_for(ordinal: int, species: String, load: Dictionary) -> String:
	var main := str(load.get("main", ""))
	if not main.is_empty():
		return main
	var table: Array = WatcherScript.RUNT_ARMS if species == WatcherScript.RUNT_ID \
		else CULTIST_ARMS
	return str(table[ordinal % table.size()])


## The road answers the leaving: the moment the squad steps out of the camp every
## third body of the chain takes the soul and comes up the lane after it, and the
## rest have to notice the squad by sight - which is what makes the trail feel
## hunted rather than scripted. Called by the camp on ESCAPING - it is the ambush,
## not the start of the road, which has been lying there a hundred and seventy
## metres away the whole time. A campaign that starts in the town never calls it,
## and the road is then just a road with a cult on it.
func wake_road(prey) -> void:
	if _woken or not is_instance_valid(prey):
		return
	_woken = true
	for index in cultists.size():
		if index % 3 != 0:
			continue
		var watcher = cultists[index]
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			watcher.hunt(prey)


## The body stays on the trail as a lootable corpse - registered with the vacuum,
## which reads the blade and the rag off the enemy as it fell. Nothing is dumped on
## the ground as well, and nothing is taken out of its hand: the corpse screen
## lists what the body was carrying.
func _on_cultist_defeated(enemy, _reward: int) -> void:
	# A guest only draws the host's cultists: the kill, its drop and its corpse
	# are booked on the host and arrive here as a snapshot and a record.
	if host != null and bool(host.get("_client")):
		return
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
	# Name the striker before the blow lands, as every blade and shaft does: the
	# squad's party mode reads it (`WarbandBody.struck_by`).
	if victim.has_method("note_attacker"):
		victim.note_attacker(attacker)
	if victim.has_method("receive_melee"):
		outcome = int(victim.receive_melee(amount, WATCHER_SOURCE, attacker.global_position))
	elif victim.has_method("take_damage"):
		victim.take_damage(amount, WATCHER_SOURCE)
		outcome = CombatScript.DEFENSE_NONE
	if outcome == CombatScript.DEFENSE_NONE:
		SfxScript.landed(attacker, victim.global_position + Vector3.UP)
	elif outcome > CombatScript.DEFENSE_NONE:
		# The guard ring reads the victim: a wooden shield thuds, a blade rings.
		SfxScript.defense(attacker.global_position,
			outcome == CombatScript.DEFENSE_PARRY, victim)


func _flat(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()
