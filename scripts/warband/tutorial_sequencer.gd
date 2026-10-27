class_name TutorialSequencer
extends Node
## GHOST OF THE WARBAND: the opening tutorial's one state machine.
##
## Four prisoners hang in one corner of the world, a fifth is loose, and the way
## out is a walk. The order is the lesson:
##   1. shift the soul through all four caged bodies (that is the whole premise);
##   2. the fifth prisoner jogs in with a shiv and kills the two watchers himself:
##      taking his body is the player's beat, and theirs is nothing;
##   3. the soul steps into him - that is what cuts all four latches at once, and
##      no latch moves while the pair are still standing over the cages;
##   4. the squad is out and arming itself off the ground;
##   5. the escape: the soul walking through the clearing's mouth is what turns
##      the trees loose on the squad. There is no door to press and no kill quota
##      to fill - ESCAPING is where this machine ends.
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
## The watchers the wood fields at the camp: the pair Corvin puts down and the six
## that come out of the trees as the squad leaves. The tally is the objective's -
## it does not gate the escape, because the leaving is the ambush.
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
				return "Corvin is at the watchers. Take his body - F5 or [ ]."
			return "Put the pair down. Every latch goes when they fall."
		State.FREED:
			return "Out and armed. Walk out through the mouth   ·   watchers down %d/%d" \
				% [_guards_down, GUARD_COUNT]
		State.ESCAPING:
			return "The trees answer. Run the trail - the town is at the far end."
	return ""

## The key line under the objective: exactly what to press, this beat. Every
## step names its own key, because a tutorial that says "take his body" and not
## "F5" has taught nothing. No step names a latch key: latches are not pressed.
func hint() -> String:
	match _state:
		State.CAGED:
			return "[ ] or F1..F4 - enter another prisoner   ·   TAB - warband   ·   P - gear"
		State.ALL_SEEN:
			return "Stay in a body - Corvin is walking in with the shiv."
		State.RESCUER_ARRIVED:
			if not _rescuer_taken:
				return "F5 or [ ] - take Corvin's body   ·   he cuts every latch himself"
			return "LMB / RMB - fight the pair   ·   the latches go when they are down"
		State.FREED:
			return "W A S D - walk out through the mouth   ·   the squad arms itself"
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

## The fifth prisoner reached the cages: the pair are his now, and the soul is
## still where the player left it. Refused unless all four bodies were seen
## first, and only ever once.
func note_rescuer_arrived() -> bool:
	if _state != State.ALL_SEEN or _rescuer_noted:
		return false
	_rescuer_noted = true
	_transition(State.RESCUER_ARRIVED)
	rescuer_ready.emit(rescuer_merc_id)
	return true

## The soul actually entered the rescuer's body. The tutorial never moves it
## there for you: the card and the objective both name the key, and this is what
## cuts the latches (the scene holds them until the pair are down).
func note_rescuer_taken() -> bool:
	if _state != State.RESCUER_ARRIVED or _rescuer_taken:
		return false
	_rescuer_taken = true
	announce()
	return true

func rescuer_taken() -> bool:
	return _rescuer_taken

## A cage latch was cut. The scene cuts all four in one act when the soul is in
## Corvin's hands; a cage still counts once, and the fourth opens the squad.
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

## A watcher died. Corvin's own kills count - he puts the first pair down himself
## and the tally has to read true - so anything from the moment he is at the cages
## on is progress. Nothing counts before the fight starts.
func note_guard_killed() -> bool:
	if _state == State.CAGED or _state == State.ALL_SEEN:
		return false
	if _guards_down >= GUARD_COUNT:
		return false
	_guards_down += 1
	announce()
	return true

## A cultist weapon left the battlefield in a soul's hands.
func note_weapon_looted() -> bool:
	if _state == State.CAGED or _state == State.ALL_SEEN:
		return false
	_weapons += 1
	announce()
	return true

## The soul walked out of the clearing's mouth. This - not a body count - is the
## escape: the scene answers it by turning the wood loose on the squad.
func note_escaped() -> bool:
	if _state != State.FREED:
		return false
	_transition(State.ESCAPING)
	return true

func _transition(next: int) -> void:
	if next == _state:
		return
	_state = next
	announce()
