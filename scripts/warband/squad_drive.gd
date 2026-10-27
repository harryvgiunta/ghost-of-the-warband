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
		# 3. No fight: an escort closes up on the soul, a holding squad stands.
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
	if distance > reach:
		_advance(actor, watcher.global_position, track)
		return
	_hold(actor)
	if str(actor.rig.weapon) == "bow":
		if actor.combat.can_draw():
			actor.combat.begin_draw()
		elif float(actor.rig.draw_amount) >= 0.85:
			actor.combat.release_draw()
	elif float(actor.combat.clash_cooldown) <= 0.0:
		actor.combat.begin_melee()
		engaged = true


## Step toward `point`, or sideways for a moment when the body has been leaning
## on something it cannot pass. A wall or a trunk stops a shoulder-driven runner
## dead, and a squadmate pinned against the lane's edge would stand there for the
## rest of the run; one sidestep gets it round and back on the line.
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
	if not _track.has(merc_id):
		_track[merc_id] = {"last": actor.global_position, "stuck": 0.0, "side": 0.0, "sign": 1.0}
	var track: Dictionary = _track[merc_id]
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
