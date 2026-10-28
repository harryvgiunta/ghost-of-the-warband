class_name DuelLesson
extends Node
## GHOST OF THE WARBAND: the first fight, taught in four beats.
##
## The camp's opening hands the player Corvin's body with empty hands: his shiv
## is in the dirt where the pair threw it, and the two watchers between the cages
## and the mouth are the first thing the player has to kill. This node is the
## lesson that makes that fight playable by somebody who has never held a mouse
## in this game:
##
##   1. **MOVE** - the soul is in his body, and walking is the first thing a new
##      player needs. Nothing hunts them yet.
##   2. **FETCH** - the shiv lies a few paces up the pocket. Pressing `K` over it
##      is the whole lesson; the warband takes the piece into that body's hands.
##   3. **SWING** - the moment the player swings is the moment to name the three
##      cuts, because that is when the question is being asked.
##   4. **GUARD** - the second watcher's first windup is the moment to teach the
##      guard, and the card holds the game still while it is read.
##
## The node owns no scene lookups: the camp feeds it facts and shows the cards it
## asks for. Every transition is guarded, so a scene that fires an event early
## (a swing before the shiv, a guard before the card) is ignored rather than
## throwing the lesson out of sequence. Facts arrive at most once per name.

signal step_changed(step: int)
## A card should open. The card itself is the scene's business.
signal card_wanted(card: int)

enum Step { DORMANT, MOVE, FETCH, FIGHT, DONE }
## The four cards, in the order the lesson asks for them. The guard is a card,
## not a step: the fight is one beat from the shiv to the last body on the dirt.
enum Card { MOVE, FETCH, SWING, GUARD }

var _step := Step.DORMANT
var _cuts_card := false
var _guard_card := false
var _guarded := false
## The watcher whose windup opened the exchange. The guard lesson belongs to the
## other one - unless only one is left standing, and then it is his as well.
var _first_windup := 0

## The soul stepped into the rescuer. This is the first beat and the only way in.
func note_taken() -> bool:
	if _step != Step.DORMANT:
		return false
	_set_step(Step.MOVE)
	card_wanted.emit(Card.MOVE)
	return true

## The body standing on the shiv. The card asks for the key that takes it.
func note_shiv_near() -> bool:
	if _step != Step.MOVE:
		return false
	_set_step(Step.FETCH)
	card_wanted.emit(Card.FETCH)
	return true

## The shiv left the dirt and went into a hand. That is the frame the cuts are
## taught on - the moment a new player is armed is the moment they ask how to
## swing - so the card is raised here, before the pair are given a single frame to
## close in. The fight may wake from this point and not before.
func note_shiv_taken() -> bool:
	if _step != Step.MOVE and _step != Step.FETCH:
		return false
	_cuts_card = true
	_set_step(Step.FIGHT)
	card_wanted.emit(Card.SWING)
	return true

## A watcher's windup started. The guard card belongs to the *second* of the pair:
## the first body to raise its club opens the exchange and the other one is the
## one the card is written for. With a single watcher left standing it teaches the
## card itself, because there is no second. `pair_alive` is how many of the pair
## are still up.
func note_windup(watcher_id: int, pair_alive: int = 2) -> bool:
	if _step != Step.FIGHT or _guard_card or _guarded:
		return false
	if _first_windup == 0:
		_first_windup = watcher_id
	if watcher_id == _first_windup and pair_alive > 1:
		return false
	_guard_card = true
	card_wanted.emit(Card.GUARD)
	return true

## A blow landed on a raised guard. The lesson is done: the player has blocked
## once, which is what the last card asked for.
func note_guarded() -> bool:
	if _step != Step.FIGHT or not _guard_card or _guarded:
		return false
	_guarded = true
	_set_step(Step.DONE)
	return true

## The pair are down. A player who never needed the guard card still ends the
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

## Whether the lesson still owns the keys, the prompt and the objective.
func active() -> bool:
	return _step == Step.MOVE or _step == Step.FETCH or _step == Step.FIGHT

## Whether the pair may wake: the player is holding a weapon and the fight is
## the lesson. Nothing hunts before this.
func fighting() -> bool:
	return _step == Step.FIGHT

func armed() -> bool:
	return _step == Step.FIGHT or _step == Step.DONE

func guarded() -> bool:
	return _guarded

## Whether the three cuts have been named (they are, the moment the shiv is taken).
func cuts_card() -> bool:
	return _cuts_card

func guard_card() -> bool:
	return _guard_card

## The one line above the crosshair while this lesson runs. Read fresh on every
## call, so a beat that changed a count cannot leave a stale label behind.
func objective() -> String:
	match _step:
		Step.MOVE:
			return "Your shiv lies in the dirt up the pocket. Walk to it."
		Step.FETCH:
			return "Take the ironwood shiv off the ground."
		Step.FIGHT:
			if _guard_card and not _guarded:
				return "The second watcher is on you. Raise your guard."
			return "Put the pair down. Latches come after."
	return ""

## The key line under it: exactly what to press, this beat.
func hint() -> String:
	match _step:
		Step.MOVE:
			return "W A S D  -  walk   ·   SHIFT  -  run   ·   MOUSE  -  look around"
		Step.FETCH:
			return "K  -  take the ironwood shiv"
		Step.FIGHT:
			if _guard_card and not _guarded:
				return "HOLD RMB  -  guard   ·   let go to swing again"
			return "LMB  -  cut   ·   WHEEL_UP  -  stab   ·   WHEEL_DOWN  -  overhead   ·   HOLD RMB  -  guard"
	return ""

## Forget every beat (a fresh campaign starts the lesson again).
func reset() -> void:
	_step = Step.DORMANT
	_cuts_card = false
	_guard_card = false
	_guarded = false
	_first_windup = 0

func _set_step(next: int) -> void:
	if next == _step:
		return
	_step = next
	step_changed.emit(_step)
