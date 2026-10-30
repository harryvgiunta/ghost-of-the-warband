class_name DuelLesson
extends Node
## GHOST OF THE WARBAND: the first fight, taught in four short beats.
##
## The camp's opening wakes the player in a cage with nothing in its hands, and
## the camp's only blade is lying on the dirt at the cold altar with a gold arrow
## over it. This node names the four things that have to be pressed for that to
## turn into a fight a newcomer can win:
##
##   1. **MOVE** - walk to the blade. Nothing hunts anybody yet.
##   2. **FETCH** - stand over it and press `K`.
##   3. **FIGHT** - `LMB` cuts, the wheel stabs and chops; the moment the blade is
##      in hand is the moment the pair wake.
##   4. **GUARD** - the second watcher's windup is the moment to name `RMB`.
##
## Every beat is one line and one key line; the scene shows each as a tip, never
## as a page to read. The node owns no scene lookups: the camp feeds it facts and
## shows the tips it asks for. Every transition is guarded, so a scene that fires
## an event early (a swing before the blade, a guard before the tip) is ignored
## rather than throwing the lesson out of sequence. Facts arrive at most once.

signal step_changed(step: int)
## A tip should be offered. The copy, the tiles and the clock are the scene's.
signal tip_wanted(tip: int)

enum Step { DORMANT, MOVE, FETCH, FIGHT, DONE }
## The four hints, in the order the lesson asks for them. The guard is a tip, not
## a step: the fight is one beat from the blade to the last body on the dirt.
enum Tip { MOVE, FETCH, SWING, GUARD }

var _step := Step.DORMANT
var _cuts_tip := false
var _guard_tip := false
var _guarded := false
## The watcher whose windup opened the exchange. The guard lesson belongs to the
## other one - unless only one is left standing, and then it is his as well.
var _first_windup := 0


## The player is awake in the camp. This is the first beat and the only way in.
func wake() -> bool:
	if _step != Step.DORMANT:
		return false
	_set_step(Step.MOVE)
	tip_wanted.emit(Tip.MOVE)
	return true


## The body standing on the blade. The tip asks for the key that takes it.
func note_shiv_near() -> bool:
	if _step != Step.MOVE:
		return false
	_set_step(Step.FETCH)
	tip_wanted.emit(Tip.FETCH)
	return true


## The blade left the dirt and went into a hand. That is the frame the cuts are
## named on - the moment a new player is armed is the moment they ask how to
## swing - so the tip is offered here, before the pair get a single frame to
## close in. The fight may wake from this point and not before.
func note_shiv_taken() -> bool:
	if _step != Step.MOVE and _step != Step.FETCH:
		return false
	_cuts_tip = true
	_set_step(Step.FIGHT)
	tip_wanted.emit(Tip.SWING)
	return true


## A watcher's windup started. The guard tip belongs to the *second* of the pair:
## the first body to raise its club opens the exchange and the other one is the
## one the tip is written for. With a single watcher left standing it teaches the
## tip itself, because there is no second. `pair_alive` is how many are still up.
func note_windup(watcher_id: int, pair_alive: int = 2) -> bool:
	if _step != Step.FIGHT or _guard_tip or _guarded:
		return false
	if _first_windup == 0:
		_first_windup = watcher_id
	if watcher_id == _first_windup and pair_alive > 1:
		return false
	_guard_tip = true
	tip_wanted.emit(Tip.GUARD)
	return true


## A blow landed on a raised guard. The lesson is done: the player has blocked
## once, which is what the last tip asked for.
func note_guarded() -> bool:
	if _step != Step.FIGHT or not _guard_tip or _guarded:
		return false
	_guarded = true
	_set_step(Step.DONE)
	return true


## The pair are down. A player who never needed the guard tip still ends the
## lesson here instead of carrying it into the latches.
func note_fight_over() -> bool:
	if _step != Step.FIGHT:
		return false
	_set_step(Step.DONE)
	return true


# --- answers ---------------------------------------------------------------

func step() -> int:
	return _step


func step_name() -> String:
	match _step:
		Step.DORMANT:
			return "dormant"
		Step.MOVE:
			return "move"
		Step.FETCH:
			return "fetch"
		Step.FIGHT:
			return "fight"
		Step.DONE:
			return "done"
	return "unknown"


## Whether the lesson still owns the prompt and the key line.
func active() -> bool:
	return _step == Step.MOVE or _step == Step.FETCH or _step == Step.FIGHT


## Whether the pair may wake: the player is holding a weapon and the fight is the
## lesson. Nothing hunts before this.
func fighting() -> bool:
	return _step == Step.FIGHT


func armed() -> bool:
	return _step == Step.FIGHT or _step == Step.DONE


func guarded() -> bool:
	return _guarded


## Whether the three cuts have been named (they are, the moment the blade is taken).
func cuts_tip() -> bool:
	return _cuts_tip


func guard_tip() -> bool:
	return _guard_tip


## The one command above the crosshair while this lesson runs. Read fresh on
## every call, so a beat that changed cannot leave a stale label behind.
func objective() -> String:
	match _step:
		Step.MOVE:
			return "Walk to the ironwood shiv"
		Step.FETCH:
			return "Take the ironwood shiv"
		Step.FIGHT:
			if _guard_tip and not _guarded:
				return "Guard the blow"
			return "Put the pair down"
	return ""


## The key line under it: exactly what to press, this beat.
func hint() -> String:
	match _step:
		Step.MOVE:
			return "W A S D  -  walk   ·   SHIFT  -  run   ·   MOUSE  -  look"
		Step.FETCH:
			return "K  -  take the ironwood shiv"
		Step.FIGHT:
			if _guard_tip and not _guarded:
				return "HOLD RMB  -  guard   ·   let go to swing"
			return "LMB  -  cut   ·   WHEEL_UP  -  stab   ·   WHEEL_DOWN  -  overhead"
	return ""


## Forget every beat (a fresh campaign starts the lesson again).
func reset() -> void:
	_step = Step.DORMANT
	_cuts_tip = false
	_guard_tip = false
	_guarded = false
	_first_windup = 0


func _set_step(next: int) -> void:
	if next == _step:
		return
	_step = next
	step_changed.emit(_step)
