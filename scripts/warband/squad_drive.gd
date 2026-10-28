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
## Where a body stops walking into what it is fighting. Blades are 1.15-2.3 m
## long, so a fighter that keeps pressing forward is inside the mob's own capsule
## long before its swing lands - and a squad that leans on a body shoves it across
## the field. An ally closes to this and no further, and backs off when the press
## has carried it inside `MIN_GAP`.
const STANDOFF := 1.45
const MIN_GAP := 0.95
## Past this gap a body jogs; inside it, it walks in. A wolf-trot into contact is
## what made the squad read as a bulldozer.
const RUN_GAP := 7.0
## True for the rest of the scene once an ally has swung at a watcher.
var engaged := false
## A hurt ally binds its wounds once the field is quiet: the bandage is a catalog
## piece in the shared stash, taken by the squad like any other loot.
const BANDAGE_ITEM := "bandage_linen"
const BANDAGE_SECONDS := 1.8
## Health below this share is worth a bandage; above it the squad keeps its
## dressings for after the fight.
const BANDAGE_HEALTH_SHARE := 0.7
## What one bandage closes, as a share of the body's own pool.
const BANDAGE_HEAL_SHARE := 0.3
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

## Clocks that run down for every ally, whatever it is doing this frame. The
## dressing clock is one of them: a bandage takes its seconds wherever the body
## is, and the channel is abandoned by walking the enemy check, not by a timer
## that keeps running behind a fight.
const TRACK_CLOCKS := ["state_left", "step_left", "side", "heal_left"]

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
		# 0. A hurt ally binds its wounds when nothing is close enough to punish
		#    it. The channel is the squad's own: no announcement, no prompt.
		if _bandage_step(actor, merc_id, track, delta):
			continue
		# 1. An unarmed ally looks for steel first: the steel is how a prisoner
		#    becomes a fighter, not a buff the scene hands out. A weapon on the
		#    ground is worth the walk; a rag or a ring is not.
		if not _armed(actor, merc_id):
			var steel = _nearest_weapon_pickup(actor)
			if steel != null:
				if actor.global_position.distance_to(steel.global_position) <= loot_reach:
					_hold(actor)
					_take(actor, merc_id, steel)
				else:
					_advance(actor, steel.global_position, track, loot_reach)
				continue
			var armed_body := _nearest_corpse_with_weapon(actor)
			if armed_body != 0:
				var held_at: Vector3 = loot.corpse_position(armed_body)
				if _clear_of_hostiles(held_at):
					if actor.global_position.distance_to(held_at) <= loot_reach:
						_hold(actor)
						_strip_weapon(actor, merc_id, armed_body)
					else:
						_advance(actor, held_at, track, loot_reach)
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
					_advance(actor, spoil.global_position, track, loot_reach)
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
						_advance(actor, at, track, loot_reach)
					continue
		# 4. No fight: an escort closes up on the soul, a holding squad stands.
		if following and is_instance_valid(player_body):
			var gap: Vector3 = player_body.global_position - actor.global_position
			gap.y = 0.0
			if gap.length() > follow_slack:
				_advance(actor, player_body.global_position, track, follow_slack)
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


## The nearest piece on the ground that could actually be a weapon. An unarmed
## ally is not walking across a clearing for a rag, a ring or a bundle: those are
## the stash's business and somebody else's walk.
func _nearest_weapon_pickup(actor):
	var best = null
	var best_distance := SEARCH_METRES
	for pickup in pickups:
		if not is_instance_valid(pickup) or bool(pickup.collected):
			continue
		if not WarbandPickup.is_weapon(str(pickup.item_id)):
			continue
		var distance: float = actor.global_position.distance_to(pickup.global_position)
		if distance < best_distance:
			best_distance = distance
			best = pickup
	return best


## The nearest body still carrying a weapon in its own record, or 0. A corpse
## registers the kit it fell with, so a watcher that was killed before this
## module existed still has steel on it.
func _nearest_corpse_with_weapon(actor) -> int:
	if loot == null or not loot.has_method("corpse_items"):
		return 0
	var best := 0
	var best_distance := SEARCH_METRES
	for corpse_id in loot.corpse_ids():
		var id := int(corpse_id)
		var has_weapon := false
		for item_id in loot.corpse_items(id):
			if WarbandPickup.is_weapon(str(item_id)):
				has_weapon = true
				break
		if not has_weapon:
			continue
		var distance: float = actor.global_position.distance_to(loot.corpse_position(id))
		if distance < best_distance:
			best_distance = distance
			best = id
	return best


## Take only the blade off a body - the rag and the rest stay on it for whoever
## searches it properly - and wear it. The piece is booked into the shared stash
## first, exactly as every take is, so the warband's worth never disagrees.
func _strip_weapon(actor, merc_id: int, corpse_id: int) -> void:
	if loot == null or not loot.has_method("take_from_corpse"):
		return
	for item_id in loot.corpse_items(corpse_id):
		var id := str(item_id)
		if not WarbandPickup.is_weapon(id):
			continue
		var result: Dictionary = loot.take_from_corpse(corpse_id, id, 0)
		if not bool(result.get("ok", false)):
			continue
		warband.auto_equip(merc_id, id)
		controller.refresh_gear(merc_id)
		actor.combat.stop()
		return


# --- field medicine --------------------------------------------------------

## One frame of a hurt ally's own dressing. Answers true when the bandage owns
## this frame's intent: the channel has just started, is still running, or has
## just closed a wound. A hostile inside `LOOT_CLEAR_METRES` drops the work
## unfinished, and the dressing stays in the stash because it was never used.
func _bandage_step(actor, merc_id: int, track: Dictionary, _delta: float) -> bool:
	if bool(track.get("bandaging", false)):
		if not _clear_of_hostiles(actor.global_position):
			# Interrupted: nothing was spent.
			track["bandaging"] = false
			track["heal_left"] = 0.0
			return false
		if float(track.get("heal_left", 0.0)) > 0.0:
			_hold(actor)
			return true
		track["bandaging"] = false
		_finish_bandage(actor, merc_id)
		return false
	if not _wants_bandage(actor, merc_id):
		return false
	if not _clear_of_hostiles(actor.global_position):
		return false
	track["bandaging"] = true
	track["heal_left"] = BANDAGE_SECONDS
	_hold(actor)
	actor.combat.stop()
	return true


## Hurt enough to spend a dressing, holding a body that can still be saved, with
## one in the shared stash to spend.
func _wants_bandage(actor, merc_id: int) -> bool:
	if warband == null or warband.stash == null:
		return false
	if int(warband.stash.pooled_count(BANDAGE_ITEM)) <= 0:
		return false
	if not warband.roster.is_alive(merc_id):
		return false
	var pool := float(actor.get("max_health"))
	if pool <= 0.0:
		return false
	return float(actor.get("health")) < pool * BANDAGE_HEALTH_SHARE


## Close the wound: the dressing leaves the stash, the body gets its share of its
## own pool back, and the roster is written on the same frame so a save taken
## mid-battle records the patched body, not the wound.
func _finish_bandage(actor, merc_id: int) -> void:
	if warband == null or warband.stash == null:
		return
	if not warband.stash.remove(BANDAGE_ITEM, 1):
		return
	var pool := float(actor.get("max_health"))
	var healed := minf(pool, float(actor.get("health")) + pool * BANDAGE_HEAL_SHARE)
	actor.health = healed
	warband.roster.set_health(merc_id, healed)
	warband.changed.emit()


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
		_guard_step(actor, direction, track, distance)
		return
	# A window that has run out is the body's own signal to attack: the guard
	# drops to the swing, and a circle ends in the lunge back in.
	if state == FIGHT_GUARD or state == FIGHT_CIRCLE:
		actor.combat.stop_block()
		track["swing_due"] = true
	# Out of reach there is nothing to strike: close in to the standoff and stop
	# there. A fighter that walks to the mob's own origin leans on it, and a squad
	# of them shoves a whole pack across the clearing.
	var standoff := _standoff_for(actor)
	if distance > standoff:
		_enter(track, FIGHT_CLOSE)
		actor.combat.stop_block()
		_advance(actor, watcher.global_position, track, standoff)
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
			_guard_step(actor, direction, track, distance)
			return
		if not bool(track.get("swing_due", false)) and rolled == FIGHT_CIRCLE:
			_circle_step(actor, direction, track)
			return
	if _swing(actor, track, direction):
		return
	_enter(track, FIGHT_CLOSE)
	actor.combat.stop_block()
	_close_step(actor, direction, track, distance)



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
## angle in. The block is raised once and dropped by the swing that follows. The
## walk in is the same standoff the closing step keeps: a guard is a blade in the
## way, not a body driving its shoulder into the target.
func _guard_step(actor, direction: Vector3, track: Dictionary, distance: float = STANDOFF) -> void:
	if not actor.combat.blocking:
		actor.combat.start_block(direction)
	actor.combat.face_block(direction)
	var across := direction.cross(Vector3.UP) * float(track.get("orbit", 1.0))
	_steer(actor, direction * GUARD_CLOSE * _press(distance) + across * GUARD_SHUFFLE,
		track, false)


## The beat between exchanges with no guard up: work the angle from the standoff,
## never lean on the body in front of it.
func _close_step(actor, direction: Vector3, track: Dictionary, distance: float = STANDOFF) -> void:
	var across := direction.cross(Vector3.UP) * float(track.get("orbit", 1.0))
	_steer(actor, direction * RESET_CLOSE * _press(distance) + across * RESET_SHUFFLE,
		track, false)


## Where this body wants to stand: its own blade's reach, less a hand's width -
## a shiv does not stand where a two-hander does - kept between `MIN_GAP` and
## `STANDOFF` so no weapon pushes and none stands out of its own swing.
func _standoff_for(actor) -> float:
	var wanted := STANDOFF
	var rig = actor.get("rig")
	if rig != null and is_instance_valid(rig) and rig.has_method("profile_for_hand"):
		var profile: Dictionary = rig.profile_for_hand("right")
		var blade_reach := float(profile.get("reach", 0.0))
		if blade_reach > 0.0:
			wanted = clampf(blade_reach * 0.78, MIN_GAP + 0.15, STANDOFF)
	return wanted


## How much of a forward step the distance allows: 1 at the outer edge of the
## standoff, 0 across the whole range a body should be holding, and a negative
## share when the press has carried it inside `MIN_GAP`, which walks it back out.
func _press(distance: float) -> float:
	if distance >= STANDOFF:
		return 1.0
	if distance <= MIN_GAP:
		return -0.9
	return 0.0


## Put the body in a fight state, with the window it holds when the state has one.
func _enter(track: Dictionary, state: int, seconds: float = 0.0) -> void:
	track["state"] = state
	track["state_left"] = seconds


## Walk or jog to a point, stopping `stop_at` short of it. A drop, a corpse and
## the soul are places to stand next to; a watcher is a body to stand *away* from.
func _advance(actor, point: Vector3, track: Dictionary, stop_at: float = 0.0) -> void:
	var to: Vector3 = point - actor.global_position
	to.y = 0.0
	var gap := to.length() - maxf(stop_at, 0.0)
	if gap <= 0.08 or to.length_squared() <= 0.0001:
		_hold(actor)
		return
	# Walking is not fighting: a guard left up while crossing the yard to a drop
	# would be a pose nobody set.
	actor.combat.stop_block()
	# Far out is a jog; the last few metres into contact are a walk, so a squad
	# arrives beside a body instead of running it over.
	_steer(actor, to.normalized(), track, gap > RUN_GAP)



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
			"heal_left": 0.0, "bandaging": false,
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
