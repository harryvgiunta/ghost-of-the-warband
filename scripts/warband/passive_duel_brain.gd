class_name PassiveDuelBrain
extends Node
## The choreography half of the presence bubble.
##
## `WarbandBubbleManager` decides that a fight is simulated (`PASSIVE_SIM`) and
## the damage funnels pay it 10%. This node makes that read on screen: while its
## body is passive it holds the ring instead of trading blows, spends four out
## of five exchanges guarding, and is allowed one measured blow on the fifth.
## The bubble's 10% already caps the kill rate; the choreography keeps a far
## pair from looking like statues and, just as importantly, from stacking kills
## while barely swinging.
##
## It drives two kinds of body, duck-typed:
##
## * **Wilderness mobs** (`scripts/devil_mob.gd`, `scripts/enemy.gd`, and the
##   forest family that inherits the former) through the `warband_stance()` /
##   `warband_guard()` hooks, which their own attack gate reads. The brain ticks
##   itself, as a child of the mob, on the mob's physics frame.
## * **Arena fighters** (`scripts/arena_actor.gd`) through the real combat
##   system: `combat.start_block()` gives a genuine guard that
##   `receive_melee()` resolves into DEFENSE_BLOCK/DEFENSE_PARRY, the body
##   circles with `move_direction`, and a window does `combat.stop_block()` then
##   `begin_melee()` (or `begin_draw()`/`release_draw()` for a bow). While the
##   brain owns a fighter it takes the body off `_bot_step` (`is_bot = false`)
##   and writes the intents itself, so the two AI layers never fight over
##   `move_direction`.
##
## **Call order for fighters:** the arena must call `step(delta)` once per
## physics frame for every fighter whose brain is driving it, *before* that
## body's own `ArenaActor.step(delta, actors)`; the intents and the block are
## consumed by that step. Mobs need no call - they tick the brain themselves.
##
## A body only ever plays this stance while the bubble registry says it is
## `PASSIVE_SIM`, so the guard pose and the 10% multiplier can never disagree.
## `set_active(true)` is the hard override for a fight the scene drives live.

## One decision per exchange, and the fifth decision is the only one allowed to
## become a blow: four parries to one swing is the "about 80% guard" rhythm.
const EXCHANGE_SECONDS := 1.1
const GUARD_EXCHANGES := 5
## What an exchange turned out to be: nothing has come due yet, a guard, or the
## one blow in five.
const EXCHANGE_NONE := -1
const EXCHANGE_GUARD := 0
const EXCHANGE_COMMIT := 1
## How long the attack gate stays open when the brain commits. Long enough for
## the body to step in and wind up, short enough that the body's own cooldown -
## not this timer - is what limits a second blow.
const SWING_WINDOW := 0.9
## States in which a mob has committed to a blow and must not be re-gated.
const SWING_STATES := ["WINDUP", "STRIKE", "DIVE", "SHOOT"]
## A guarding fighter holds this ring; inside it it backs off, outside it closes.
const FIGHTER_RING := 2.7
## A bow cannot guard, so it holds shooting range instead and spends its window
## on an arrow - the same distance ladder `_bot_step` uses.
const FIGHTER_BOW_RING := 12.0
## Inside this distance the blade comes out and the guard goes up.
const FIGHTER_BLADE_RANGE := 9.0
## Only these can set a guard; `start_block()` refuses everything else.
const GUARD_WEAPONS := ["sword", "dagger"]

var _body: Node
var _opponent: Node3D
## True for an `ArenaActor`-style fighter, false for a wilderness mob.
var _fighter := false
## Set by `set_active`: a live fight the scene forced on, overriding the bubble.
var _active := false
## The stance currently written to the body, so a flip is applied exactly once.
var _passive := false
var _exchange := 0
var _exchange_left := 0.0
var _window_left := 0.0
var _swinging := false
var _orbit_dir := 1.0
var _rng := RandomNumberGenerator.new()


func _physics_process(delta: float) -> void:
	# A fighter is stepped by its own arena through `step()`. Ticking it here as
	# well would spend the exchange clock twice on one physics frame.
	if _fighter:
		return
	step(delta)


## The whole brain for one physics frame. A scene calls this itself for fighter
## bodies, before `ArenaActor.step()`; mobs call it from their own tick.
func step(delta: float) -> void:
	var body := _body
	if not is_instance_valid(body):
		return
	var passive: bool = (not _active and body.get("alive") != false
		and WarbandDamage.is_passive(body))
	if passive != _passive:
		_apply_stance(passive)
	if not passive:
		return
	if _fighter:
		_tick_fighter(delta)
	else:
		_tick_mob(delta)


## Take over a body already in a fight: a wilderness mob, or an arena fighter
## with `opponent` standing in for the enemy. The brain becomes a child of the
## body, so its tick shares the body's lifetime.
func attach(body, opponent = null) -> void:
	detach()
	if not (body is Node3D) or not is_instance_valid(body):
		return
	_fighter = body.has_method("update_input") and body.get("combat") != null
	if not _fighter and (not body.has_method("warband_guard")
			or not body.has_method("warband_stance")):
		push_error("PassiveDuelBrain needs an ArenaActor or the warband_guard() "
			+ "hooks on %s" % str(body))
		return
	_body = body
	# Fighters and mobs both carry a `slot`-like id or none at all: the pair must
	# circle in opposite directions, so odd ids go one way and even ids the other.
	var slot_value: Variant = body.get("slot")
	_orbit_dir = -1.0 if slot_value != null and int(slot_value) % 2 == 0 else 1.0
	if opponent is Node3D and is_instance_valid(opponent):
		_opponent = opponent
		# A mob pair the scene hands over may not have sighted each other yet,
		# and the mob's own state machine needs a target before it can duel.
		if not _fighter and opponent is CharacterBody3D \
				and not is_instance_valid(body.get("_target")):
			body.set("_target", opponent)
	var parent := get_parent()
	if parent != null and parent != body:
		parent.remove_child(self)
	if get_parent() == null:
		body.add_child(self)


## Hand the body back its own behaviour: real damage, no guard, no spacing bias,
## and its own AI (a fighter goes back to `_bot_step`).
func detach() -> void:
	_release()
	_body = null
	_opponent = null
	_fighter = false
	var parent := get_parent()
	if parent != null:
		parent.remove_child(self)


## `true` while the scene drives this fight for real; `false` returns the body
## to the bubble, which is the only thing that may make it passive.
func set_active(active: bool) -> void:
	_active = active
	if active:
		_release()


## True while the body is driving its own fight, false while this brain owns its
## intents. Reflects the stance last written to the body.
func active() -> bool:
	return not _passive


# --- the far-fight choreography -------------------------------------------

## Mobs: the guard gate is theirs, the rhythm is ours.
func _tick_mob(delta: float) -> void:
	var mob := _body
	# Nothing to duel: a passive body with no target is just walking its patch,
	# and re-gating it would leave a guard pose on an idle mob.
	if not is_instance_valid(mob.get("_target")):
		return
	# The commit: the tick the body starts a blow, shut the gate again so a
	# second windup cannot follow on the next frame.
	if str(mob.get("state")) in SWING_STATES:
		if not _swinging:
			_swinging = true
			_window_left = 0.0
			mob.warband_guard(_guard_span())
		return
	if _swinging:
		_swinging = false
	if _window_left > 0.0:
		_window_left = maxf(0.0, _window_left - delta)
		if _window_left > 0.0:
			return
		# The window closed without a blow (out of reach, staggered): back to
		# guarding instead of standing with the gate open.
		mob.warband_guard(_guard_span())
	match _exchange_due(delta, float(mob.get("_attack_cooldown")) <= 0.0):
		EXCHANGE_NONE:
			return
		EXCHANGE_GUARD:
			_guard_exchange(mob)
		_:
			mob.warband_guard(0.0)
			_window_left = SWING_WINDOW
			# A body still holding the parry pose steps back in and swings.
			if mob.has_method("_enter") and str(mob.get("state")) == "RECOVER":
				mob._enter("CIRCLE")


## Fighters: circle, guard with the real combat system, and open one window.
func _tick_fighter(delta: float) -> void:
	var body := _body
	var opponent := _opponent
	if not is_instance_valid(opponent):
		return
	var combat: Variant = body.get("combat")
	var rig: Variant = body.get("rig")
	if combat == null or rig == null:
		return
	var to_opponent: Vector3 = opponent.global_position - body.global_position
	to_opponent.y = 0.0
	var distance := to_opponent.length()
	var direction := to_opponent.normalized() if distance > 0.001 else Vector3.FORWARD
	var aim: Vector3 = opponent.get_aim_position() if opponent.has_method("get_aim_position") \
		else opponent.global_position + Vector3(0.0, 1.2, 0.0)
	combat.set_aim(aim)
	if _window_left > 0.0:
		# The window: drop the guard and take the one blow. A blade closes first;
		# a bow shoots from where it stands.
		_window_left = maxf(0.0, _window_left - delta)
		if str(rig.weapon) == "bow":
			body.update_input(Vector2.ZERO, false)
		else:
			body.update_input(Vector2(direction.x, direction.z), false)
		_strike(combat, rig)
		return
	if _exchange_due(delta, str(rig.phase) == "READY") == EXCHANGE_COMMIT:
		combat.stop_block()
		_window_left = SWING_WINDOW
		body.update_input(Vector2(direction.x, direction.z), false)
		return
	# Circle: sideways with a backward bias, never a sprint, so the pair reads
	# as circling guards rather than a charge.
	var ring := FIGHTER_BOW_RING if str(rig.weapon) == "bow" else FIGHTER_RING
	var tangent := Vector3(-direction.z, 0.0, direction.x) * _orbit_dir
	var intent := tangent
	if distance > ring + 0.3:
		intent += direction
	elif distance < ring - 0.6:
		intent -= direction
	body.update_input(Vector2(intent.x, intent.z).limit_length(), false)
	if distance > FIGHTER_BLADE_RANGE:
		# Beyond blade reach there is no guard to set: the body keeps its bow and
		# spends the window on a shot instead.
		combat.stop_block()
		return
	if str(rig.weapon) not in GUARD_WEAPONS:
		# Only a blade can set a guard: the same switch the bot makes in close.
		rig.set_weapon("sword")
	if not combat.blocking:
		combat.start_block(direction)
	else:
		# Keeps the guard pointed at the opponent while the body keeps circling.
		combat.face_block(direction)


## One blow from a committed window. A bow needs its draw first; everything else
## swings. A landed swing closes the window so the next guard re-arms at once.
func _strike(combat: Variant, rig: Variant) -> void:
	if str(rig.weapon) == "bow":
		if str(rig.phase) in ["DRAWING", "HOLDING"]:
			if float(rig.draw_amount) >= 0.85:
				combat.release_draw()
				_window_left = 0.0
			else:
				# A draw cannot be rushed: hold the window until the arrow is
				# ready instead of losing the shot to the window timer.
				_window_left = maxf(_window_left, 0.2)
		elif combat.can_draw():
			combat.begin_draw()
			_window_left = maxf(_window_left, 0.2)
		return
	if combat.begin_melee():
		_window_left = 0.0


# --- shared rhythm ---------------------------------------------------------

## Counts one exchange and answers what it is: nothing yet, a guard, or the one
## blow in five. The body's own readiness has the final say, so a window is never
## spent while it is still recovering.
func _exchange_due(delta: float, body_ready: bool) -> int:
	_exchange_left = maxf(0.0, _exchange_left - delta)
	if _exchange_left > 0.0:
		return EXCHANGE_NONE
	_exchange_left = EXCHANGE_SECONDS
	_exchange += 1
	if _exchange % GUARD_EXCHANGES != 0:
		return EXCHANGE_GUARD
	return EXCHANGE_COMMIT if body_ready else EXCHANGE_GUARD


## A guard has to outlast the gap to the next exchange, or the body would get a
## free swing in the seam between two parries.
func _guard_span() -> float:
	return EXCHANGE_SECONDS + _rng.randf_range(0.15, 0.45)


func _guard_exchange(mob: Node) -> void:
	mob.warband_guard(_guard_span())
	# The parry itself: step back into the guard pose rather than trade. Only
	# from CIRCLE - forcing it from IDLE/RETURN would disturb a calm body.
	if mob.has_method("_enter") and str(mob.get("state")) == "CIRCLE":
		mob._enter("RECOVER")


func _apply_stance(passive: bool) -> void:
	_passive = passive
	_exchange = 0
	_exchange_left = 0.0
	_window_left = 0.0
	_swinging = false
	var body := _body
	if _fighter:
		# The brain writes the intents, so the bot must not write them too.
		body.is_bot = not passive
		if not passive and body.get("combat") != null:
			body.combat.stop_block()
		return
	body.warband_stance(passive)
	if passive:
		# Open on a parry, never on a free swing.
		body.warband_guard(_guard_span())


func _release() -> void:
	var body := _body
	if is_instance_valid(body):
		if _fighter:
			body.is_bot = true
			if body.get("combat") != null:
				body.combat.stop_block()
		elif body.has_method("warband_stance"):
			body.warband_stance(false)
	_passive = false
	_exchange = 0
	_exchange_left = 0.0
	_window_left = 0.0
	_swinging = false
