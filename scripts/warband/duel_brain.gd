class_name DuelBrain
extends RefCounted
## The duel ladder: how a body with a weapon fights another body that has one.
##
## One brain, two owners. The arena's three foes (`arena_area.gd`) and the
## Hollow's duelists (`devil_mob.gd`) fight through this file: pick the target,
## aim at where it is going, close to the weapon's own reach, hold a guard
## window, step off the line between blows and - for a bow - keep the range the
## bow wants and work the draw, hold and release.
##
## The brain owns no body. The caller hands it what the body can see (`view`) and
## does what the answer says (`tick`), so a `WarbandBody` and a `devil_mob` are
## driven by the same ladder through different hands. Everything a fight's
## temper *is* - the share of exchanges a body guards, the beat it holds before a
## blow, the seconds it spends circling, how far it leads a moving body, its
## reach and whether it swings only into an opening - arrives as `temper` data,
## so a tier and a demon differ in numbers and never in rules.

## How far beyond its weapon's own reach a body stops closing: a swing starts
## inside this band and the body carries itself in on the blow. A temper may
## carry its own (`pad`); the arena's tiers use this one.
const CLOSE_PAD := 1.1
## What a rolled guard is held for on top of the tier's own step: one beat of the
## fight, so a guard is a window and never a state.
const GUARD_BASE := 0.45
## The share of a swing's clip past which its contact has been and struck and the
## body is in its follow-through (`Archer.SWING_FOLLOW_END`): the opening a
## duelist answers.
const RECOVERY_SHARE := 0.65
## How often a body already circling reconsiders the side it steps off on, and
## the seconds it commits to the new side.
const FLIP_CHANCE := 0.02
const FLIP_HOLD := 0.4

## The body's own clock inside the fight: the guard window left, the beat before
## the next blow, the seconds left circling, and which way it steps off the line.
var guard_left := 0.0
var beat := 0.0
var step := 0.0
var step_sign := 1.0
## What the target was doing with its guard at the last look: a guard that has
## come down since bought one blow and is spent, which is an opening.
var target_guarded := false


func _init(start_sign: float = 1.0) -> void:
	step_sign = -1.0 if start_sign < 0.0 else 1.0


## One brain tick. What the body can see (`view`):
##   `position` - where it stands.
##   `target` - where the target stands; `target_velocity` - how it is moving.
##   `weapon` - "bow" or a blade; the caller names the swing it would make.
##   `ready` - may this body begin a blow now (its own cooldown and gate).
##   `can_draw` - may it put an arrow on the string now.
##   `blocking` - is its guard up this tick.
##   `target_open` - is the target in a window (`observe`).
## The answer is a decision and nothing else:
##   `move` - a unit direction, zero to stand; `run` - at a run or a walk.
##   `guard` - the window is open: raise the guard, or drop it when false.
##   `swing` - the variant to commit to, empty for no blow.
##   `draw` - put the string up and stand.
func tick(delta: float, temper: Dictionary, view: Dictionary) -> Dictionary:
	var here: Vector3 = view.get("position", Vector3.ZERO)
	var goal := _lead_point(view.get("target", here), view.get("target_velocity", Vector3.ZERO),
		float(temper.get("lead", 0.0)))
	var flat := goal - here
	flat.y = 0.0
	var distance := flat.length()
	var direction := flat.normalized() if distance > 0.001 else Vector3.ZERO
	beat = maxf(0.0, beat - delta)
	guard_left = maxf(0.0, guard_left - delta)
	step = maxf(0.0, step - delta)
	var answer := {
		"move": Vector3.ZERO, "run": false, "guard": guard_left > 0.0,
		"swing": "", "draw": false,
	}
	if str(view.get("weapon", "")) == "bow":
		_work_bow(answer, temper, view, direction, distance)
	else:
		_work_blade(answer, temper, view, direction, distance)
	return answer


## Whether the target can be hit right now: it is in the follow-through of a
## swing of its own, it is staggered, or the guard it raised has just been spent
## and come down. Asked once a tick, because "just been blocked" is a change
## between two looks. A target with no combat of its own has no guard to read and
## is always open.
func observe(combat) -> bool:
	if combat == null:
		target_guarded = false
		return true
	var guarding: bool = combat.get("blocking") == true
	var spent: bool = target_guarded and not guarding
	target_guarded = guarding
	if spent:
		return true
	var staggered = combat.get("stagger_time")
	if staggered != null and float(staggered) > 0.0:
		return true
	if not combat.has_method("melee_progress_for"):
		return true
	for hand in ["right", "left"]:
		var progress := float(combat.melee_progress_for(hand))
		if progress >= RECOVERY_SHARE and progress < 1.0:
			return true
	return false


## Where a body aims: at the target, or at where it is going.
func _lead_point(at: Vector3, velocity: Vector3, lead: float) -> Vector3:
	if lead <= 0.0:
		return at
	return at + Vector3(velocity.x, 0.0, velocity.z) * lead


func _work_blade(answer: Dictionary, temper: Dictionary, view: Dictionary,
		direction: Vector3, distance: float) -> void:
	var reach := float(temper.get("range", 0.0)) + float(temper.get("pad", CLOSE_PAD))
	if distance > reach:
		answer["move"] = direction
		answer["run"] = distance > 6.0
		return
	# In reach: a beat, a guard, or the blow itself - and a temper that fights
	# into openings takes the blow only when the target has one.
	if beat <= 0.0 and bool(view.get("ready", false)) and _open(temper, view):
		if guard_left > 0.0:
			answer["move"] = direction
			return
		if randf() < float(temper.get("guard", 0.0)) and step <= 0.0:
			answer["guard"] = true
			answer["move"] = direction
			guard_left = GUARD_BASE + float(temper.get("step", 0.0))
			return
		answer["guard"] = false
		answer["swing"] = str(view.get("swing", "overhead"))
		answer["move"] = direction
		beat = float(temper.get("beat", 0.0))
		return
	# Between blows - and while the target is not open - step off the line so the
	# body is not a target that stands, and hold the guard if the temper wants one.
	var side := direction.cross(Vector3.UP) * step_sign
	if step <= 0.0 and randf() < FLIP_CHANCE:
		step_sign = -step_sign
		step = FLIP_HOLD + float(temper.get("step", 0.0))
	answer["move"] = (direction * 0.6 + side * 0.8).normalized()
	if not _open(temper, view):
		answer["guard"] = true


func _work_bow(answer: Dictionary, temper: Dictionary, view: Dictionary,
		direction: Vector3, distance: float) -> void:
	var want := 12.0 + float(temper.get("lead", 0.0)) * 4.0
	if distance > want + 2.0:
		answer["move"] = direction
		answer["run"] = true
		return
	if distance < want - 4.0:
		answer["move"] = -direction
		return
	if bool(view.get("can_draw", false)) and _open(temper, view):
		answer["guard"] = false
		answer["draw"] = true
		return
	if not bool(view.get("blocking", false)) and guard_left <= 0.0 \
			and randf() < float(temper.get("guard", 0.0)) * 0.3:
		answer["guard"] = true


## Whether a temper that fights into openings may commit now. A temper without
## `window` fights on its beat alone, which is the arena's own rule.
func _open(temper: Dictionary, view: Dictionary) -> bool:
	return not bool(temper.get("window", false)) or bool(view.get("target_open", false))
