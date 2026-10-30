extends "res://scripts/forest_mob.gd"
## The camp's watchers: the wood's antlered wardens, armed and varied.
##
## A watcher is the hollow warden of the Unholy Forest - the same imported body,
## the same baked clips, the same authoritative mob state machine - with three
## things of its own:
##
##   * the variant: a deterministic table entry (paint, silhouette size, weapon,
##     favourite swing, guard share, crouch) picked from the body's id and the
##     ordinal in its node name, so a clearing of watchers reads as a pack of
##     creatures instead of one creature copied;
##   * the arm: a catalog piece built into its right hand as the real model the
##     warband holds (`sword.gd` / `dagger.gd` / `bow.gd` off the hand bone), and
##     only ever the makeshift tier - the camp is a knife fight in the mud;
##   * the fight: three swings to choose between (a sweep, a lunge and the plain
##     overhead), a rolled guard window it holds instead of trading, a stagger
##     when a real blow lands, and a stalking crouch it rests in.
##
## The mob surface the scenes already call is unchanged: `mob_wake`, `hunt`,
## `hunting`, `arm`, `take_weapon_item`, `has_weapon_visual`, `gear_items`,
## `health_pool`, `alive`, `player`, the `defeated`/`attacked` signals, and the
## three dials a wave sets on its own bodies (`blow_scale`, `guard_scale`,
## `swing_gap_scale`).
##
## Everything else is inherited and untouched: sight and the pursuit memory, the
## swept move, the damage funnel, the ragdoll corpse, the tick budget. Which clip
## plays is the sampler's business (`forest_mob_visual.gd` -> `devil_mob_visual.gd`);
## this script only decides what the body is doing.

const ArmorData = preload("res://scripts/armor_data.gd")
## The item catalog: a variant names catalog pieces and the corpse lists them.
const Catalog = preload("res://scripts/player_state.gd")

## The species the camp keeps on its gate. A watcher is a warden whatever a
## scene forgets to set.
const WARDEN_ID := "hollow_warden"

## The pair the lesson fields are thinned bodies; everything else that holds the
## road is a hard body. Both are 30% under their old pools (31/101).
const PAIR_HEALTH := 31.0
const HARDENED_HEALTH := 101.0

## The makeshift tier, in catalog order. No forged steel is allowed in the camp,
## so this is the whole pool a variant may name - and the twig bow is in it
## because a scene may still hand one over, not because a warden is an archer.
const MAKESHIFT_TIER := ["dagger_ironwood", "club_makeshift", "branch_heavy",
	"bow_twig", "shield_wood"]

## What a watcher may wear. The camp is the first scenario and it pays in salvage,
## so a corpse carries the makeshift set or nothing at all; the creature wears no
## armour of its own, this is what a body is carrying. `_pick_variant` holds the
## rule, so a future table row cannot reintroduce a forged kit.
const WATCHER_ARMOUR := ["naked", "makeshift"]

## The swings the warden's body authors, by the name the sampler table uses.
const SWING_OVERHEAD := "overhead"
const SWING_SLASH := "slash"
const SWING_STAB := "stab"

## Every watcher is on the camp's hostile layer: the warband's own combat is
## pointed at layer 2 (`cage_escape.WATCHER_LAYER`), so a body on the arena's
## default 4 would be swung through.
const WATCHER_LAYER := 2
## The pack, so a crowd that spawned in one line does not stand inside itself.
const WATCHER_GROUP := "camp_watchers"
## The wood's authored sight range: a watcher is "hunting" only while its quarry
## is inside it, which is what keeps the road's cult dormant until the leaving.
const SIGHT_RANGE := 60.0
## How long a rolled guard is held. The guard is a settle inside an exchange -
## long enough to read as a brace, short enough that a warden already in reach
## swings straight after it - never a stance and never a way to stand about.
const GUARD_SECONDS := 0.35
## A blow worth this share of the body (or the flat floor) is a stagger: the
## recoil plays and the swing, the guard and the step are all lost. Ten percent
## is the contract's "certain" weight, so a chip is traded through and a real cut
## ends the exchange.
const STAGGER_FLOOR := 6.0
const STAGGER_SHARE := 0.10
const STAGGER_SECONDS := 0.60
## The slack past its reach at which a warden counts as trading - the same band
## the mob's own attack trigger uses, so a guard roll happens exactly when a
## swing would have.
const TRADE_REACH := 1.15

## The deterministic variant table. Every entry is a creature: a paint, a build, a
## piece in its hand and a way of fighting. `tint` multiplies the authored
## surfaces (so a warden keeps its PBR maps and its antlers are its own colour),
## `scale` is applied uniformly to the whole body, `main` is always from the
## makeshift tier, `swing` is the attack it favours - the pool repeats it, so it
## is a preference and not a rotation - and `guard` is the share of exchanges the
## body braces through (never 1.0). `armor` and `pieces` are what the corpse
## carries, and in the first scenario that is the makeshift set or nothing: the
## slots vary so two wardens are not the same corpse, the tier does not.
const VARIANTS := [
	{"name": "Moss Warden", "scale": 1.02, "tint": Color(0.72, 0.86, 0.62),
		"main": "club_makeshift", "swing": SWING_SLASH,
		"armor": "makeshift", "pieces": ["chest", "legs"],
		"guard": 0.52, "crouch": false},
	{"name": "Ash Reaver", "scale": 0.90, "tint": Color(0.84, 0.86, 0.90),
		"main": "dagger_ironwood", "swing": SWING_STAB,
		"armor": "makeshift", "pieces": ["chest", "head"],
		"guard": 0.44, "crouch": true},
	{"name": "Bone Picker", "scale": 1.16, "tint": Color(1.00, 0.96, 0.84),
		"main": "club_makeshift", "swing": SWING_OVERHEAD,
		"armor": "makeshift", "pieces": ["chest", "hands"],
		"guard": 0.60, "crouch": false},
	{"name": "Rustcoat", "scale": 1.24, "tint": Color(0.96, 0.74, 0.58),
		"main": "branch_heavy", "swing": SWING_STAB,
		"armor": "makeshift", "pieces": ["chest", "legs"],
		"guard": 0.48, "crouch": false},
	{"name": "Dull Violet", "scale": 0.94, "tint": Color(0.82, 0.74, 0.96),
		"main": "dagger_ironwood", "swing": SWING_STAB,
		"armor": "makeshift", "pieces": ["chest", "legs", "feet"],
		"guard": 0.66, "crouch": true},
	{"name": "Tallow Sentry", "scale": 1.30, "tint": Color(1.00, 0.92, 0.68),
		"main": "club_makeshift", "swing": SWING_SLASH,
		"armor": "makeshift", "pieces": ["chest", "head"],
		"guard": 0.56, "crouch": false},
	{"name": "Moss Stalker", "scale": 0.88, "tint": Color(0.72, 0.86, 0.62),
		"main": "dagger_ironwood", "swing": SWING_STAB,
		"armor": "naked", "pieces": [],
		"guard": 0.40, "crouch": true},
	{"name": "Ashen Warden", "scale": 1.10, "tint": Color(0.84, 0.86, 0.90),
		"main": "branch_heavy", "swing": SWING_OVERHEAD,
		"armor": "makeshift", "pieces": ["chest", "legs"],
		"guard": 0.50, "crouch": false},
	{"name": "Bone Herald", "scale": 0.98, "tint": Color(1.00, 0.96, 0.84),
		"main": "club_makeshift", "swing": SWING_SLASH,
		"armor": "makeshift", "pieces": ["chest", "head"],
		"guard": 0.62, "crouch": false},
	{"name": "Rust Widow", "scale": 1.06, "tint": Color(0.96, 0.74, 0.58),
		"main": "dagger_ironwood", "swing": SWING_STAB,
		"armor": "makeshift", "pieces": ["chest", "head", "legs"],
		"guard": 0.58, "crouch": true},
	{"name": "Violet Bound", "scale": 1.20, "tint": Color(0.82, 0.74, 0.96),
		"main": "branch_heavy", "swing": SWING_STAB,
		"armor": "makeshift", "pieces": ["chest", "legs"],
		"guard": 0.46, "crouch": false},
	{"name": "Tallow Throat", "scale": 0.92, "tint": Color(1.00, 0.92, 0.68),
		"main": "club_makeshift", "swing": SWING_OVERHEAD,
		"armor": "makeshift", "pieces": ["chest"],
		"guard": 0.68, "crouch": false},
]

## Set before the body enters the tree: the pair Corvin fights are the thinned
## ones, everyone else gets the hardened pool.
var health_pool := HARDENED_HEALTH
## The catalog piece in the right hand, or "" for an empty hand. `arm` writes it,
## `take_weapon_item` hands it back so the scene can drop it.
var weapon_item := ""
## Armour a corpse is carrying. A scene may overwrite it (the road does).
var armor_items: Array[String] = []
## What else is on the body when it falls: a dressing, a bundle, whatever the
## scene put there. It is not worn gear, so it never shows on the model - it is
## only ever offered to whoever searches the corpse.
var carried: Array[String] = []

## Scene dials on this body's fight, set at spawn and read by the swing loop.
## They exist because the same body is a duelist in one wave and an ambusher
## taken by surprise in the next, and those are not the same fight:
## `blow_scale` multiplies what a landed swing takes off, `guard_scale` how often
## it braces at all, `swing_gap_scale` how long it waits between swings, and
## `windup_scale` how long the raised club hangs before it comes down.
var blow_scale := 1.0
var guard_scale := 1.0
var swing_gap_scale := 1.0
var windup_scale := 1.0

## The resolved table entry for this body. Read by the regression and by anything
## that wants to know what a watcher brought.
var variant: Dictionary = {}

var _body_scale := 1.0
var _variant_slot := 0
## The watcher's own clock for the guard roll: one roll per exchange, cleared by
## the swing it opens.
var _exchange_rolled := false
## A landed blow is not a sighting: the body it came from is hunted even from
## inside the safe ring.
var _enraged := false
## True once a scene has woken this watcher (`mob_wake`); only a hunting body
## answers `hunting()` with a pursuit.
var _awake := false


## The camp sets `mob_id` (`hollow_warden`) before the body enters the tree; a
## scene that forgets still gets a warden rather than the devil the mob class
## defaults to. `mob_id` itself is the mob's own member.
func _init() -> void:
	mob_id = WARDEN_ID


func _ready() -> void:
	# The mob's own `_ready` renames itself after its species. A watcher keeps the
	# name its scene gave it (`CampWatcher3`), which is also the ordinal its
	# variant is seeded from.
	var label := name
	super()
	name = label
	variant = _pick_variant()
	_rng.seed = absi(mob_id.hash()) + _variant_slot * 977 + 17
	collision_layer = WATCHER_LAYER
	_shape_body()
	_stamp_armor_items()
	_stamp_carried()
	if weapon_item.is_empty():
		weapon_item = str(variant.get("main", ""))
	_apply_weapon()
	max_health = maxf(health_pool, 1.0)
	health = max_health
	# A mob does not roam like a beast on its patch: a watcher holds its post.
	profile["roam"] = 0.0


# --- the mob surface the scenes call ---------------------------------------

## Start hunting: the senses are on from now on. The camp calls this when Corvin
## reaches the cages; a road cultist gets it when the leaving wakes the road.
func mob_wake() -> void:
	super()
	if not alive:
		return
	if not _awake:
		# First wake: no idle beat to sit through. A watcher handed a quarry
		# engages it at once instead of walking out its spawn cooldown while the
		# target stands in front of it.
		_attack_cooldown = 0.0
	_awake = true


## Commit to a body and charge it. Called on spawn, by `squad_drive.retarget` for
## a watcher that has calmed, and by the camp when the lesson turns.
func hunt(target: Node3D) -> void:
	if not alive or not is_instance_valid(target) or target.get("alive") == false:
		return
	var body := target as CharacterBody3D
	if body == null:
		return
	mob_wake()
	player = body
	# A quarry inside the safe ring is not a sighting; a body that struck this
	# watcher is, wherever it stands.
	if not _enraged and MobSenses.in_safe_ring(safe_center, body.global_position):
		return
	_senses.notice(body, body.global_position)


## True while this watcher has a live pursuit: awake, with a standing quarry
## inside the wood's own sight range.
func hunting() -> bool:
	if not alive or not _awake:
		return false
	var target := _live_target()
	if target == null:
		return false
	var offset := target.global_position - global_position
	return Vector2(offset.x, offset.z).length() <= SIGHT_RANGE


## Record the body that just landed a blow. A hit watcher turns on its striker
## even when the striker is standing in the safe ring.
func note_attacker(attacker: Node3D) -> void:
	super(attacker)
	if not alive or not is_instance_valid(attacker):
		return
	_enraged = true
	var body := attacker as CharacterBody3D
	if body != null:
		player = body
	mob_wake()


## Put a catalog piece in the right hand. The model is the piece the warband
## would hold, hung off the hand bone, so the rig and the corpse agree.
func arm(item_id: String) -> void:
	weapon_item = item_id
	if not is_node_ready():
		return
	_apply_weapon()


## Strip the carried weapon (the scene drops it) and clear the hand.
func take_weapon_item() -> String:
	var item := weapon_item
	weapon_item = ""
	if is_node_ready():
		_apply_weapon()
	return item


## True while the hand is actually holding the catalog piece `weapon_item` names.
func has_weapon_visual() -> bool:
	return is_instance_valid(_visual) and not weapon_item.is_empty() \
		and _visual.held_item() == weapon_item


## Everything worth taking off this body: the piece in its hand and the rag on
## its back. The scene spawns each where it fell.
func gear_items() -> Array[String]:
	var out: Array[String] = []
	if not weapon_item.is_empty():
		out.append(weapon_item)
	for piece in armor_items:
		if not piece.is_empty():
			out.append(piece)
	for piece in carried:
		if not piece.is_empty():
			out.append(piece)
	return out


## The chest, scaled with the body so a small warden is aimed at where it
## actually stands.
func get_aim_position() -> Vector3:
	return global_position + Vector3(0.0, float(profile.get("aim", 1.0)) * _body_scale, 0.0)


func get_display_name() -> String:
	return str(variant.get("name", profile.get("display", "Hollow warden")))


# --- the variant -----------------------------------------------------------

## The table entry for this body, seeded by its id and its ordinal. The camp
## names its watchers `CampWatcher1..N` and the road names its own, so the digits
## in the node name walk the table; a body with no ordinal falls back to the id's
## hash.
func _pick_variant() -> Dictionary:
	_variant_slot = variant_index_for(mob_id, name)
	var out: Dictionary = (VARIANTS[_variant_slot] as Dictionary).duplicate(true)
	if not MAKESHIFT_TIER.has(str(out.get("main", ""))):
		out["main"] = "dagger_ironwood"
	# The first scenario pays in salvage, in the hand and on the corpse alike. The
	# variant table says what a body brought when the camp was written; this is the
	# rule that holds it there - a leather, cloth or mail rag off the first six
	# cultists put a forged kit in a squad's pack before the trail's second torch.
	# Only the tier changes: the paint, the build, the hand and the way of fighting
	# are still the variant's own, and a body that came in with nothing on its back
	# still drops nothing.
	var worn := str(out.get("armor", "naked"))
	if not WATCHER_ARMOUR.has(worn):
		worn = "makeshift"
	out["armor"] = worn
	if worn == "naked":
		out["pieces"] = []
	if health_pool >= HARDENED_HEALTH:
		return out
	# The pair Corvin fights are still their own bodies - their own paint, build
	# and hand - and only thinner: a shiv or a club, never the limb it can barely
	# lift, and one rag on the corpse instead of the whole salvage kit.
	out["guard"] = minf(float(out.get("guard", 0.5)), 0.55)
	if weapon_item.is_empty():
		out["main"] = "club_makeshift" if _variant_slot % 2 == 1 else "dagger_ironwood"
		out["swing"] = SWING_SLASH if _variant_slot % 2 == 1 else SWING_STAB
	if str(out.get("armor", "")) == "makeshift":
		out["pieces"] = ["chest"]
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
## same id and ordinal sign the same string on every run.
static func signature_of(entry: Dictionary) -> String:
	var tint: Color = entry.get("tint", Color.WHITE)
	return "%0.2f|%s|%s|%s|%s|%s" % [float(entry.get("scale", 1.0)),
		tint.to_html(false), str(entry.get("main", "")), str(entry.get("swing", "")),
		str(entry.get("armor", "")),
		"|".join(PackedStringArray(entry.get("pieces", [])))]


func variant_signature() -> String:
	return signature_of(variant)


## The share of exchanges this body braces through. `guard_scale` is the scene's
## dial on top of the variant: the camp sets it low on the ambush, where four
## ambushers that also turtle are not a fight. Never 1.0, because a body that
## always guards never trades.
func guard_chance() -> float:
	return clampf(float(variant.get("guard", 0.5)) * guard_scale, 0.0, 0.9)


func crouch_armed() -> bool:
	return bool(variant.get("crouch", false))


func swing_pool() -> Array:
	return swing_pool_for(weapon_item, str(variant.get("swing", SWING_OVERHEAD)))


func body_scale() -> float:
	return _body_scale


func paint_tint() -> Color:
	return _visual.tint() if is_instance_valid(_visual) else Color.WHITE


## Every authored clip this body claims it will play. The regression asks the
## sampler for each name; a name the table promises and the asset does not carry
## is a `body_plays` miss rather than a silent fallback.
func claimed_clips() -> Array[String]:
	var out: Array[String] = []
	if not is_instance_valid(_visual):
		return out
	for name in _visual.attack_names():
		out.append(_visual.attack_clip(str(name)))
	for clip in [_visual.block_clip(), _visual.stagger_clip(), _visual.crouch_clip()]:
		if not str(clip).is_empty() and not out.has(str(clip)):
			out.append(str(clip))
	return out


func body_plays(clip: String) -> bool:
	return is_instance_valid(_visual) and _visual.has_clip(clip)


## What a weapon can swing: the club sweeps, the shiv and the limb lunge, and the
## plain overhead is always in the pool for variety. The variant's favourite is
## repeated, so the mix is a preference rather than a rotation.
static func swing_pool_for(item_id: String, favourite: String) -> Array:
	var item: Dictionary = Catalog.ITEMS.get(item_id, {})
	var vocabulary: Array = [SWING_OVERHEAD]
	match str(item.get("kind", "")):
		"sword":
			# The club is swung across the body; the whole limb is heavy enough to
			# be driven forward instead (catalog index 4 is the two-hander).
			vocabulary = [SWING_SLASH, SWING_OVERHEAD] if int(item.get("index", 0)) < 4 \
				else [SWING_STAB, SWING_OVERHEAD]
		"dagger":
			vocabulary = [SWING_STAB, SWING_OVERHEAD]
	var pool: Array = []
	# The preference is the body's, not the weapon's: a piece it cannot favour -
	# a forged sword in a shiv-carrier's hand - falls back to the swing the piece
	# itself is made for, so the pool always repeats something.
	var lead := favourite if vocabulary.has(favourite) else str(vocabulary[0])
	pool.append(lead)
	pool.append(lead)
	for name in vocabulary:
		if not pool.has(name):
			pool.append(name)
	return pool


# --- behaviour -------------------------------------------------------------

## The exchange. Inside its own blade a warden plants and swings; circling is
## only ever for closing the distance or resetting after a swing, never a way to
## stand on top of the body it is fighting.
func _circle(delta: float, distance: float, direction: Vector3) -> void:
	var in_reach := distance <= float(profile.reach) + TRADE_REACH
	if _attack_cooldown > 0.0:
		_exchange_rolled = false
	elif in_reach and not _exchange_rolled:
		# One guard roll per exchange, and only when a swing is actually
		# available: the brace is a settle *instead of* an immediate swing, so a
		# hit roll costs `GUARD_SECONDS` and a missed one swings on this tick.
		_exchange_rolled = true
		if _rng.randf() < guard_chance():
			brace(GUARD_SECONDS)
	if not in_reach:
		super(delta, distance, direction)
		return
	# Hold the ground: face the quarry, settle into the guard or the crouch while
	# the beat runs out, and swing the moment it does. Sight is for noticing a
	# body, not for hitting one already inside the blade - an in-reach warden
	# turns and trades instead of walking off to a remembered spot.
	_move_intent = Vector3.ZERO
	_move_speed = 0.0
	_face_intent = direction
	if guard_up() or _attack_cooldown > 0.0:
		return
	_choose_attack()
	_enter("WINDUP")


## One of the three swings, chosen from the variant's pool when the windup starts.
func _choose_attack() -> void:
	if not is_instance_valid(_visual):
		return
	var pool := swing_pool()
	if pool.is_empty():
		return
	_visual.set_attack(str(pool[_rng.randi_range(0, pool.size() - 1)]))


## What one landed strike takes off: the body's own profile, weighted by the
## scene's dial. The scene applies it through the victim's guard.
func _strike_damage() -> float:
	return float(profile.get("damage", 0.0)) * blow_scale


## The telegraph, stretched for a body that is teaching rather than fighting: a
## raised club that hangs for 1.3 s is the window the guard card is written for,
## and the wood's own 0.55 s cannot be answered by somebody reading a card.
func _windup_seconds() -> float:
	return super() * maxf(0.0, windup_scale)


## The beat between two swings: the profile's own cycle, stretched by the dial a
## wave sets on its own bodies.
func _cooldown_seconds() -> float:
	return float(profile.get("cooldown", 1.0)) * maxf(0.0, swing_gap_scale)


func _present_blocking() -> bool:
	return guard_up()


## A crouch-armed warden rests low while it waits on its swing, and holds the
## stance while it is hurt. It stands for the swing itself.
func _present_crouch() -> bool:
	if not crouch_armed() or not alive or state == "STAGGER":
		return false
	return _attack_cooldown > 0.0 or health < max_health


## A blow worth a tenth of the body (or the flat floor) is not shrugged: the
## stagger plays and the swing, the guard and the step are all lost. A chip is
## traded through so the exchange keeps moving.
func take_damage(amount: float, source_id: int, headshot: bool = false) -> void:
	if not alive:
		return
	var before := health
	super(amount, source_id, headshot)
	if not alive:
		return
	if before - health >= _stagger_threshold():
		_braced = 0.0
		stagger(STAGGER_SECONDS)


func _stagger_threshold() -> float:
	return maxf(STAGGER_FLOOR, maxf(max_health, 1.0) * STAGGER_SHARE)


## A dead watcher reports its defeat once, from the inherited death, and leaves
## the body in the mud for the loot vacuum to read.
func _enter_dead(announce: bool) -> void:
	_awake = false
	_enraged = false
	super(announce)


# --- the body and the kit --------------------------------------------------

## The build. The silhouette is scaled uniformly - a stretched body would distort
## the mesh - and the physics capsule stays the profile's, so the reach, the aim
## height and the hit volume the fight is tuned on do not drift with a variant.
func _shape_body() -> void:
	_body_scale = clampf(float(variant.get("scale", 1.0)), 0.88, 1.30)
	if is_instance_valid(_body):
		_body.scale = Vector3.ONE * _body_scale
	if is_instance_valid(_visual):
		_visual.set_tint(variant.get("tint", Color.WHITE))


func _apply_weapon() -> void:
	if is_instance_valid(_visual):
		_visual.set_held_weapon(weapon_item)


## Every body in the wood walks the table with a field dressing tied at its belt:
## the squad's medicine is looted off the mobs it kills, never handed out and never
## out of the shared stash. The variant's own ordinal still decides the ichor, so
## the same warden always carries the same kit.
const CARRIED_BANDAGE := "bandage_linen"
## One warden in three also carries a vial of its own ichor - the reagent the
## campaign's fourth order asks for, and the only way the bench ever gets it in
## the first scenario. It is the variant's property again, not a roll at the kill,
## so a corpse that was killed twice on two machines carried the same vial.
const CARRIED_ICHOR := "ichor_vial"
const ICHOR_EVERY := 3

func _stamp_carried() -> void:
	carried.clear()
	carried.append(CARRIED_BANDAGE)
	# Slots 2, 5, 8 and 11 of the twelve: four wardens in a full table, and the
	# clearings that field six get one or two of them.
	if _variant_slot % ICHOR_EVERY == ICHOR_EVERY - 1:
		carried.append(CARRIED_ICHOR)


func _stamp_armor_items() -> void:
	armor_items.clear()
	var set_name := str(variant.get("armor", "naked"))
	if not WATCHER_ARMOUR.has(set_name) or set_name == "naked":
		return
	var set_index: int = ArmorData.SET_IDS.find(set_name)
	if set_index < 0:
		return
	for slot in variant.get("pieces", []) as Array:
		armor_items.append(ArmorData.item_id(set_index, str(slot)))


# --- helpers ---------------------------------------------------------------

## The body this watcher is after, or null. A downed body is not a target; a
## standing body inside the safe ring is not one either, unless it struck first.
func _live_target() -> CharacterBody3D:
	if not is_instance_valid(player):
		return null
	if player.get("alive") == false or player.get("downed") == true:
		return null
	if not _enraged and MobSenses.in_safe_ring(safe_center, player.global_position):
		return null
	return player


## A watcher hunts the body it was pointed at, not whoever walks past: the camp's
## lesson is four prisoners at the cages and two bodies with a job. `hear_alert`
## and a landed blow still turn it on whoever started it.
func _candidates() -> Array:
	var list: Array = []
	var target := _live_target()
	if target != null:
		list.append(target)
	return list


## Huntable bodies: alive, and either outside the town's safe ring or the one
## that struck this watcher.
func _is_hostile(candidate: Node3D) -> bool:
	if not is_instance_valid(candidate) or candidate.get("alive") == false:
		return false
	if _enraged:
		return true
	return not MobSenses.in_safe_ring(safe_center, candidate.global_position)


## The camp's pack is the watchers: the wood's own mobs are elsewhere and
## separation is the only thing that reads this.
func _group_name() -> String:
	return WATCHER_GROUP
