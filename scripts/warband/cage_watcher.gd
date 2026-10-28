extends "res://scripts/warband/cultist_guard.gd"
## The camp's watchers: ranger-rigged wardens, one per variant, half-armed.
##
## They used to be the wilderness hollow warden, and the silhouette was the whole
## problem: a creature with six baked clips cannot block, stagger, crouch or swing
## a blade more than one way, its pack was identical, and it carried forged
## catalog steel into the opening of a campaign whose first lesson is a knife
## fight in the mud. A watcher is now the same `ArenaActor` body the warband and
## the cult field - rig, melee sweeps, guard, armour, hit react, the authored
## block/stab/crouch clips - wearing a camp kit.
##
## Three things are the watcher's own:
##
##   * the variant: a deterministic table entry (scale, build, paint, armour
##     subset, main hand, off hand, guard chance, crouch) picked from the body's
##     id, so a clearing of watchers reads as a clearing of people;
##   * the kit tier: only makeshift steel. The five pieces the camp's armorer
##     actually sells are the only main hands a variant names;
##   * the mob surface the scenes already call: `mob_wake`, `hunt`, `hunting`,
##     `arm`, `take_weapon_item`, `gear_items`, and the `defeated`/`attacked`
##     signals that resolve a blow through the victim's own guard.
##
## The body ticks itself: `world_scene.gd` says "the watchers tick themselves",
## and no scene steps `host.guards`, so `_physics_process` is the clock.

## One watcher dies: `cage_escape._on_watcher_defeated` and
## `escape_run._on_cultist_defeated` are connected to this and take the gear.
signal defeated(enemy, reward)
## One watcher's swing reached a body. The scene applies it through the body's own
## guard, exactly like the frontier's `_on_enemy_attack`.
signal attacked(attacker, amount, victim)

const MobSenses = preload("res://scripts/mob_senses.gd")
const Arrow = preload("res://scripts/arrow.gd")
## The item catalog, under a local name: the static variant helpers read it, and
## a static function resolves its own class's constants without guessing at the
## inherited ones.
const Catalog = preload("res://scripts/player_state.gd")

## The pair Corvin puts down are thinned mooks; everything else that holds the
## road is twice what a camp watcher used to be.
const PAIR_HEALTH := 44.0
const HARDENED_HEALTH := 144.0

## The makeshift tier, in catalog order. No forged steel is allowed in the camp,
## so this is the whole main-hand pool the variant table may name.
const MAKESHIFT_MAINS := ["dagger_ironwood", "bow_twig", "club_makeshift", "branch_heavy"]

## What a watcher may wear. The four salvage sets and the shirt on its back.
const WATCHER_ARMOUR := ["naked", "makeshift", "cloth", "leather", "mail"]

## The clips the melee behaviour claims. The rig's mapping is copied here exactly
## so the regression can ask any body what it says it will play and find it in the
## authored animation player.
const BLOCK_ONE_HAND := "Sword_Block_Loop_OneHand"
const BLOCK_TWO_HAND := "Sword_Block_Loop"
const STAB_CLIP := "Dagger_Stab"
const OVERHEAD_CLIP := "Sword_Overhead"
const OVERHEAD_ONE_HAND_CLIP := "Sword_Overhead_OneHand"
const CROUCH_CLIP := "Crouch_Idle_Loop"

## Every watcher is on the camp's hostile layer: the warband's own combat is
## pointed at layer 2 (`cage_escape.WATCHER_LAYER`), so a body on the arena's
## default 4 would be swung through.
const WATCHER_LAYER := 2
## The pack, so a crowd that spawned in one line does not walk into one body.
const WATCHER_GROUP := "camp_watchers"
## How far a watcher keeps from another watcher's centre.
const PACK_GAP := 1.1
## Watchmen slots sit above the warband's own so `take_damage` never reads a
## watcher's blow as the body's own (slot 0 would swallow a `source_id` of 0).
const WATCHER_SLOT_BASE := 500
## The wood's authored sight range. A watcher is "hunting" only while its quarry
## is inside it, which is what keeps the road's cult dormant until the leaving.
const SIGHT_RANGE := 60.0
## Parking distance: past this a watcher stops ticking entirely, and it comes back
## the moment a body closes to `WAKE_DISTANCE`. The gap between the two is what
## keeps a body on the boundary from flickering in and out of sleep.
const SLEEP_DISTANCE := 82.0
const WAKE_DISTANCE := 66.0
## How often a parked watcher checks the one number that can wake it.
const DROWSY_SECONDS := 0.1
## How long a rolled guard is held, and the beat between two swings. The guard is
## a window inside an exchange, never a stance.
const GUARD_SECONDS := 0.55
const SWING_GAP := 0.35
## A blow worth this share of the body (or the flat floor) is a stagger: the hit
## react plays and the swing, guard and step are all lost. Ten percent is the
## contract's "certain" weight, so a chip is traded through and a real cut ends
## the exchange.
const STAGGER_FLOOR := 6.0
const STAGGER_SHARE := 0.10
## How close a blade has to pass a body's chest to count as a landed swing.
const VICTIM_RADIUS := 0.32
## A bow watcher keeps this band: back off inside it, walk in outside it.
const BOW_NEAR := 5.5
const BOW_FAR := 15.0
## The arena clamps a body to its bed (`bounds`). The camp and the road are
## kilometres apart in one scene, so the watcher removes the leash.
const CAMP_BOUNDS := 4096.0

## The deterministic variant table. Every entry is a person: a build, a colour, a
## kit and a way of fighting. `scale` shapes the body's reach, capsule and aim
## height, `hunch` leans the whole skeleton, `pieces` is the armour subset worn
## from `armor`, `main` is always from the makeshift tier, and `guard` is the share
## of exchanges the body braces through (never 1.0).
const VARIANTS := [
	{"name": "Moss Warden", "scale": 0.92, "hunch": -0.07,
		"tint": Color(0.23, 0.30, 0.17), "armor": "leather", "pieces": ["chest", "legs", "feet"],
		"main": "club_makeshift", "off": "", "guard": 0.58, "crouch": true, "stagger": 0.45},
	{"name": "Ash Knife", "scale": 0.88, "hunch": -0.11,
		"tint": Color(0.36, 0.37, 0.36), "armor": "cloth", "pieces": ["chest", "head"],
		"main": "dagger_ironwood", "off": "", "guard": 0.52, "crouch": true, "stagger": 0.40},
	{"name": "Bone Picker", "scale": 1.02, "hunch": 0.02,
		"tint": Color(0.71, 0.67, 0.54), "armor": "makeshift", "pieces": ["chest", "hands"],
		"main": "club_makeshift", "off": "shield_wood", "guard": 0.66, "crouch": false, "stagger": 0.50},
	{"name": "Rustcoat", "scale": 1.08, "hunch": -0.04,
		"tint": Color(0.38, 0.20, 0.11), "armor": "leather", "pieces": ["chest", "legs"],
		"main": "dagger_ironwood", "off": "dagger_ironwood", "guard": 0.46,
		"crouch": false, "stagger": 0.55},
	{"name": "Dull Violet", "scale": 0.96, "hunch": -0.12,
		"tint": Color(0.31, 0.22, 0.39), "armor": "cloth", "pieces": ["chest", "legs", "feet"],
		"main": "club_makeshift", "off": "", "guard": 0.70, "crouch": true, "stagger": 0.45},
	{"name": "Tallow", "scale": 1.12, "hunch": 0.07,
		"tint": Color(0.78, 0.73, 0.55), "armor": "mail", "pieces": ["chest"],
		"main": "branch_heavy", "off": "", "guard": 0.52, "crouch": false, "stagger": 0.60},
	{"name": "Grey Sentry", "scale": 1.00, "hunch": 0.00,
		"tint": Color(0.29, 0.31, 0.33), "armor": "mail", "pieces": ["chest", "head"],
		"main": "club_makeshift", "off": "shield_wood", "guard": 0.64, "crouch": false, "stagger": 0.50},
	{"name": "Green Stalker", "scale": 0.90, "hunch": -0.06,
		"tint": Color(0.19, 0.26, 0.15), "armor": "naked", "pieces": ["chest"],
		"main": "bow_twig", "off": "", "guard": 0.48, "crouch": true, "stagger": 0.40},
	{"name": "Brown Bully", "scale": 1.05, "hunch": 0.05,
		"tint": Color(0.43, 0.27, 0.15), "armor": "makeshift", "pieces": ["chest", "legs"],
		"main": "branch_heavy", "off": "", "guard": 0.56, "crouch": false, "stagger": 0.60},
	{"name": "Pale Throat", "scale": 0.94, "hunch": -0.09,
		"tint": Color(0.66, 0.62, 0.56), "armor": "cloth", "pieces": ["chest", "head"],
		"main": "dagger_ironwood", "off": "shield_wood", "guard": 0.60, "crouch": true, "stagger": 0.40},
	{"name": "Slate", "scale": 1.10, "hunch": 0.03,
		"tint": Color(0.25, 0.28, 0.32), "armor": "leather", "pieces": ["chest", "head", "legs"],
		"main": "club_makeshift", "off": "", "guard": 0.47, "crouch": false, "stagger": 0.50},
	{"name": "Violet Bound", "scale": 0.98, "hunch": -0.02,
		"tint": Color(0.34, 0.24, 0.42), "armor": "makeshift", "pieces": ["chest"],
		"main": "dagger_ironwood", "off": "", "guard": 0.68, "crouch": true, "stagger": 0.45},
]

## The mob id the scenes set before the body enters the tree (`hollow_warden`).
## It seeds the variant along with the node's own ordinal.
var mob_id := ""
## Set before the body enters the tree: the pair Corvin fights are the thinned
## ones, everyone else gets the hardened pool.
var health_pool := HARDENED_HEALTH
## The catalog piece in the right hand, or "" for an empty hand. `arm` writes it,
## `take_weapon_item` hands it back so the scene can drop it.
var weapon_item := ""
## Armour a corpse is carrying. The rig wears the variant's set; this is what the
## scene spawns as loot, and a scene may overwrite it (the road does).
var armor_items: Array[String] = []
## The body this watcher has been pointed at. `squad_drive.retarget` writes it,
## `hunt` commits to it.
var player: Node3D = null
## A no-hunt ring, in `MobSenses` units. The camp leaves it at the origin, which
## is the yard: the caged prisoners are inside it and are never hunted. The road
## points it at the town gate.
var safe_center := Vector3.ZERO
## The resolved table entry for this body. Read by the regression and by anything
## that wants to know what a watcher brought.
var variant: Dictionary = {}

var _body_scale := 1.0
## True while this watcher is parked (see `_park`): no physics step, no rig solve.
var _asleep := false
var _drowsy := 0.0
var _skin: StandardMaterial3D = null
var _variant_slot := 0
var _rng := RandomNumberGenerator.new()
## The watcher's own clock. Guard windows and swing gaps are stamped against it,
## so nothing here depends on the physics frame counter.
var _clock := 0.0
var _swing_ends := 0.0
var _next_swing := 0.0
var _guard_until := 0.0
## True once the guard for this exchange has been rolled (hit or missed). Cleared
## whenever a swing starts, so every exchange rolls once.
var _exchange_rolled := false
var _awake := false
## A landed blow is not a sighting: the body it came from is hunted even from
## inside the safe ring.
var _enraged := false
var _bow := false
var _swings: Array = ["overhead"]


func _ready() -> void:
	super()
	# The camp and the road are one world; the arena's bed would clamp a watcher
	# standing at the mouth straight into the yard.
	bounds = CAMP_BOUNDS
	collision_layer = WATCHER_LAYER
	# World and the warband's bodies, exactly the wilderness mob's kit: a watcher
	# stops at the body it is fighting instead of standing inside it, and never
	# hard-collides with its own pack.
	collision_mask = 1 | 4
	max_slides = 2
	authoritative = true
	is_bot = true
	# The arena body hands its damage funnel to `configure()`; a watcher never
	# calls that. Combat still animates the swing, the guard and the stagger, but
	# the contact is the `attacked` signal so the scene resolves it through the
	# victim's own guard, exactly like every other mob in the game.
	combat.damage_enabled = false
	variant = _pick_variant()
	slot = WATCHER_SLOT_BASE + _variant_slot
	combat.source_id = slot
	_rng.seed = absi(str(mob_id).hash()) + _variant_slot * 977 + 17
	if weapon_item.is_empty():
		weapon_item = str(variant.get("main", ""))
	_shape_body()
	_apply_variant_kit()
	_stamp_armor_items()
	health = health_pool
	stamina = max_stamina
	display_name = str(variant.get("name", "Watcher"))
	# The arena nameplate and the ground ring are fighter furniture; a watcher is
	# scenery until it swings. `_process` rewrites the ring's visibility every
	# frame, so it is switched off by layer instead of by `visible`.
	if _label != null:
		_label.visible = false
	if _ground_ring != null:
		_ground_ring.layers = 0
	rig.melee_sweep.connect(_on_melee_sweep)
	fired.connect(_on_fired)
	add_to_group(WATCHER_GROUP)


## The watcher is its own clock. No scene calls `step` on `host.guards`; the world
## hands it a target through `player` and this tick runs the body down.
func _physics_process(delta: float) -> void:
	if not authoritative or not alive:
		return
	var actors: Array = []
	var target: Node3D = _live_target()
	if _awake and target != null:
		actors.append(target)
	step(delta, actors, Engine.get_physics_frames())
	_check_dormancy(target)


## A watcher nothing is anywhere near costs nothing: the body stops ticking and
## the rig stops solving bones, which is the whole cost of a ranger rig. Forty of
## them down a nine hundred metre road would otherwise all animate for a squad
## standing at the far end. `retarget` still hands a parked body its quarry the
## moment one comes inside the scene's aggro ring, and `_process` wakes it.
func _check_dormancy(target: Node3D) -> void:
	if _asleep or _awake or combat.stagger_time > 0.0:
		return
	if is_instance_valid(target) \
			and global_position.distance_to(target.global_position) < SLEEP_DISTANCE:
		return
	_park()


## A parked watcher still watches the one cheap thing there is to watch: the
## distance to the body the scene last named. Ten checks a second, no physics, no
## animation.
func _process(delta: float) -> void:
	if not _asleep:
		return
	_drowsy += delta
	if _drowsy < DROWSY_SECONDS:
		return
	_drowsy = 0.0
	if not is_instance_valid(player):
		return
	if global_position.distance_to(player.global_position) <= WAKE_DISTANCE:
		_wake()


func _park() -> void:
	_asleep = true
	_drowsy = 0.0
	set_physics_process(false)
	set_process(true)
	if is_instance_valid(rig):
		rig.set_physics_process(false)


func _wake() -> void:
	if not _asleep:
		return
	_asleep = false
	set_process(false)
	set_physics_process(true)
	if is_instance_valid(rig):
		rig.set_physics_process(true)

# --- the mob surface the scenes call ---------------------------------------

## Start hunting: the senses are on from now on. The camp calls this when Corvin
## reaches the cages; a road cultist gets it when the leaving wakes the road.
func mob_wake() -> void:
	if not alive:
		return
	_wake()
	_awake = true


## Commit to a body and charge it. Called on spawn, by `squad_drive.retarget` for
## a watcher that has calmed, and by the camp when the lesson turns.
func hunt(target: Node3D) -> void:
	if not alive or not is_instance_valid(target):
		return
	if target.get("alive") == false:
		return
	_wake()
	player = target
	# A quarry inside the safe ring is not a sighting; a body that struck this
	# watcher is, wherever it stands.
	if _enraged or not MobSenses.in_safe_ring(safe_center, target.global_position):
		_awake = true


## True while this watcher has a live pursuit: awake, with a standing quarry
## inside the wood's own sight range.
func hunting() -> bool:
	if not _awake:
		return false
	var target: Node3D = _live_target()
	if target == null:
		return false
	var offset: Vector3 = target.global_position - global_position
	return Vector2(offset.x, offset.z).length() <= SIGHT_RANGE


## Record the body that just landed a blow. A hit watcher turns on its striker
## even when the striker is standing in the safe ring.
func note_attacker(attacker: Node3D) -> void:
	if not alive or not is_instance_valid(attacker):
		return
	player = attacker
	_enraged = true
	_awake = true


## Put a catalog piece in the right hand. The rig builds every makeshift weapon
## already, so this is the same `apply_kit` path the cult uses; the body's build
## and paint are untouched.
func arm(item_id: String) -> void:
	weapon_item = item_id
	if not is_node_ready():
		return
	_apply_variant_kit()


## Strip the carried weapon (the scene drops it) and clear the hand.
func take_weapon_item() -> String:
	var item := weapon_item
	weapon_item = ""
	if is_node_ready():
		_apply_variant_kit()
	return item


## True while the rig is actually holding the catalog piece `weapon_item` names.
func has_weapon_visual() -> bool:
	if not is_instance_valid(rig) or weapon_item.is_empty():
		return false
	var item: Dictionary = Catalog.ITEMS.get(weapon_item, {})
	if item.is_empty():
		return false
	var index := int(item.get("index", 0))
	match str(item.get("kind", "")):
		"sword":
			return rig.weapon in ["sword", "dual"] and rig.sword_index == index and not rig.staff_active
		"dagger":
			return rig.weapon == "dagger" and rig.dagger_index == index
		"bow":
			return rig.weapon == "bow" and rig.bow_index == index
	return false


## Everything worth taking off this body: the blade in its hand and the rag on
## its back. The scene spawns each as a drop where it fell.
func gear_items() -> Array[String]:
	var out: Array[String] = []
	if not weapon_item.is_empty():
		out.append(weapon_item)
	for piece in armor_items:
		if not piece.is_empty():
			out.append(piece)
	return out


## A watcher is a mob, not a fighter with a revive clock: a lethal blow puts it
## down for good and the bleed state never opens.
func enter_downed(source_id: int = -1) -> void:
	if not alive or downed:
		return
	_die(source_id)


## The chest, scaled with the body so a small watcher is aimed at where it
## actually is rather than where the arena's default body would be.
func get_aim_position() -> Vector3:
	return global_position + Vector3(0, 1.2 * _body_scale, 0)

# --- damage and death ------------------------------------------------------

## A landed blow above the threshold must be seen: the hit react plays and the
## swing, guard and step are lost. The arena's own reaction is a roll, and a mob
## that shrugs a real hit reads as scenery, so the watcher takes it every time.
func take_damage(amount: float, source_id: int, headshot: bool = false,
		_react: bool = true) -> void:
	_wake()
	if not authoritative or not alive or source_id == slot:
		return
	var before := health
	super.take_damage(amount, source_id, headshot, false)
	if not alive:
		return
	var applied := before - health
	if applied >= maxf(STAGGER_FLOOR, max_health * STAGGER_SHARE) \
			and combat.stagger_time <= 0.0:
		stagger(float(variant.get("stagger", 0.45)))


## The inherited death hides the rig and starts the arena's respawn clock. A
## watcher leaves a body in the mud instead, and `CultistGuard.step` already
## refuses to bring a dead body back.
func _die(source_id: int) -> void:
	if not alive:
		return
	super._die(source_id)
	_awake = false
	_enraged = false
	if is_instance_valid(rig):
		rig.visible = true
		rig.set_downed(true)
	defeated.emit(self, 0)

# --- behaviour -------------------------------------------------------------

## The arena bot step is replaced wholesale: it swings one overhead and guards
## never. A watcher picks its swing from its own weapon's vocabulary, rolls a
## guard for each exchange, crouches when its variant is crouch-armed, and walks
## (never sprints) onto its quarry.
func _bot_step(delta: float, _actors: Array) -> void:
	_clock += delta
	if combat.stagger_time > 0.0:
		_idle_step()
		return
	var target: Node3D = _live_target()
	if not _awake or target == null:
		_idle_step()
		return
	var offset: Vector3 = target.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	var forward: Vector3 = -rig.global_basis.z
	if distance > 0.0001:
		forward = offset / distance
	var aim: Vector3 = target.get_aim_position() if target.has_method("get_aim_position") \
		else target.global_position + Vector3(0, 1.0, 0)
	combat.set_aim(aim)
	if distance > 0.0001:
		# Face the quarry: the guard's own facing roll reads this, so a watcher
		# that kept its back turned would not be able to block at all.
		rig.rotation.y = atan2(-forward.x, -forward.z)
	if _bow:
		_bow_step(distance, forward)
	else:
		_melee_step(distance, forward)
	_keep_the_pack_apart()


## Six watchers out of one treeline all walk the same body down; without this
## they would stand inside each other. The arena's own soft separation only acts
## inside half a metre, which is already a huddle, so the pack uses the old
## mob's spacing.
func _keep_the_pack_apart() -> void:
	# A body in a swing or behind a raised guard holds its ground; the crowd
	# spreads in the beats between exchanges, not through them.
	if combat.blocking or rig.is_melee():
		return
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group(WATCHER_GROUP):
		if other == self or not is_instance_valid(other) or not bool(other.get("alive")):
			continue
		var offset: Vector3 = global_position - other.global_position
		offset.y = 0.0
		var gap := offset.length()
		if gap <= 0.001 or gap >= PACK_GAP:
			continue
		push += offset / gap * (PACK_GAP - gap)
	if push.length_squared() <= 0.000001:
		return
	var wanted := Vector3(move_direction.x, 0.0, move_direction.y) + push * 0.8
	move_direction = Vector2(wanted.x, wanted.z).limit_length(1.0)


func _idle_step() -> void:
	move_direction = Vector2.ZERO
	run_requested = false
	_set_crouch(crouch_armed() and health < max_health)
	combat.stop()


func _melee_step(distance: float, forward: Vector3) -> void:
	var reach: float = float(rig.melee_reach("right")) * _body_scale
	var close := distance <= reach + VICTIM_RADIUS + 0.35
	if not close:
		move_direction = Vector2(forward.x, forward.z)
		run_requested = false
		_set_guard(false, forward)
		_set_crouch(false)
		return
	move_direction = Vector2.ZERO
	run_requested = false
	# One guard roll per exchange, once the previous swing has finished.
	if _clock >= _swing_ends and not _exchange_rolled:
		_exchange_rolled = true
		if _rng.randf() < guard_chance():
			_guard_until = _clock + GUARD_SECONDS
	if _clock < _guard_until:
		_set_crouch(false)
		_set_guard(true, forward)
		return
	_set_guard(false, forward)
	var waiting := _clock < _next_swing
	_set_crouch(crouch_armed() and waiting)
	if waiting:
		return
	_set_crouch(false)
	var swing := str(_swings[_rng.randi_range(0, _swings.size() - 1)])
	if combat.begin_melee("right", swing):
		var seconds: float = rig.melee_seconds("right")
		_swing_ends = _clock + seconds
		_next_swing = _swing_ends + SWING_GAP
		_exchange_rolled = false


## A twig bow is still a bow: the watcher holds the band and shoots. The world
## never hands a mob an arrow, so the watcher owns its shaft and launches it on
## the rig's own release, through the arena arrow that already resolves terrain,
## armour and the victim's damage funnel.
func _bow_step(distance: float, forward: Vector3) -> void:
	_set_guard(false, forward)
	_set_crouch(false)
	if distance < BOW_NEAR:
		move_direction = Vector2(-forward.x, -forward.z)
	elif distance > BOW_FAR:
		move_direction = Vector2(forward.x, forward.z)
	else:
		move_direction = Vector2.ZERO
	run_requested = false
	if combat.can_draw():
		combat.begin_draw()
	elif rig.phase in ["DRAWING", "HOLDING"] and rig.draw_amount >= 0.85:
		combat.release_draw()


## The guard is the arena's own authored block: `start_block` plays
## `Sword_Block_Loop*` and the victim-side defence roll reads the facing.
func _set_guard(on: bool, forward: Vector3) -> void:
	if not on:
		if combat.blocking:
			combat.stop_block()
		return
	if combat.blocking:
		combat.face_block(forward)
	else:
		combat.start_block(forward)


## The crouch entry the arena exposes is `cover.crouch_requested` (that is the
## field `set_crouch` writes); `ArenaActor.step` feeds `cover.crouch_amount` into
## the rig, which plays the authored `Crouch_Idle_Loop` and `Crouch_Fwd_Loop`.
func _set_crouch(value: bool) -> void:
	if cover.crouch_requested == value:
		return
	cover.crouch_requested = value
	if value:
		slide.reset()
		rig.set_slide(-1.0, Vector3.FORWARD)


## The rig's own sweep window is the contact. Combat's damage is off on this body,
## so this is the one place a swing can land: the blade segment against the
## quarry's chest, then the scene owns the guard roll.
func _on_melee_sweep(hand: String, _previous_base: Vector3, _previous_tip: Vector3,
		current_base: Vector3, current_tip: Vector3, radius: float) -> void:
	if hand != "right" or not alive or combat.stagger_time > 0.0:
		return
	var victim: Node3D = _live_target()
	if victim == null or not victim.has_method("receive_melee"):
		return
	var point: Vector3 = victim.get_aim_position() if victim.has_method("get_aim_position") \
		else victim.global_position + Vector3(0, 1.0, 0)
	if _segment_gap(point, current_base, current_tip) > radius + VICTIM_RADIUS:
		return
	attacked.emit(self, rig.melee_damage("right"), victim)


func _on_fired(_slot: int, origin: Vector3, direction: Vector3, speed: float,
		charge: float) -> void:
	var parent := get_parent()
	if not alive or not _bow or parent == null:
		return
	var arrow := Arrow.new()
	arrow.source_id = slot
	arrow.hit_mask = 1 | 4 | 8
	arrow.authoritative_damage = true
	parent.add_child(arrow)
	var excluded: Array[RID] = [get_rid()]
	arrow.launch(origin, direction, speed, Combat.damage_for(rig.bow_index, charge), excluded)

# --- the variant -----------------------------------------------------------

## The table entry for this body, seeded by its id. The camp names its watchers
## `CampWatcher1..N` and the road names its own, so the ordinal in the node name
## walks the table; a body with no ordinal falls back to the id's hash.
func _pick_variant() -> Dictionary:
	_variant_slot = variant_index_for(mob_id, name)
	var out: Dictionary = (VARIANTS[_variant_slot] as Dictionary).duplicate(true)
	if not MAKESHIFT_MAINS.has(str(out.get("main", ""))):
		out["main"] = "dagger_ironwood"
	if health_pool >= HARDENED_HEALTH:
		return out
	# The pair Corvin fights: a shiv or a club, never a shield, and only the
	# shirt on its back or the salvage kit. Everything else about the body is
	# still its own variant, so the two do not read as clones.
	out["name"] = "Camp Watcher"
	out["off"] = ""
	out["armor"] = "makeshift" if _variant_slot % 2 == 1 else "naked"
	out["pieces"] = ["chest", "legs"] if _variant_slot % 2 == 1 else ["chest"]
	out["guard"] = minf(float(out.get("guard", 0.5)), 0.55)
	if weapon_item.is_empty():
		out["main"] = "club_makeshift" if _variant_slot % 2 == 1 else "dagger_ironwood"
	return out


## The deterministic table index for a watcher id. `7` is coprime with the table
## size, so consecutive ordinals walk every entry instead of repeating.
static func variant_index_for(watcher_id: String, node_name: String) -> int:
	var digits := ""
	for index in node_name.length():
		var code := node_name.unicode_at(index)
		if code >= 48 and code <= 57:
			digits += node_name[index]
	var base := absi(watcher_id.hash())
	if digits.is_empty():
		return base % VARIANTS.size()
	return (base + int(digits) * 7) % VARIANTS.size()


## One variant's identity, as the regression compares it. Two bodies with the
## same id must sign the same string on every run.
static func signature_of(entry: Dictionary) -> String:
	var main_id := str(entry.get("main", ""))
	var tint: Color = entry.get("tint", Color.WHITE)
	return "%0.2f|%s|%s|%s|%s|%s" % [float(entry.get("scale", 1.0)),
		tint.to_html(false), main_id, str(entry.get("off", "")),
		str(entry.get("armor", "")), "|".join(PackedStringArray(swing_pool_for(main_id)))]


func variant_signature() -> String:
	return signature_of(variant)


## The share of exchanges this body braces through. Read by the regression and by
## the fight itself; never 1.0, because a body that always guards never trades.
func guard_chance() -> float:
	return clampf(float(variant.get("guard", 0.5)), 0.0, 0.95)


func crouch_armed() -> bool:
	return bool(variant.get("crouch", false))


func swing_pool() -> Array:
	return _swings.duplicate()


func body_scale() -> float:
	return _body_scale


func paint_tint() -> Color:
	return _skin.albedo_color if _skin != null else Color.WHITE


## The clips this body claims it will play. The regression asks the rig for each
## one, so a claim the authored library cannot back is a failure rather than a
## silent fallback.
func claimed_clips() -> Array[String]:
	var out: Array[String] = []
	if not is_instance_valid(rig):
		return out
	if _bow:
		return out
	out.append(_block_clip())
	for swing in _swings:
		var clip := _clip_for(str(swing))
		if not out.has(clip):
			out.append(clip)
	if crouch_armed():
		out.append(CROUCH_CLIP)
	return out


func rig_plays(clip: String) -> bool:
	return is_instance_valid(rig) and rig._player != null and rig._player.has_animation(clip)


## The rig's own melee clip mapping: a dagger uses the authored thrust for every
## variant, a diagonal reuses the authored overhead, and a two-hander the
## two-hand overhead.
func _clip_for(swing: String) -> String:
	if rig.weapon == "dagger" or swing == "stab":
		return STAB_CLIP
	if swing in ["diagonal_left", "diagonal_right"]:
		return OVERHEAD_CLIP
	return OVERHEAD_CLIP if rig.sword_index == 2 else OVERHEAD_ONE_HAND_CLIP


func _block_clip() -> String:
	return BLOCK_TWO_HAND if rig.sword_index == 2 else BLOCK_ONE_HAND


## What a weapon can swing. A shiv thrusts, a club overheads and cuts diagonally,
## a tree limb is all overhead and backhand. The pool repeats the body's
## favourite so the mix is a preference, not a rotation.
static func swing_pool_for(item_id: String) -> Array:
	var item: Dictionary = Catalog.ITEMS.get(item_id, {})
	var kind := str(item.get("kind", ""))
	if kind == "dagger":
		return ["stab", "stab", "diagonal_left"]
	if kind == "sword":
		if int(item.get("index", 0)) >= 4:
			return ["overhead", "overhead", "diagonal_right"]
		return ["overhead", "diagonal_left", "diagonal_right"]
	return ["overhead"]

# --- the kit and the body --------------------------------------------------

## The build. The rig's skeleton is what the skin follows, so scaling it scales
## the silhouette and, because the weapon nodes are posed onto bone transforms,
## the visible reach with it. The physics capsule stays the arena's: `cover` owns
## its height for the crouch every stance tick, and a scaled hit body would be
## 10 cm off the floor at the ends of the range for no gameplay gain.
func _shape_body() -> void:
	_body_scale = clampf(float(variant.get("scale", 1.0)), 0.88, 1.12)
	if not is_instance_valid(rig) or not is_instance_valid(rig.skeleton):
		return
	# The skeleton node is never scaled. A scaled skeleton makes every bone basis
	# non-orthonormal, and Godot's pose math casts those bases to quaternions -
	# which logs an engine error per bone per frame, forty bodies over one road.
	# Size lives in `_body_scale` (capsule, reach, aim height) and in the build:
	# the lean, the armour subset, the kit and the shoulders, none of which touch
	# the skeleton's own transform.
	rig.skeleton.rotation.x = float(variant.get("hunch", 0.0))


## Dress the body through the cult kit path (`apply_kit` -> `Archer.apply_loadout`
## -> the rig's own weapons and armour), then cut the worn pieces down to the
## variant's subset. Called on ready, on `arm` and on `take_weapon_item`, so the
## rig and the catalog string can never disagree.
func _apply_variant_kit() -> void:
	apply_kit(weapon_item, str(variant.get("off", "")), str(variant.get("armor", "naked")))
	var pieces := _resolved_pieces()
	rig.set_armor_pieces(pieces)
	kit["pieces"] = pieces.duplicate()
	_bow = str(Catalog.ITEMS.get(weapon_item, {}).get("kind", "")) == "bow"
	_swings = swing_pool_for(weapon_item)
	_stamp_health()
	_paint()


func _resolved_pieces() -> Dictionary:
	var set_index: int = ArmorData.SET_IDS.find(str(variant.get("armor", "naked")))
	var worn: Array = variant.get("pieces", [])
	var pieces := {}
	for slot in ArmorData.SLOTS:
		pieces[slot] = set_index if set_index >= 0 and worn.has(slot) else ArmorData.NONE
	return pieces


## The health pool is the camp's contract, and a loadout change re-derives
## `max_health` from the trinket table, so every kit step stamps the pool back on.
func _stamp_health() -> void:
	max_health = maxf(health_pool, 1.0)
	health = minf(health, max_health)


func _stamp_armor_items() -> void:
	armor_items.clear()
	var set_name := str(variant.get("armor", "naked"))
	if not WATCHER_ARMOUR.has(set_name):
		return
	var set_index: int = ArmorData.SET_IDS.find(set_name)
	if set_index < 0 or set_name == "naked":
		return
	for slot in variant.get("pieces", []) as Array:
		armor_items.append(ArmorData.item_id(set_index, str(slot)))


## One material for every mesh under the rig: one resource per watcher, so a
## variant's paint can never recolour the body beside it. Replaces the cult's
## crimson with the variant's own colour.
func _paint() -> void:
	if _skin == null:
		_skin = StandardMaterial3D.new()
		_skin.resource_name = "WatcherPaint"
		_skin.albedo_color = variant.get("tint", Color(0.4, 0.35, 0.3))
		_skin.metallic = 0.08
		_skin.roughness = 0.62
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = _skin

# --- helpers ---------------------------------------------------------------

## The body this watcher is after, or null. A downed body is not a target; a
## standing body inside the safe ring is not one either, unless it struck first.
func _live_target() -> Node3D:
	if not is_instance_valid(player):
		return null
	if player.get("alive") == false or player.get("downed") == true:
		return null
	if not _enraged and MobSenses.in_safe_ring(safe_center, player.global_position):
		return null
	return player


## Shortest distance from a point to a blade segment: the sweep window is a
## segment cast, and a body inside it is a landed blow.
static func _segment_gap(point: Vector3, from: Vector3, to: Vector3) -> float:
	var span := to - from
	var length_squared := span.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(from)
	var t := clampf((point - from).dot(span) / length_squared, 0.0, 1.0)
	return point.distance_to(from + span * t)
