extends RefCounted
## The warband's side of a fight with the wood: one squad, one behaviour.
##
## The cage escape grew this AI inside the scene - a freed prisoner silently arms
## himself from the cultist steel on the ground and goes for the nearest watcher,
## and the player's own body is never driven. The escape run needs the same squad
## with one clause the cage never needed: the run has somewhere to be, so an ally
## with nothing to fight walks with the soul.
##
## Rather than fork that into a second copy, this module is the one
## implementation. Each scene owns an instance and hands in the facts only it
## knows:
##
##   * `eligible` - who is a squadmate on this frame. The cage answers with its
##     latches (a prisoner still in a cage is not free); the run answers with the
##     roster.
##   * `following` - whether an ally escorts the soul or holds its ground.
##   * `engage_radius` - how far an ally will pick a fight on its own. The cage
##     lets the squad cross the yard; the run keeps them near the soul.
##
## Everything the squad does is silent. Arming itself, taking a drop and swinging
## are the squad's business, not a feed to read; the warband contract forbids a
## loot step in the objective and forbids announcing pickups.

## Read-only sources the scene owns.
var controller
var warband
var loot
## Mercenary ids this scene fields as its squad.
var squad_ids: Array[int] = []
## Live arrays owned by the scene, shared by reference so a drop or a watcher
## spawned after setup is seen without a second call.
var watchers: Array = []
var pickups: Array = []

## The body the local soul is inside this frame. Never driven from here.
var player_body = null
## `merc_id -> bool`, defaulting to "every squad id is free".
var eligible := Callable()
var following := false
## How far behind the soul an escorting ally may fall before it closes up.
var follow_slack := 3.2
## Deterministic across runs: the rhythm looks unscripted without making a
## regression flaky.
var _rng := RandomNumberGenerator.new()
var _rng_seeded := false
var engage_radius := 60.0
## How close an ally must stand to swing.
var reach := 2.0
## How close an ally must be to take a drop off the ground.
var loot_reach := 1.5
## True for the rest of the scene once an ally has swung at a watcher.
var engaged := false
## How long an ally may push without moving before it sidesteps, and for how long
## that sidestep lasts.
const BLOCKED_SECONDS := 0.35
const SIDESTEP_SECONDS := 0.55
## How clear the field has to be before a squadmate bends over a corpse.
const LOOT_CLEAR_METRES := 22.0
## The pressure rhythm: this many swings, then a chance to break off, guard and
## walk the circle for a beat before coming back in. Circling is punctuation, not
## a stance - a squad that only ever circles is a squad getting hit.
const SWINGS_BEFORE_CIRCLE := 3
const CIRCLE_CHANCE := 0.35
const CIRCLE_MIN := 0.6
const CIRCLE_MAX := 1.2

## per merc_id: {last, stuck, side, sign}
var _track: Dictionary = {}


## Point the module at a warband and the controller that owns its bodies.
func setup(warband_state, soul_controller, loot_vacuum) -> void:
	warband = warband_state
	controller = soul_controller
	loot = loot_vacuum


## One frame of squad intent. Called before `controller.physics_step` so the
## brains have written a body's intent for the tick that integrates it.
func drive(delta: float) -> void:
	if controller == null or warband == null:
		return
	player_body = controller.active_body(1)
	for raw_id in squad_ids:
		var merc_id := int(raw_id)
		if not _is_free(merc_id):
			continue
		var actor = controller.body_of(merc_id)
		if actor == null or not is_instance_valid(actor):
			continue
		# The soul's own body is the player's business, never the AI's.
		if actor == player_body:
			continue
		if not bool(actor.get("alive")) or bool(actor.get("downed")):
			_hold(actor)
			continue
		actor.combat.damage_enabled = true
		var track := _track_for(merc_id, actor, delta)
		# 1. An unarmed ally looks for steel first: the steel is how a prisoner
		#    becomes a fighter, not a buff the scene hands out.
		if not _armed(actor, merc_id):
			var pickup = _nearest_pickup(actor)
			if pickup != null:
				if actor.global_position.distance_to(pickup.global_position) <= loot_reach:
					_hold(actor)
					_take(actor, merc_id, pickup)
				else:
					_advance(actor, pickup.global_position, track)
				continue
		# 2. Armed, or nothing left to grab: go at the nearest watcher.
		var watcher = _nearest_watcher(actor)
		if watcher != null:
			_fight(actor, watcher, track)
			continue
		# 3. Nothing hostile close: check the bodies. A squad strips the field when
		#    the fighting has stopped, never mid-swing.
		if _clear_of_hostiles(actor):
			var spoil = _nearest_pickup(actor)
			if spoil != null:
				if actor.global_position.distance_to(spoil.global_position) <= loot_reach:
					_hold(actor)
					_take(actor, merc_id, spoil)
				else:
					_advance(actor, spoil.global_position, track)
				continue
		# 4. No fight: an escort closes up on the soul, a holding squad stands.
		if following and is_instance_valid(player_body):
			var gap: Vector3 = player_body.global_position - actor.global_position
			gap.y = 0.0
			if gap.length() > follow_slack:
				_advance(actor, player_body.global_position, track)
				continue
		_hold(actor)


## How many free squadmates are actually holding something. The roster alone is
## not the answer: a body can outlive the gear the roster says it wears.
func armed_count() -> int:
	if controller == null or warband == null:
		return 0
	var count := 0
	var soul_body = controller.active_body(1)
	for raw_id in squad_ids:
		var merc_id := int(raw_id)
		if not _is_free(merc_id):
			continue
		var actor = controller.body_of(merc_id)
		if actor == null or not is_instance_valid(actor):
			continue
		if actor == soul_body or not bool(actor.get("alive")):
			continue
		var gear: Dictionary = warband.roster.equipped_of(merc_id)
		var in_roster := not str(gear.get("main", "")).is_empty() \
			or not str(gear.get("off", "")).is_empty()
		if in_roster and _holds_weapon(actor):
			count += 1
	return count


## Point every living watcher at the nearest standing squad body and put it on
## the hunt. Shared because a watcher that has calmed down is a scene bug in both
## the camp and the run, and the answer is the same in both.
##
## `radius` bounds how far a watcher will take a *new* target. In the one world
## the camp's guards, the six that come out of the trees and the road's cultists
## all live on one list, so without a bound a watcher in the clearing would run
## the whole 286 m of trail after a squad that had already left it - and the
## road's cultists would come up to the town to fight. A watcher already hunting
## is left alone: this only decides who it notices.
static func retarget(watchers: Array, bodies: Array, radius: float = INF) -> void:
	for watcher in watchers:
		if not is_instance_valid(watcher) or not bool(watcher.get("alive")):
			continue
		var nearest = null
		var best := INF
		for body in bodies:
			if not is_instance_valid(body) or not bool(body.get("alive")):
				continue
			if bool(body.get("downed")):
				continue
			var distance: float = body.global_position.distance_to(watcher.global_position)
			if distance < best:
				best = distance
				nearest = body
		if nearest == null:
			continue
		if radius < INF and watcher.global_position.distance_to(nearest.global_position) > radius:
			continue
		watcher.player = nearest
		# `hunt` only re-arms the senses when the pursuit lapsed, so calling it
		# every frame never resets a watcher that is already running somebody down.
		if not bool(watcher.hunting()):
			watcher.hunt(nearest)


# --- answers ---------------------------------------------------------------

func _is_free(merc_id: int) -> bool:
	if merc_id <= 0:
		return false
	if not eligible.is_valid():
		return true
	return bool(eligible.call(merc_id))


## Whether the body is actually swinging something: the rig, not the roster. A
## body whose roster says armed but whose hands are empty is wearing a stale
## loadout, so it is re-dressed once instead of being written off as unarmed.
func _armed(actor, merc_id: int) -> bool:
	var gear: Dictionary = warband.roster.equipped_of(merc_id)
	var roster_armed := not str(gear.get("main", "")).is_empty() \
		or not str(gear.get("off", "")).is_empty()
	if roster_armed and not _holds_weapon(actor):
		controller.refresh_gear(merc_id)
	return roster_armed and _holds_weapon(actor)


func _holds_weapon(actor) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	if str(actor.rig.weapon) in ["sword", "dagger", "dual", "bow"]:
		return true
	return bool(actor.rig.staff_active) or bool(actor.rig.off_weapon_active)


func _nearest_pickup(actor):
	var best = null
	var best_distance := 40.0
	for pickup in pickups:
		if not is_instance_valid(pickup) or bool(pickup.collected):
			continue
		var distance: float = actor.global_position.distance_to(pickup.global_position)
		if distance < best_distance:
			best_distance = distance
			best = pickup
	return best


## True when no living cultist is close enough to interrupt a body bending over a
## corpse. `LOOT_CLEAR_METRES` is wider than the reach, so a squad does not strip
## gear in the middle of a ring.
func _clear_of_hostiles(actor) -> bool:
	for watcher in watchers:
		if not is_instance_valid(watcher) or not bool(watcher.get("alive")):
			continue
		if actor.global_position.distance_to(watcher.global_position) <= LOOT_CLEAR_METRES:
			return false
	return true


func _nearest_watcher(actor):
	var best = null
	var best_distance := engage_radius
	for watcher in watchers:
		if not is_instance_valid(watcher) or not bool(watcher.get("alive")):
			continue
		var distance: float = actor.global_position.distance_to(watcher.global_position)
		if distance < best_distance:
			best_distance = distance
			best = watcher
	return best


# --- intent ----------------------------------------------------------------

func _fight(actor, watcher, track: Dictionary) -> void:
	var to: Vector3 = watcher.global_position - actor.global_position
	to.y = 0.0
	var distance := to.length()
	actor.combat.set_aim(watcher.get_aim_position())
	# Nothing circles: the squad walks into the cult and stays on it. A body that
	# steps back and forth while a cultist hits it reads as a spectator, and the
	# squad's job is to be the reason the player is not alone in here.
	if distance > reach * 0.92:
		actor.combat.stop_block()
		_advance(actor, watcher.global_position, track)
		return
	if str(actor.rig.weapon) == "bow":
		_hold(actor)
		if actor.combat.can_draw():
			actor.combat.begin_draw()
		elif float(actor.rig.draw_amount) >= 0.85:
			actor.combat.release_draw()
		return
	# A break-off beat: guard up, walk the circle, come back in. It happens after a
	# few swings and not every time, so it reads as a fighter resetting rather than
	# as a body that will not fight.
	if float(track.get("circle", 0.0)) > 0.0:
		actor.combat.start_block(to.normalized())
		_circle(actor, to, track)
		return
	# The rhythm of a fight: swing the moment the blade is free, and hold the guard
	# in the gap rather than standing in the open taking the counter.
	if float(actor.combat.clash_cooldown) <= 0.0:
		actor.combat.stop_block()
		# A dagger swings its stab, not the overhead chop: that is the variant the
		# item's own passive speeds up (Prison shank, +200%), and it is what makes
		# a shiv a shiv. Every other blade keeps the overhead.
		var variant := "stab" if str(actor.rig.weapon) == "dagger" else "overhead"
		actor.combat.begin_melee("right", variant)
		engaged = true
		track["swings"] = int(track.get("swings", 0)) + 1
		if int(track["swings"]) >= SWINGS_BEFORE_CIRCLE and _rng.randf() < CIRCLE_CHANCE:
			track["swings"] = 0
			track["circle"] = _rng.randf_range(CIRCLE_MIN, CIRCLE_MAX)
		return
	actor.combat.start_block(to.normalized())
	# Walk the last half metre in while the guard is up: pressure, not orbiting.
	if distance > reach * 0.55:
		_advance(actor, watcher.global_position, track)
	else:
		_hold(actor)


func _advance(actor, point: Vector3, track: Dictionary) -> void:
	var to: Vector3 = point - actor.global_position
	to.y = 0.0
	if to.length_squared() <= 0.0001:
		_hold(actor)
		return
	var direction := to.normalized()
	if float(track.get("side", 0.0)) > 0.0:
		direction = direction.cross(Vector3.UP) * float(track.get("sign", 1.0))
	actor.accept_network_input(Vector2(direction.x, direction.z), true)


## Blocked-detection for one ally: how long it has been pushing without moving,
## and the remainder of a sidestep once it starts one. The sign alternates, so a
## body caught between two things tries both ways round instead of one forever.
func _track_for(merc_id: int, actor, delta: float) -> Dictionary:
	if not _rng_seeded:
		_rng_seeded = true
		_rng.seed = 9173
	if not _track.has(merc_id):
		_track[merc_id] = {"last": actor.global_position, "stuck": 0.0, "side": 0.0,
			"sign": 1.0, "swings": 0, "circle": 0.0}
	var track: Dictionary = _track[merc_id]
	track["circle"] = maxf(0.0, float(track.get("circle", 0.0)) - delta)
	var moved: float = actor.global_position.distance_to(track["last"])
	track["last"] = actor.global_position
	var wanted: bool = Vector2(actor.move_direction).length_squared() > 0.01
	track["stuck"] = float(track["stuck"]) + delta if wanted and moved < 0.02 else 0.0
	track["side"] = maxf(0.0, float(track["side"]) - delta)
	if float(track["stuck"]) >= BLOCKED_SECONDS and float(track["side"]) <= 0.0:
		track["stuck"] = 0.0
		track["side"] = SIDESTEP_SECONDS
		track["sign"] = -float(track["sign"])
	return track


func _hold(actor) -> void:
	actor.accept_network_input(Vector2.ZERO, false)


## Walk a half-step around the target. Every third ally takes the other way, so a
## squad of three does not orbit in lockstep.
func _circle(actor, to: Vector3, track: Dictionary) -> void:
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length_squared() < 0.0001:
		return
	var side := float(track.get("circle_side", 0.0))
	if is_zero_approx(side):
		side = 1.0 if actor.get_instance_id() % 2 == 0 else -1.0
		track["circle_side"] = side
	var across: Vector3 = flat.normalized().cross(Vector3.UP) * side
	actor.accept_network_input(Vector2(across.x, across.z), false)


## A squadmate takes a drop for themselves: the vacuum books the piece into the
## shared stash and the body wears it, because the player's pickup rule would arm
## the soul instead. Silent on purpose.
func _take(actor, merc_id: int, pickup) -> void:
	if loot == null:
		return
	var item_id := str(pickup.item_id)
	var result: Dictionary = loot.quick_loot(pickup, 0)
	if not bool(result.get("ok", false)):
		return
	warband.auto_equip(merc_id, item_id)
	controller.refresh_gear(merc_id)
	actor.combat.stop()
