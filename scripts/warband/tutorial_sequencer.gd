class_name TutorialSequencer
extends Node
## GHOST OF THE WARBAND: the opening tutorial's one state machine.
##
## Four prisoners hang in one corner of the world, a fifth is loose, and the way
## out is a walk. The order is the lesson:
##   1. shift the soul through all four caged bodies (that is the whole premise);
##   2. the fifth prisoner jogs in with a shiv and stands still: taking his body
##      is the player's beat;
##   3. walk to each cage and press G to cut its latch - four latches, four cages;
##   4. take the cultist steel and put down the two antlered watchers, then the six
##      that come out of the trees;
##   5. the escape: the clearing's mouth opens onto the trail through the wood,
##      and the town is at the far end of it. There is no door to press and no
##      scene to change - ESCAPING is where this machine ends.
##
## This node owns no scene lookups - no bodies, no labels, no nodes. The scene
## feeds it facts and it answers with a state, one objective line, one key hint
## and three signals. Every transition is guarded, so a scene that fires events
## early is ignored instead of throwing the tutorial out of sequence.
##
## Facts arrive at most once per name: a possessed body re-entered twice, a drop
## collected twice, or two kills landing on one frame all still count once.

signal state_changed(state: int, objective: String)
signal rescuer_ready(merc_id: int)

enum State { CAGED, ALL_SEEN, RESCUER_ARRIVED, FREED, ESCAPING }

## Bodies the lesson is built around. The scene must cage exactly this many.
const PRISONER_COUNT := 4
## Gate watchers that have to fall before the escape is on: the first pair and
## the six armed ones that come through when they die.
const GUARD_COUNT := 8

## The loose prisoner's mercenary id, set through `begin()`.
var rescuer_merc_id := -1

var _state := State.CAGED
var _started := false
var _seen: Array[int] = []
var _opened: Array[int] = []
var _guards_down := 0
var _weapons := 0
var _rescuer_noted := false
var _rescuer_taken := false

## Announce the opening state. Idempotent: re-entering the camp (or a scene that
## calls setup twice) never rewinds progress.
func begin(rescuer_id: int = -1) -> void:
	if _started:
		return
	_started = true
	rescuer_merc_id = rescuer_id
	announce()

## Re-emit the current state and objective so the HUD can redraw after a count
## changed without a transition ("2/4 latches cut").
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
		State.ALL_SEEN:
			return "all_seen"
		State.RESCUER_ARRIVED:
			return "rescuer_arrived"
		State.FREED:
			return "freed"
		State.ESCAPING:
			return "escaping"
	return "unknown"

## What the HUD shows. Read fresh on every call, so the counters are never a
## stale label somebody forgot to refresh.
func objective() -> String:
	match _state:
		State.CAGED:
			return "Shift your soul between the four prisoners   %d/%d" % [_seen.size(), PRISONER_COUNT]
		State.ALL_SEEN:
			return "All four seen. The fifth prisoner is coming."
		State.RESCUER_ARRIVED:
			if not _rescuer_taken:
				return "Corvin is through. Take his body - F5 or [ ]."
			return "Cut each latch with G   %d/%d" % [_opened.size(), PRISONER_COUNT]
		State.FREED:
			return "Put down the watchers   %d/%d" % [_guards_down, GUARD_COUNT]
		State.ESCAPING:
			return "The way is clear. The trail through the wood leads to town."
	return ""

## The key line under the objective: exactly what to press, this beat. Every
## step names its own key, because a tutorial that says "free the squad" and not
## "G" has taught nothing.
func hint() -> String:
	match _state:
		State.CAGED:
			return "[ ] or F1..F4 - enter another prisoner   ·   TAB - warband   ·   P - gear"
		State.ALL_SEEN:
			return "Stay in a body - Corvin is walking in with the shiv."
		State.RESCUER_ARRIVED:
			if not _rescuer_taken:
				return "F5 or [ ] - take Corvin's body   ·   then G at a cage to cut its latch"
			return "G - cut this cage's latch   ·   walk to each cage"
		State.FREED:
			return "LMB / RMB - fight   ·   E - revive   ·   the squad arms itself"
		State.ESCAPING:
			return "W A S D - walk the trail   ·   the town is at the far end of the wood"
	return ""

func seen_count() -> int:
	return _seen.size()

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

## One of the caged bodies got a soul. Only the first four distinct bodies count,
## and only while the lesson is still on its first beat.
func note_body_entered(merc_id: int) -> bool:
	if not _started or _state != State.CAGED or merc_id <= 0:
		return false
	if _seen.has(merc_id) or _seen.size() >= PRISONER_COUNT:
		return false
	_seen.append(merc_id)
	if _seen.size() >= PRISONER_COUNT:
		_transition(State.ALL_SEEN)
	else:
		announce()
	return true

## The fifth prisoner reached the cages. Refused unless all four bodies were
## seen first, and only ever once. The scene forces the soul into him next.
func note_rescuer_arrived() -> bool:
	if _state != State.ALL_SEEN or _rescuer_noted:
		return false
	_rescuer_noted = true
	_transition(State.RESCUER_ARRIVED)
	rescuer_ready.emit(rescuer_merc_id)
	return true

## The soul actually entered the rescuer's body. The tutorial never moves it
## there for you: the card and the objective both name the key, and until this
## fires no latch can be cut.
func note_rescuer_taken() -> bool:
	if _state != State.RESCUER_ARRIVED or _rescuer_taken:
		return false
	_rescuer_taken = true
	announce()
	return true

func rescuer_taken() -> bool:
	return _rescuer_taken

## One cage latch was cut by the player. A cage counts once; the fourth opens the
## squad and starts the fight.
func note_cage_opened(index: int) -> bool:
	if _state != State.RESCUER_ARRIVED or index < 0 or index >= PRISONER_COUNT:
		return false
	if _opened.has(index):
		return false
	_opened.append(index)
	if _opened.size() >= PRISONER_COUNT:
		_transition(State.FREED)
	else:
		announce()
	return true

## A gate watcher died. Counted only during the fight; a kill before the squad is
## out is a scene bug, not progress.
func note_guard_killed() -> bool:
	if _state != State.FREED or _guards_down >= GUARD_COUNT:
		return false
	_guards_down += 1
	_check_escape()
	return true

## A cultist weapon left the battlefield in a soul's hands.
func note_weapon_looted() -> bool:
	if _state != State.FREED:
		return false
	_weapons += 1
	_check_escape()
	return true

## Reconcile the fight with what is already true. A squadmate can put a watcher
## down (or take the steel) while the player is still cutting the last latches;
## `note_guard_killed` refuses those as progress because the squad is not out
## yet, so the scene hands the running totals over the moment FREED begins.
## Monotonic: it can only raise a counter, never rewind one.
func note_battle_state(guards_down: int, weapons: int) -> void:
	if _state != State.FREED:
		return
	var before := _guards_down * 1000 + _weapons
	_guards_down = clampi(maxi(_guards_down, guards_down), 0, GUARD_COUNT)
	_weapons = maxi(_weapons, weapons)
	# Silent when nothing moved: `_check_escape` announces, and a listener that
	# calls back in on every announce would otherwise recurse forever.
	if _guards_down * 1000 + _weapons == before:
		return
	_check_escape()

func _check_escape() -> void:
	if _state != State.FREED:
		return
	if _guards_down >= GUARD_COUNT:
		_transition(State.ESCAPING)
	else:
		announce()

func _transition(next: int) -> void:
	if next == _state:
		return
	_state = next
	announce()
