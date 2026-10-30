extends "res://scripts/warband/cage_watcher.gd"
## The hollow warden with a bow: the trail's hidden archers.
##
## A watcher is a club-and-shiv ambusher; this one is the same authored body, the
## same variant table and the same sampler, with a twig bow in its hand and a
## different exchange: it never closes to blade reach. It holds a ring 8-16 m out,
## draws the `Warden_Attack_Stab` clip as its release, and puts a real `arrow.gd`
## shaft through the air with the cinder devil's own lead and drop - the arrow is
## spawned through the world's projectile list, so a co-op guest draws the same
## flight and only the host resolves the hit. When a body closes inside 6 m it
## gives ground 3-6 m rather than trading, and it never leaves the trees it was
## posted in: the leash is the group's own anchor, not the player's position.
##
## Hidden until sprung: `player` stays null and the body rests in its crouch, so
## nothing in the wood notices a body walking past at 25 m. `escape_run.gd` polls
## the three-group ambush and calls `begin_ambush()` on all three at once; a blow
## that lands on the archer springs it the same way.

const ArrowScript = preload("res://scripts/arrow.gd")

## The catalog piece in the hand, and the grip `forest_mob_visual.gd` already
## authors for a bow on the warden's hand bone.
const BOW_ITEM := "bow_twig"

## The catalog ammunition the corpse gives back: the shafts a hidden archer was
## drawing from. The wood is where a band that ran its quiver dry re-supplies, and
## the body that was shooting at you is the one worth bending over.
const ARROW_ITEM := "arrow"
const CARRIED_ARROWS := 4

## The ring it holds: never inside this, never past that - and it retreats when a
## blade gets closer than the inner edge. The two numbers are what make fighting
## one a march up the trail instead of a scrum.
const HOLD_NEAR := 8.0
const HOLD_FAR := 16.0
const RETREAT_UNDER := 6.0
## An ambush is not a chase. The warden's own 3.6 m/s run made closing on one a
## footrace it always won; at two-thirds speed a walking body nearly holds it and
## a running body catches it. The sideways step is quieter again, so a body at
## the ring can actually line up a cut.
const MOVE_SCALE := 0.68
const STRAFE_SCALE := 0.70
## The farthest it will shoot: the outside edge of the hold band, so a body
## running the lane is only under fire while it is actually inside the ring.
const MAX_SHOT := 18.0
## The tree group it belongs to. Past this it walks home instead of following the
## squad down the lane - an archer is an ambush, not a hunter.
const LEASH := 13.0

## The cinder devil's bow, the one the frontier's own archers fire: 30 m/s with
## the arrow's own 4 m/s^2 drop, aimed a tenth of a second ahead. The release is
## the warden's stab clip's hold, stretched so a body can see the draw.
const ARROW_SPEED := 30.0
const ARROW_GRAVITY := 4.0
const LEAD_SECONDS := 0.12
const DRAW_SECONDS := 0.85
## The beat between two shafts. Three of these in one band is already a hard
## fight; it is the *number* of arrows, not one arrow's damage, that should hurt.
const COOLDOWN_SECONDS := 3.0
## What one shaft takes off, before the scene's `blow_scale` dial.
const ARROW_DAMAGE := 6.0
## The trail books a warden's blow under `escape_run.gd`'s WATCHER_SOURCE (91).
## The arrow carries the same id, so a death is attributed to the wood.
const DAMAGE_SOURCE := 91
## Terrain, the warband's bodies (layer 4) and the raised shield (layer 8).
## `enemy.gd`'s cinder devil uses this exact mask; a mob's body (layer 2) is not
## in it, so a shaft never hits the archer's own pack.
const HIT_MASK := 1 | 4 | 8

## Where the archer's group stands. The scene sets it through `set_anchor()`; the
## archer holds the ground around it and never hunts past `LEASH` from it.
var anchor := Vector3.ZERO
## The world scene, for `_keep_projectile()` so co-op clients see the shaft.
var host: Node3D = null
## Shafts this body has released, for the scene and the regression.
var shots_fired := 0
## True once the ambush is sprung; a hidden archer crouches and holds its fire.
var ambush_awake := false

var _retreat := 0.0
var _has_anchor := false


func _ready() -> void:
	# Before the parent's `_ready` reads them: the road's archers carry the
	# hardened pool, like every other road watcher, and the bow in their hand.
	health_pool = HARDENED_HEALTH
	weapon_item = BOW_ITEM
	super()
	# The numbers this body fights with are its own: a bow's reach is the ring,
	# not `profile.reach`, and the cooldown and draw are the arrow's clock.
	profile["damage"] = ARROW_DAMAGE
	profile["cooldown"] = COOLDOWN_SECONDS
	profile["windup"] = DRAW_SECONDS
	profile["sight"] = 40.0
	profile["strafe"] = 0.55
	weapon_item = BOW_ITEM
	_apply_weapon()
	_attack_cooldown = 0.4


## The group's post. Held as both the roam home and the leash centre.
func set_anchor(point: Vector3) -> void:
	anchor = point
	home = point
	_has_anchor = true


## Spring the ambush on `target`: the scene calls this on the whole group on the
## same frame. Idempotent, and refused by a dead body.
func begin_ambush(target: Node3D) -> void:
	if ambush_awake or not alive or not is_instance_valid(target):
		return
	ambush_awake = true
	_retreat = 0.0
	# A beat of reaction before the first draw: the group has to see the body.
	_attack_cooldown = 0.9
	hunt(target)


## The scene's marker: `escape_run.wake_road()` leaves the ambushers alone, so a
## group is only ever sprung by a body coming close or by a blow.
func is_ambusher() -> bool:
	return true


## A hidden archer is not handed a quarry. `world_scene` re-targets every guard
## within 55 m each frame, which would spring the ambush from the far end of the
## lane; the group's own poll and a landed blow are the only ways in. Once sprung,
## the base hunt applies unchanged.
func hunt(target: Node3D) -> void:
	if not ambush_awake:
		return
	super(target)


## A landed blow springs the group's mark even before the archer could see it.
func note_attacker(attacker: Node3D) -> void:
	ambush_awake = true
	super(attacker)


## A blow is a sighting: the body turns on whoever struck it, wherever it stands.
func take_damage(amount: float, source_id: int, headshot: bool = false) -> void:
	ambush_awake = true
	super(amount, source_id, headshot)


## A neighbour's cry inside earshot is a sighting too: an archer that answers one
## is no longer pretending to be a bush.
func hear_alert(attacker: Node3D, at: Vector3) -> void:
	ambush_awake = true
	super(attacker, at)


## The hidden stance: no quarry. `world_scene` stamps `player` on every guard
## within `AGGRO_RADIUS` every frame and the field cannot know better, so the body
## clears it itself until the ambush is sprung. The inherited tick still runs -
## gravity, the culler and the crouch all need it - but with no candidates it can
## never see the squad pass at twenty metres.
func _physics_process(delta: float) -> void:
	if not ambush_awake:
		player = null
		targets.clear()
	super(delta)


# --- the exchange ----------------------------------------------------------

## The hold. Inside its ring it stands its ground, steps around the quarry and
## looses when the cooldown is spent; inside `RETREAT_UNDER` it gives 3-6 m of
## ground first; past `HOLD_FAR` it walks in - but never past its own leash.
func _circle(delta: float, distance: float, direction: Vector3) -> void:
	if not is_instance_valid(_target):
		super(delta, distance, direction)
		return
	if not _senses.seen:
		# Losing the view is not losing the fight: walk the last sighting, still
		# inside the group's own leash.
		_hunt(delta)
		return
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var gap := to_target.length()
	var facing := to_target.normalized() if gap > 0.001 else direction
	_face_intent = facing
	# A squad that runs off down the trail is not chased: the group's own tree
	# line is the whole of its territory.
	if _has_anchor:
		var home_offset := anchor - global_position
		home_offset.y = 0.0
		if home_offset.length() > LEASH:
			_move_intent = _steer(home_offset.normalized())
			_move_speed = float(profile.run_speed) * MOVE_SCALE
			_face_intent = facing
			return
	if gap < RETREAT_UNDER and _retreat <= 0.0:
		# One beat of giving ground per close: 0.8-1.4 s at the run speed is the
		# 3-6 m the ring wants back.
		_retreat = _rng.randf_range(0.8, 1.4)
	if _retreat > 0.0:
		_retreat = maxf(0.0, _retreat - delta)
		var tangent := Vector3(-facing.z, 0.0, facing.x) * _strafe_dir
		_move_intent = _steer((-facing + tangent * 0.30).normalized())
		_move_speed = float(profile.run_speed) * MOVE_SCALE
		_face_intent = facing
		return
	if gap > HOLD_FAR:
		_move_intent = _steer(facing)
		_move_speed = float(profile.run_speed) * MOVE_SCALE
		return
	# Inside the band: step sideways across the quarry's front, slowly, and keep
	# the bow up. Nothing here walks into a blade.
	var tangent := Vector3(-facing.z, 0.0, facing.x) * _strafe_dir
	_move_intent = _steer(tangent * 0.55)
	_move_speed = float(profile.walk_speed) * 0.85 * STRAFE_SCALE
	if _attack_cooldown > 0.0 or gap > MAX_SHOT or not _senses.seen:
		return
	if not _shot_lane(_bow_origin()):
		# A trunk in the way: hold the shot and re-aim a beat later instead of
		# probing the wood sixty times a second.
		_attack_cooldown = 0.25
		return
	_choose_attack()
	_enter("WINDUP")


## The draw is the warden's stab clip, held for the whole telegraph.
func _choose_attack() -> void:
	if is_instance_valid(_visual):
		_visual.set_attack(SWING_STAB)


func _windup_seconds() -> float:
	return DRAW_SECONDS * maxf(0.0, windup_scale)


func _cooldown_seconds() -> float:
	return COOLDOWN_SECONDS * maxf(0.0, swing_gap_scale)


## What one shaft is worth. The scene's `blow_scale` still weights it.
func _strike_damage() -> float:
	return ARROW_DAMAGE * blow_scale


## The release. No `attacked` signal: an arrow owns its own hit, so emitting the
## melee blow as well would book the damage twice.
func _resolve_strike() -> void:
	if not is_instance_valid(_target) or not alive:
		return
	var origin := _bow_origin()
	if not _shot_lane(origin):
		return
	var aim := _target.global_position + Vector3(0.0, 1.0, 0.0) \
		+ _target.velocity * LEAD_SECONDS
	var flight := origin.distance_to(aim) / ARROW_SPEED
	# The arrow falls at 4 m/s^2; lift the aim by what it will drop over flight.
	aim.y += 0.5 * ARROW_GRAVITY * flight * flight
	var heading := (aim - origin).normalized()
	var parent := get_parent()
	if parent == null:
		return
	var arrow := ArrowScript.new()
	arrow.source_id = DAMAGE_SOURCE
	arrow.shooter = self
	arrow.hit_mask = HIT_MASK
	arrow.authoritative_damage = true
	parent.add_child(arrow)
	arrow.launch(origin, heading, ARROW_SPEED, _strike_damage(), [get_rid()], origin)
	# The world's list is what a co-op guest's replays read: one call, so a shaft
	# drawn on the host is drawn on every peer.
	if is_instance_valid(host) and host.has_method("_keep_projectile"):
		host._keep_projectile(arrow)
	shots_fired += 1


## Where the shaft leaves: chest height, a hand's width ahead of the body, on the
## line the bow hand actually holds.
func _bow_origin() -> Vector3:
	var aim_height := float(profile.get("aim", 1.72)) * body_scale()
	return global_position + Vector3(0.0, aim_height * 0.86, 0.0) \
		- global_basis.z * 0.45


## The bow only looses at what it can see: scenery blocks the line, but a
## packmate standing in it does not (the mask is terrain only).
func _shot_lane(origin: Vector3) -> bool:
	if not is_instance_valid(_target) or not is_inside_tree():
		return false
	var query := PhysicsRayQueryParameters3D.new()
	query.from = origin
	query.to = _target.global_position + Vector3(0.0, 1.0, 0.0)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## A lost sighting is not a licence to cross the map: the walk home is clamped to
## the group's post, and only inside it does the base pursuit hunt.
func _hunt(delta: float) -> void:
	if _has_anchor:
		var home_offset := anchor - global_position
		home_offset.y = 0.0
		if home_offset.length() > LEASH:
			_move_intent = _steer(home_offset.normalized())
			_move_speed = float(profile.run_speed) * MOVE_SCALE
			_face_intent = _move_intent
			return
	super(delta)


## The archer carries what it fires. The base body stamps the field dressing every
## warden wears (and its vial of ichor where the variant says so); an archer adds
## the quiver it was drawing from, so its corpse is ammunition as well as kit - the
## only resupply out on the road.
func _stamp_carried() -> void:
	super()
	for index in CARRIED_ARROWS:
		carried.append(ARROW_ITEM)


## The hidden stance: crouched until the ambush is sprung, and crouched again
## whenever the bow is re-arming. It stands for the draw itself.
func _present_crouch() -> bool:
	if not alive or state == "STAGGER":
		return false
	return not ambush_awake or _attack_cooldown > 0.0
