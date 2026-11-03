extends RefCounted
## Plays the PROC entries a kit arms. One instance per body, armed at dress time,
## ticked by the body's own authoritative frame.
##
## Every verb here is receiver-side on purpose: a landed blow is the only event
## the engine knows without a new signal, and the attacker's node arrives through
## `ArenaActor.struck_by` before the blow resolves. That covers the whole proc
## vocabulary in `AnnointCatalog.Proc` without touching `combat.gd`.
##
## Rules, and why they are these rules:
##   * one roll per blow, never per frame
##   * a cooldown is a countdown in seconds, not a timestamp, so it survives a
##     pause and reads the same on a replica that never runs the roll
##   * `every N` counts the bearer's own triggers and is reset by re-arming
##   * the attacker is remembered for `ATTACKER_MEMORY` seconds, because
##     `struck_by` and the damage call are the same beat
##   * a bleed is applied through the target's own `take_damage`, so a dead body
##     stops bleeding without this file knowing what death means

const Catalog = preload("res://scripts/warband/annoint_catalog.gd")

const ATTACKER_MEMORY := 1.0
## Bleeds tick in one-damage steps so a 2/s DoT is visible, not a float trickle.
const BLEED_STEP := 1.0

var _body = null
var _procs: Array = []
var _cooldown: Dictionary = {}   # index -> seconds left
var _ticks: Dictionary = {}      # index -> trigger count since arming
var _attacker = null
var _attacker_left := 0.0
var _bleeds: Array = []          # {target, dps, left, carry, slot}
var _armed := 0


func bind(body) -> void:
	_body = body


## Called on every dress: the kit's procs replace the old set wholesale.
func arm(procs: Array) -> void:
	_procs = procs.duplicate()
	_cooldown.clear()
	_ticks.clear()
	_bleeds.clear()
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
			_bleeds.append({"target": target, "dps": float(entry.magnitude),
				"left": maxf(float(entry.duration), 1.0), "carry": 0.0,
				"slot": int(_body.slot)})


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
	if _bleeds.is_empty():
		return
	var still: Array = []
	for bleed in _bleeds:
		var target = bleed["target"]
		if not is_instance_valid(target):
			continue
		bleed["left"] = float(bleed["left"]) - delta
		bleed["carry"] = float(bleed["carry"]) + float(bleed["dps"]) * delta
		while float(bleed["carry"]) >= BLEED_STEP:
			bleed["carry"] = float(bleed["carry"]) - BLEED_STEP
			_hurt(target, BLEED_STEP)
		if float(bleed["left"]) > 0.0 and is_instance_valid(target):
			still.append(bleed)
	_bleeds = still
