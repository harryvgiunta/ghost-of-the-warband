extends RefCounted
## Plays the PROC entries a kit arms. One instance per body, armed at dress time,
## ticked by the body's own authoritative frame.
##
## Two edges feed it. Every receiver-side verb (`HEAL`/`STAMINA`/`REFLECT`/
## `ABSORB`/`LETHAL_SAVE`/`STAGGER`/`GUARD_BREAK`/`BLEED`) hangs off a landed blow
## the body *took*, which is the only event the engine knows without a new signal:
## the attacker's node arrives through `ArenaActor.struck_by` before the blow
## resolves. The two attack-side verbs (`QUICK_STRIKE`, `POISON`) hang off
## `Trigger.HIT` - a blow this body *landed* - which `Combat` names through the
## body's own `note_attack_landed`. Neither edge touches `combat.gd`'s damage.
##
## Rules, and why they are these rules:
##   * one roll per blow, never per frame
##   * a cooldown is a countdown in seconds, not a timestamp, so it survives a
##     pause and reads the same on a replica that never runs the roll
##   * `every N` counts the bearer's own triggers and is reset by re-arming
##   * the attacker is remembered for `ATTACKER_MEMORY` seconds, because
##     `struck_by` and the damage call are the same beat
##   * a bleed or a poison is applied through the target's own `take_damage`, so a
##     dead body stops losing health without this file knowing what death means
##   * the quick strike is queued to the next tick rather than begun inside the
##     blow: `Combat` is still sweeping its victim list when it names the hit, and
##     a second swing started under that sweep would reset the list it is walking

const Catalog = preload("res://scripts/warband/annoint_catalog.gd")
const AbilityFx = preload("res://scripts/ability_fx.gd")

const ATTACKER_MEMORY := 1.0
## Bleeds tick in one-damage steps so a 2/s DoT is visible, not a float trickle.
const BLEED_STEP := 1.0
## How long a queued quick strike keeps trying to get the blade moving before it
## gives up. A swing in its recovery frees the hand in well under this; a body
## staggered, rolling, drinking or holding a bow never frees it at all.
const STRIKE_GRACE := 0.6
## The bloom a poisoned body gives off. Not blood, so not `BloodFx`.
const POISON_TINT := Color("7ee06a")

var _body = null
var _procs: Array = []
var _cooldown: Dictionary = {}   # index -> seconds left
var _ticks: Dictionary = {}      # index -> trigger count since arming
var _attacker = null
var _attacker_left := 0.0
var _dots: Array = []            # {kind, target, dps, left, carry}
var _strikes: Array = []         # {hand, rate, left}
var _armed := 0


func bind(body) -> void:
	_body = body


## Called on every dress: the kit's procs replace the old set wholesale.
func arm(procs: Array) -> void:
	_procs = procs.duplicate()
	_cooldown.clear()
	_ticks.clear()
	_dots.clear()
	_strikes.clear()
	_attacker = null
	_attacker_left = 0.0
	_armed = _procs.size()


func armed_count() -> int:
	return _armed


## The striker behind the blow, remembered for one beat.
func note_attacker(node) -> void:
	if node == null or node == _body:
		return
	_attacker = node
	_attacker_left = ATTACKER_MEMORY


# --- the die ---------------------------------------------------------------

func _ready_now(index: int) -> bool:
	return float(_cooldown.get(index, 0.0)) <= 0.0


func _spend(index: int, seconds: float) -> void:
	if seconds > 0.0:
		_cooldown[index] = seconds


## Chance or cadence, never both.
func _passes(index: int, entry) -> bool:
	if int(entry.every) > 0:
		var count := int(_ticks.get(index, 0)) + 1
		_ticks[index] = count
		return count % int(entry.every) == 0
	return randf() < float(entry.chance)


# --- the incoming edge -----------------------------------------------------

## The amount that should land. A lethal save clamps, an absorb multiplies.
func on_incoming(amount: float, source_id: int) -> float:
	if _procs.is_empty() or not is_instance_valid(_body):
		return amount
	var out := amount
	for index in _procs.size():
		var entry = _procs[index]
		if not bool(entry.wired):
			continue
		if int(entry.trigger) == Catalog.Trigger.LETHAL:
			if out < float(_body.health) or not _ready_now(index):
				continue
			if not _passes(index, entry):
				continue
			_spend(index, entry.cooldown)
			out = maxf(0.0, float(_body.health) - 1.0)
		elif int(entry.proc) == Catalog.Proc.ABSORB:
			if float(entry.scale) <= 0.0 or not _ready_now(index):
				continue
			if not _passes(index, entry):
				continue
			_spend(index, entry.cooldown)
			out *= maxf(0.0, 1.0 - float(entry.scale))
	return maxf(0.0, out)


## The blow landed: pay the receiver-side verbs and hand the attacker theirs.
func after_damage(landed: float, source_id: int) -> void:
	if _procs.is_empty() or landed <= 0.0 or not is_instance_valid(_body):
		return
	for index in _procs.size():
		var entry = _procs[index]
		if not bool(entry.wired) or int(entry.trigger) != Catalog.Trigger.DAMAGE_TAKEN:
			continue
		if int(entry.proc) == Catalog.Proc.ABSORB:
			continue
		if not _ready_now(index) or not _passes(index, entry):
			continue
		_spend(index, entry.cooldown)
		_pay(index, entry, landed, source_id)


func on_block() -> void:
	if _procs.is_empty() or not is_instance_valid(_body):
		return
	for index in _procs.size():
		var entry = _procs[index]
		if not bool(entry.wired) or int(entry.trigger) != Catalog.Trigger.BLOCK:
			continue
		if not _ready_now(index) or not _passes(index, entry):
			continue
		_spend(index, entry.cooldown)
		_pay(index, entry, 0.0, -1)


## The bearer's own blow landed on `target`: the attack-side edge. `hand` is the
## wrist that swung, so a dual pair's quick strike comes from the same hand;
## `landed` is the blow's own figure, which a lifesteal share is taken from.
func on_hit(target, hand: String = "", landed: float = 0.0) -> void:
	if _procs.is_empty() or not is_instance_valid(_body):
		return
	for index in _procs.size():
		var entry = _procs[index]
		if not bool(entry.wired) or int(entry.trigger) != Catalog.Trigger.HIT:
			continue
		if not _ready_now(index) or not _passes(index, entry):
			continue
		_spend(index, entry.cooldown)
		_pay_hit(entry, target, hand, landed)


# --- the verbs -------------------------------------------------------------

func _pay(index: int, entry, landed: float, source_id: int) -> void:
	# Branch rather than match: these are enum values from the catalog's script,
	# not constants of this one, and a match pattern needs a literal.
	if int(entry.proc) == Catalog.Proc.HEAL:
		_body.health = minf(float(_body.health) + float(entry.magnitude),
			float(_body.max_health))
	elif int(entry.proc) == Catalog.Proc.STAMINA:
		_body.stamina = minf(float(_body.stamina) + float(entry.magnitude),
			float(_body.max_stamina))
	elif int(entry.proc) == Catalog.Proc.REFLECT:
		var target = _striker()
		if target != null and float(entry.scale) > 0.0:
			_hurt(target, landed * float(entry.scale))
	elif int(entry.proc) == Catalog.Proc.STAGGER:
		var target = _striker()
		if target != null and target.get("combat") != null:
			target.combat.stagger(float(entry.magnitude))
	elif int(entry.proc) == Catalog.Proc.GUARD_BREAK:
		var target = _striker()
		if target != null and target.get("combat") != null:
			target.combat.break_guard()
	elif int(entry.proc) == Catalog.Proc.BLEED:
		var target = _striker()
		if target != null and float(entry.magnitude) > 0.0:
			_dots.append({"kind": "bleed", "target": target,
				"dps": float(entry.magnitude),
				"left": maxf(float(entry.duration), 1.0), "carry": 0.0})


## The attack-side verbs. A quick strike is queued for the next tick (see the
## header); a poison is laid on the body that was just opened.
func _pay_hit(entry, target, hand: String, landed: float) -> void:
	if int(entry.proc) == Catalog.Proc.LIFESTEAL:
		# A share of the blow comes back as health, on the bearer. A blow that
		# reports no figure (a harness naming a hit) heals nothing rather than
		# guessing at a number the receiver owns.
		var share := landed * float(entry.scale)
		if share > 0.0:
			_body.health = minf(float(_body.health) + share,
				float(_body.max_health))
		return
	if int(entry.proc) == Catalog.Proc.QUICK_STRIKE:
		if float(entry.scale) <= 1.0:
			return
		_strikes.append({"hand": hand if hand in ["left", "right"] else "right",
			"rate": float(entry.scale), "left": STRIKE_GRACE})
	elif int(entry.proc) == Catalog.Proc.POISON:
		if not is_instance_valid(target) or target.get("alive") == false:
			return
		_poison(target, float(entry.magnitude), float(entry.duration))


## One poison per target per runtime: a second dose refreshes the clock instead of
## stacking a twin, so the figure on the card is the figure the body loses each
## second. The bloom marks the dose, not the tick - five green bursts a second on
## a whole pack would be the frame's cost, not the mechanic's.
func _poison(target, dps: float, seconds: float) -> void:
	if dps <= 0.0:
		return
	var left := maxf(seconds, 1.0)
	for dot in _dots:
		if str(dot["kind"]) != "poison" or dot["target"] != target:
			continue
		dot["dps"] = maxf(float(dot["dps"]), dps)
		dot["left"] = maxf(float(dot["left"]), left)
		_bloom(target, 0.55)
		return
	_dots.append({"kind": "poison", "target": target, "dps": dps,
		"left": left, "carry": 0.0})
	_bloom(target, 1.0)


## A green bloom at the wound. Presentation only: nothing here reads health.
func _bloom(target, scale: float) -> void:
	var parent := _fx_parent()
	if parent == null or not is_instance_valid(target):
		return
	var at: Vector3 = target.get_aim_position() if target.has_method("get_aim_position") \
		else (target as Node3D).global_position + Vector3.UP
	AbilityFx.burst(parent, at, POISON_TINT, clampf(scale, 0.4, 1.2))


func _fx_parent() -> Node3D:
	if not is_instance_valid(_body):
		return null
	return _body.get_parent() as Node3D


func _striker():
	if _attacker_left <= 0.0 or not is_instance_valid(_attacker):
		return null
	return _attacker


func _hurt(target, amount: float) -> void:
	if amount <= 0.0 or not is_instance_valid(target):
		return
	if not target.has_method("take_damage"):
		return
	target.take_damage(amount, int(_body.slot))


# --- the clock -------------------------------------------------------------

func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	for index in _cooldown.keys():
		var left := float(_cooldown[index]) - delta
		if left <= 0.0:
			_cooldown.erase(index)
		else:
			_cooldown[index] = left
	if _attacker_left > 0.0:
		_attacker_left = maxf(0.0, _attacker_left - delta)
		if _attacker_left <= 0.0:
			_attacker = null
	_advance_strikes(delta)
	if _dots.is_empty():
		return
	var still: Array = []
	for dot in _dots:
		var target = dot["target"]
		if not is_instance_valid(target):
			continue
		dot["left"] = float(dot["left"]) - delta
		dot["carry"] = float(dot["carry"]) + float(dot["dps"]) * delta
		while float(dot["carry"]) >= BLEED_STEP:
			dot["carry"] = float(dot["carry"]) - BLEED_STEP
			_hurt(target, BLEED_STEP)
		if float(dot["left"]) > 0.0 and is_instance_valid(target):
			still.append(dot)
	_dots = still


## The queued quick strikes, oldest first. A hand that cannot swing yet - still in
## its own cut, rolling, staggered, holding a bow - keeps its place until
## `STRIKE_GRACE` runs out; the proc spends its chance either way.
func _advance_strikes(delta: float) -> void:
	if _strikes.is_empty():
		return
	var still: Array = []
	for strike in _strikes:
		if not is_instance_valid(_body):
			continue
		var began := false
		if _body.has_method("quick_strike"):
			began = bool(_body.quick_strike(strike["hand"], float(strike["rate"])))
		if began:
			continue
		strike["left"] = float(strike["left"]) - delta
		if float(strike["left"]) > 0.0:
			still.append(strike)
	_strikes = still
