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
##
## The fight itself is the ranger clones' rhythm with the guard made honest, and
## with every frame accounted for: an ally inside `engage_radius` is closing,
## swinging, holding a short guard window, taking a few steps off the line, or
## re-forming for the next blow. There is no fifth answer, so a body with a
## hostile in reach can never fall back to standing still.

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
## How close an ally must be to take a drop off the ground, or to bend over a
## fallen body.
var loot_reach := 1.5
## True for the rest of the scene once an ally has swung at a watcher.
var engaged := false
## How long an ally may push without moving before it sidesteps, and for how long
## that sidestep lasts.
const BLOCKED_SECONDS := 0.35
const SIDESTEP_SECONDS := 0.55
## How clear the field has to be before a squadmate bends over a corpse.
const LOOT_CLEAR_METRES := 22.0
## How far an ally looks for steel on the ground or a body worth stripping. Wider
## than the walk-in reach: a squad crosses the clearing for a blade.
const SEARCH_METRES := 40.0

## The fight ladder. Every frame a body spends with a hostile in range resolves
## to one of these, which is what keeps a squadmate from falling through to a
## held body while there is still something to kill.
const FIGHT_CLOSE := 0   ## walking onto the target, blade down
const FIGHT_SWING := 1   ## the blow on this frame
const FIGHT_GUARD := 2   ## a rolled guard window, shuffling in
const FIGHT_CIRCLE := 3  ## a few short steps off the line
const FIGHT_RESET := 4   ## the beat between exchanges: no guard, closing again

## The guard is a window, never a stance: the chance is rolled fresh for every
## exchange and the window is shorter than the rhythm it sits in, so an ally
## never spends the whole fight behind a raised blade.
const GUARD_CHANCE_MIN := 0.55
const GUARD_CHANCE_MAX := 0.70
const GUARD_MIN := 0.35
const GUARD_MAX := 0.80

## A circle is punctuation, not a stance: after 1-3 swings a body may take a few
## short steps off the line, each rolled with its own direction and length, and
## then lunge back in for the next blow.
const SWINGS_MIN := 1
const SWINGS_MAX := 3
const CIRCLE_CHANCE := 0.5
const CIRCLE_MIN := 0.25
const CIRCLE_MAX := 0.55
const STEP_MIN := 0.12
const STEP_MAX := 0.20
## How often a step reverses a body's whole direction of travel.
const CIRCLE_REVERSE := 0.30
const CIRCLE_LATERAL_MIN := 0.55
const CIRCLE_LATERAL_MAX := 1.0
const CIRCLE_BACK_MIN := 0.25
const CIRCLE_BACK_MAX := 0.55

## The shuffle a body keeps while it holds a guard or re-forms after an exchange:
## enough movement that it reads as working the angle rather than standing still.
const GUARD_CLOSE := 0.55
const GUARD_SHUFFLE := 0.30
const RESET_CLOSE := 0.60
const RESET_SHUFFLE := 0.40

## Clocks that run down for every ally, whatever it is doing this frame.
const TRACK_CLOCKS := ["state_left", "step_left", "side"]

## What a body can swing, and the narrower pair that can also set a guard. What a
## hand can hold at all is the union plus a bow, which the squad's `_armed` test
## asks before anything else.
const BLADES := ["sword", "dagger", "dual"]
const GUARD_BLADES := ["sword", "dagger"]
const HELD_WEAPONS := ["sword", "dagger", "dual", "bow"]
## The two phases in which a bow's string is up.
const DRAW_PHASES := ["DRAWING", "HOLDING"]

## per merc_id: the blocked push, the current fight state, and this body's own
## rolls. Nothing here is read off the instance id: two allies in the same gear
## circle on different beats because each rolled for itself.
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
		if _clear_of_hostiles(actor.global_position):
			var spoil = _nearest_pickup(actor)
			if spoil != null:
				if actor.global_position.distance_to(spoil.global_position) <= loot_reach:
					_hold(actor)
					_take(actor, merc_id, spoil)
				else:
					_advance(actor, spoil.global_position, track)
				continue
			var fallen := _nearest_corpse(actor)
			# The body has to be clear in its own right, not just the body
			# walking to it: the rule is about the fight near the corpse.
			if fallen != 0 and loot.has_corpse(fallen):
				var at: Vector3 = loot.corpse_position(fallen)
				if _clear_of_hostiles(at):
					if actor.global_position.distance_to(at) <= loot_reach:
						_hold(actor)
						_claim(fallen)
					else:
						_advance(actor, at, track)
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
## all live on one list, so without a bound a watcher in the camp would run the
## whole nine hundred metres of trail after a squad that had already left it - and
## the road's cultists would come up to the town to fight. A watcher already hunting
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
	if str(actor.rig.weapon) in HELD_WEAPONS:
		return true
	return bool(actor.rig.staff_active) or bool(actor.rig.off_weapon_active)


## Whether a blow could start on this frame: the same gate `Combat.begin_melee`
## applies, asked *before* the exchange is rolled so a body still recovering is
## never handed a guard window it did not earn.
func _blade_free(actor) -> bool:
	if str(actor.rig.weapon) not in BLADES:
		return false
	return float(actor.combat.clash_cooldown) <= 0.0 \
		and float(actor.combat.attack_progress) >= 0.999 \
		and bool(actor.rig.can_begin_melee("right"))


## Only a blade can set a guard: `Combat.start_block` refuses a bow, a staff and a
## dual pair, so a body that cannot guard never spends an exchange on one.
func _can_guard(actor) -> bool:
	return str(actor.rig.weapon) in GUARD_BLADES


func _nearest_pickup(actor):
	var best = null
	var best_distance := SEARCH_METRES
	for pickup in pickups:
		if not is_instance_valid(pickup) or bool(pickup.collected):
			continue
		var distance: float = actor.global_position.distance_to(pickup.global_position)
		if distance < best_distance:
			best_distance = distance
			best = pickup
	return best


## The nearest fallen body this ally may search, or 0 for none. The vacuum holds
## the bodies a scene registered (`register_corpse`) and stops offering one it has
## already been emptied, so the module asks it rather than keeping corpses of its
## own - and a scene whose vacuum predates `claim_corpse` simply has nothing to
## offer, which leaves the squad's fight and escort untouched.
func _nearest_corpse(actor) -> int:
	if loot == null or not loot.has_method("claim_corpse"):
		return 0
	return int(loot.corpse_at(actor.global_position, SEARCH_METRES))


## True when no living cultist is close enough to interrupt a body bending over a
## corpse. `LOOT_CLEAR_METRES` is wider than the reach, so a squad does not strip
## gear in the middle of a ring. Measured at the thing being looted - the drop or
## the body - because that is where the fight would have to be over.
func _clear_of_hostiles(point: Vector3) -> bool:
	for watcher in watchers:
		if not is_instance_valid(watcher) or not bool(watcher.get("alive")):
			continue
		if point.distance_to(watcher.global_position) <= LOOT_CLEAR_METRES:
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
	var direction := to.normalized() if distance > 0.001 else Vector3.FORWARD
	actor.combat.set_aim(watcher.get_aim_position())
	var state := int(track.get("state", FIGHT_CLOSE))
	var left := float(track.get("state_left", 0.0))
	# A window that is still running is what the body is doing this frame. A
	# circle keeps its steps even when they carry the body just outside reach:
	# cutting it short is what made a break-off read as a stumble.
	if state == FIGHT_CIRCLE and left > 0.0:
		_circle_step(actor, direction, track)
		return
	# A guard holds from slightly beyond reach too - a body does not drop its
	# blade the instant its target steps back - but a target that has broken
	# clean away is a chase, and a chase is not shielded.
	if state == FIGHT_GUARD and left > 0.0 and distance <= reach * 1.35:
		_guard_step(actor, direction, track)
		return
	# A window that has run out is the body's own signal to attack: the guard
	# drops to the swing, and a circle ends in the lunge back in.
	if state == FIGHT_GUARD or state == FIGHT_CIRCLE:
		actor.combat.stop_block()
		track["swing_due"] = true
	# Out of reach there is nothing to strike: close in, blade down.
	if distance > reach * 0.92:
		_enter(track, FIGHT_CLOSE)
		actor.combat.stop_block()
		_advance(actor, watcher.global_position, track)
		return
	if str(actor.rig.weapon) == "bow":
		_fight_bow(actor, track, direction)
		return
	# An exchange this body has already rolled and not yet landed: swing the
	# moment the blade is free. Re-rolling here is how a body that cannot swing
	# this frame ends up guarding forever.
	if not bool(track.get("swing_due", false)) and _blade_free(actor):
		_roll_exchange(actor, track)
		var rolled := int(track.get("state", FIGHT_CLOSE))
		if not bool(track.get("swing_due", false)) and rolled == FIGHT_GUARD:
			# Show the window on the frame it opens, so a guard is never an
			# invisible state that only exists in a timer.
			_guard_step(actor, direction, track)
			return
		if not bool(track.get("swing_due", false)) and rolled == FIGHT_CIRCLE:
			_circle_step(actor, direction, track)
			return
	if _swing(actor, track, direction):
		return
	_enter(track, FIGHT_CLOSE)
	actor.combat.stop_block()
	_close_step(actor, direction, track)


## What this exchange is, rolled once at the moment the blade comes free, which is
## the only moment the choice costs anything. A guard is drawn with a fresh chance
## every exchange - never a cooldown-gated certainty - and the blow is never
## withheld, only delayed by the short window it was rolled behind.
func _roll_exchange(actor, track: Dictionary) -> void:
	if _can_guard(actor) and _rng.randf() < _rng.randf_range(GUARD_CHANCE_MIN, GUARD_CHANCE_MAX):
		_enter(track, FIGHT_GUARD, _rng.randf_range(GUARD_MIN, GUARD_MAX))
		return
	if int(track.get("swings_left", 0)) <= 0:
		track["swings_left"] = _rng.randi_range(SWINGS_MIN, SWINGS_MAX)
		if _rng.randf() < CIRCLE_CHANCE:
			_begin_circle(track)
			return
	track["swing_due"] = true


## The blow itself. False means the blade was not free this frame, so the caller
## keeps the body moving instead of pretending a swing happened.
func _swing(actor, track: Dictionary, direction: Vector3) -> bool:
	if not _blade_free(actor):
		return false
	# A dagger swings its stab, not the overhead chop: that is the variant the
	# item's own passive speeds up (Prison shank, +200%), and it is what makes
	# a shiv a shiv. Every other blade keeps the overhead.
	var variant := "stab" if str(actor.rig.weapon) == "dagger" else "overhead"
	actor.combat.stop_block()
	if not actor.combat.begin_melee("right", variant):
		return false
	engaged = true
	track["swing_due"] = false
	track["swings_left"] = int(track.get("swings_left", 0)) - 1
	_enter(track, FIGHT_SWING)
	# The swing is a step as well as a cut: the body keeps its weight going in
	# rather than cutting from a standstill.
	_steer(actor, direction, track, false)
	return true


## A bow cannot guard and cannot swing, so it keeps the draw/hold/release path and
## spends the beat between shots on a step. Only a string that is up plants the
## feet: a draw cannot be rushed.
func _fight_bow(actor, track: Dictionary, direction: Vector3) -> void:
	if actor.combat.can_draw():
		_enter(track, FIGHT_SWING)
		_hold(actor)
		actor.combat.begin_draw()
		return
	if str(actor.rig.phase) in DRAW_PHASES or float(actor.rig.draw_amount) > 0.0:
		_enter(track, FIGHT_SWING)
		_hold(actor)
		if float(actor.rig.draw_amount) >= 0.85:
			actor.combat.release_draw()
		return
	# The beat between shots is the same short steps a blade's circle uses, but it
	# is not a circle: a bow is never breaking off, so it must not leave a window
	# clock behind for the melee ladder to read.
	_enter(track, FIGHT_RESET)
	_circle_step(actor, direction, track)


## A break-off beat: a quarter to a half second of steps, each with its own
## direction and length, then the body lunges back in on the target for its next
## blow - the clear-distance check above turns the end of the circle into a run.
func _begin_circle(track: Dictionary) -> void:
	_enter(track, FIGHT_CIRCLE, _rng.randf_range(CIRCLE_MIN, CIRCLE_MAX))
	_roll_step(track)


## One step of a circle. A reversal is possible on any step but is not the norm: a
## body that flips every step reads as a glitch, one that never does reads as a
## script.
func _roll_step(track: Dictionary) -> void:
	var orbit := float(track.get("orbit", 1.0))
	if _rng.randf() < CIRCLE_REVERSE:
		orbit = -orbit
	track["orbit"] = orbit
	track["lateral"] = _rng.randf_range(CIRCLE_LATERAL_MIN, CIRCLE_LATERAL_MAX)
	track["back"] = _rng.randf_range(CIRCLE_BACK_MIN, CIRCLE_BACK_MAX)
	track["step_left"] = _rng.randf_range(STEP_MIN, STEP_MAX)


## Sideways with a backward bias, re-rolled every step, so the path is rugged and
## very short instead of an orbit.
func _circle_step(actor, direction: Vector3, track: Dictionary) -> void:
	if float(track.get("step_left", 0.0)) <= 0.0:
		_roll_step(track)
	var across := direction.cross(Vector3.UP) * float(track.get("orbit", 1.0))
	var intent := across * float(track.get("lateral", 0.7)) \
		- direction * float(track.get("back", 0.35))
	_steer(actor, intent, track, false)


## The guard window: up, pointed at the target, and the body still walking its
## angle in. The block is raised once and dropped by the swing that follows.
func _guard_step(actor, direction: Vector3, track: Dictionary) -> void:
	if not actor.combat.blocking:
		actor.combat.start_block(direction)
	actor.combat.face_block(direction)
	var across := direction.cross(Vector3.UP) * float(track.get("orbit", 1.0))
	_steer(actor, direction * GUARD_CLOSE + across * GUARD_SHUFFLE, track, false)


## The beat between exchanges with no guard up: close the gap on an angle, so the
## body never stands inside its own reach waiting for the blade.
func _close_step(actor, direction: Vector3, track: Dictionary) -> void:
	var across := direction.cross(Vector3.UP) * float(track.get("orbit", 1.0))
	_steer(actor, direction * RESET_CLOSE + across * RESET_SHUFFLE, track, false)


## Put the body in a fight state, with the window it holds when the state has one.
func _enter(track: Dictionary, state: int, seconds: float = 0.0) -> void:
	track["state"] = state
	track["state_left"] = seconds


func _advance(actor, point: Vector3, track: Dictionary) -> void:
	var to: Vector3 = point - actor.global_position
	to.y = 0.0
	if to.length_squared() <= 0.0001:
		_hold(actor)
		return
	# Walking is not fighting: a guard left up while crossing the yard to a drop
	# would be a pose nobody set.
	actor.combat.stop_block()
	_steer(actor, to.normalized(), track, true)


## One intent write for every kind of movement the squad makes. A body whose push
## is going nowhere takes the sidestep instead, so a squadmate caught on a wall
## tries both ways round rather than shouldering it for the rest of the fight.
func _steer(actor, direction: Vector3, track: Dictionary, running: bool) -> void:
	if float(track.get("side", 0.0)) > 0.0:
		direction = direction.cross(Vector3.UP) * float(track.get("sign", 1.0))
	actor.accept_network_input(Vector2(direction.x, direction.z).limit_length(), running)


## Blocked-detection for one ally, plus the fight clocks and this body's own rolls.
## Everything here is per mercenary: two allies in the same gear still circle on
## different beats because neither side is read off an id.
func _track_for(merc_id: int, actor, delta: float) -> Dictionary:
	if not _rng_seeded:
		_rng_seeded = true
		# Fixed, never the wall clock: a scene replays the same rhythm and a
		# regression that fails does so for a reason.
		_rng.seed = 9173
	if not _track.has(merc_id):
		_track[merc_id] = {"last": actor.global_position, "stuck": 0.0, "side": 0.0,
			"sign": 1.0, "state": FIGHT_CLOSE, "state_left": 0.0, "step_left": 0.0,
			"swings_left": 0, "swing_due": false,
			"orbit": 1.0 if _rng.randf() < 0.5 else -1.0, "lateral": 0.7, "back": 0.35}
	var track: Dictionary = _track[merc_id]
	for key in TRACK_CLOCKS:
		track[key] = maxf(0.0, float(track.get(key, 0.0)) - delta)
	var moved: float = actor.global_position.distance_to(track["last"])
	track["last"] = actor.global_position
	var wanted: bool = Vector2(actor.move_direction).length_squared() > 0.01
	track["stuck"] = float(track["stuck"]) + delta if wanted and moved < 0.02 else 0.0
	if float(track["stuck"]) >= BLOCKED_SECONDS and float(track["side"]) <= 0.0:
		track["stuck"] = 0.0
		track["side"] = SIDESTEP_SECONDS
		track["sign"] = -float(track["sign"])
	return track


func _hold(actor) -> void:
	actor.combat.stop_block()
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


## Book a fallen body's gear into the shared stash. The vacuum walks it as the
## squad's own silent sweep (peer 0: no soul's hands are involved) and the scene
## re-dresses the body; nothing here touches the paperdoll, and nothing is
## announced. The body itself forgets each piece as it is booked, so a corpse is
## offered once and then stops being a target - no bookkeeping of ours.
func _claim(corpse_id: int) -> void:
	loot.claim_corpse(corpse_id, 0)
