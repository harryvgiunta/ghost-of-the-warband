class_name TutorialSequencer
extends Node
## GHOST OF THE WARBAND: the opening's one state machine, and the only part of
## the game that teaches.
##
## Five prisoners are held in one camp. The player wakes in the first of them,
## shut in a cage, and the five beats are the five things a new player has to do:
##
##   1. **CAGED** - take the blade through the bars, then cut your own latch. The
##      shiv lies on the dirt outside the cell door; `K` reaches it through the
##      bars, and `G` is what the new steel opens. Nothing else opens the cage.
##   2. **LOOSE** - out of the cage and into the camp. The first step away from
##      the bars is what "getting your bearings" means here, and the beat ends on
##      it: no timer, no line to read.
##   3. **FREEING** - the objective: the four still shut in the wood. The camp's
##      own lesson (`duel_lesson.gd`) takes the prompt while the player arms
##      itself and puts the pair down; the sequencer's line is the count.
##   4. **WARBAND** - five bodies on their feet. The objective turns over: the way
##      on is the town, and the town is down the trail.
##   5. **ESCAPING** - the squad walked out through the gap in the trees. That is
##      the ending of the opening, not a kill quota: the ambush is the leaving.
##
## This node owns no scene lookups - no bodies, no labels, no nodes. The scene
## feeds it facts and it answers with a state, one objective line and one key
## line. Every transition is guarded, so a scene that fires events early is
## ignored instead of throwing the opening out of sequence. Facts arrive at most
## once per name.

signal state_changed(state: int, objective: String)

enum State { CAGED, LOOSE, FREEING, WARBAND, ESCAPING }

## The five cages the squad is held in. The player wakes in the first.
const CAGE_COUNT := 5
## The watchers the camp fields: the pair between the cages and the mouth, and
## the four that come out of the trees as the squad leaves (`Camp.AMBUSH_COUNT`).
## The tally is the checkpoint's - it does not gate the escape, because the
## leaving is the ambush.
const GUARD_COUNT := 6

var _state := State.CAGED
var _started := false
var _opened: Array[int] = []
var _guards_down := 0
var _weapons := 0
## The caged body has the blade in hand (taken through the bars). It is the one
## fact the CAGED line needs: the shiv is the errand until it is taken, and the
## latch it can cut is the errand after.
var _armed := false


## Announce the opening state. Idempotent: re-entering the camp (or a scene that
## calls setup twice) never rewinds progress.
func begin() -> void:
	if _started:
		return
	_started = true
	announce()


## Re-emit the current state and objective so the HUD can redraw after a count
## changed without a transition ("2/5").
func announce() -> void:
	state_changed.emit(_state, objective())


func state() -> int:
	return _state


func started() -> bool:
	return _started


func state_name() -> String:
	return state_name_of(_state)


static func state_name_of(value: int) -> String:
	match value:
		State.CAGED:
			return "caged"
		State.LOOSE:
			return "loose"
		State.FREEING:
			return "freeing"
		State.WARBAND:
			return "warband"
		State.ESCAPING:
			return "escaping"
	return "unknown"


## What the HUD shows. Read fresh on every call, so the counters are never a
## stale label somebody forgot to refresh.
func objective() -> String:
	match _state:
		State.CAGED:
			# The blade is the first errand: it lies on the dirt outside the door
			# and is the only thing a caged body can reach. The latch follows.
			return "Cut your latch" if _armed else "Take the shiv through the bars"
		State.LOOSE:
			return "Get your bearings"
		State.FREEING:
			return "Free your warband   %d/%d" % [_opened.size(), CAGE_COUNT]
		State.WARBAND:
			return "Run to the town"
		State.ESCAPING:
			# The world's own line - the trail and the metres to the town - is
			# what a body needs past the mouth, not a stale instruction.
			return ""
	return ""


## The key line under the objective: exactly what to press, this beat.
func hint() -> String:
	match _state:
		State.CAGED:
			return "G  -  pick the latch" if _armed else "K  -  take the ironwood shiv"
		State.LOOSE:
			return "W A S D  -  walk   ·   MOUSE  -  look"
		State.FREEING:
			return "G  -  cut a latch   ·   K  -  take a weapon"
		State.WARBAND:
			return "W A S D  -  run   ·   follow the gold arrow"
		State.ESCAPING:
			return "W A S D  -  run the trail   ·   the town is at the far end"
	return ""


func cages_opened() -> int:
	return _opened.size()


func opened_cages() -> Array[int]:
	return _opened.duplicate()


func is_cage_opened(index: int) -> bool:
	return _opened.has(index)


func guards_down() -> int:
	return _guards_down


func weapons_taken() -> int:
	return _weapons


## Whether the whole squad is out: five latches cut, five bodies on their feet.
func warband_free() -> bool:
	return _opened.size() >= CAGE_COUNT


## One cage latch was cut. Index 0 is the player's own cage, and opening it is
## the first beat: the opening moves on to the camp. The rest are the objective,
## and the fifth is the end of it.
##
## A latch is a fact, not a permission, so it is booked whatever beat the opening
## is on - a body that somehow cuts one early cuts metal and skips nothing.
func note_cage_opened(index: int) -> bool:
	if index < 0 or index >= CAGE_COUNT or _opened.has(index):
		return false
	_opened.append(index)
	if _state == State.CAGED and index == 0:
		_transition(State.LOOSE)
	elif _state == State.LOOSE and warband_free():
		_transition(State.WARBAND)
	elif _state == State.FREEING and warband_free():
		_transition(State.WARBAND)
	else:
		announce()
	return true


## The freed body stepped away from its own cage: that is the whole of the
## bearings beat. Refused from anywhere but LOOSE, and only ever once.
func note_looked_around() -> bool:
	if _state != State.LOOSE:
		return false
	_transition(State.FREEING)
	return true


## A watcher died. Anything from the moment the squad is loose counts - the camp
## has to read true about its own guards.
func note_guard_killed() -> bool:
	if _state == State.CAGED or _guards_down >= GUARD_COUNT:
		return false
	_guards_down += 1
	return true


## A weapon left the battlefield in a soul's hands.
func note_weapon_looted() -> bool:
	if _state == State.CAGED:
		return false
	_weapons += 1
	return true


## The caged body reached the shiv through the bars. Booked as a fact like a latch:
## the CAGED line turns from the blade to the latch the blade opens, and no state
## changes - the cage is still shut until `note_cage_opened` says otherwise.
func note_armed() -> bool:
	if _armed:
		return false
	_armed = true
	announce()
	return true


## Whether the caged body holds the blade (read by the camp's own prompt).
func armed() -> bool:
	return _armed


## The squad walked out of the clearing's mouth. This - not a body count - is the
## escape: the scene answers it by turning the wood loose on the squad.
func note_escaped() -> bool:
	if _state != State.WARBAND:
		return false
	_transition(State.ESCAPING)
	return true


func _transition(next: int) -> void:
	if next == _state:
		return
	_state = next
	announce()
