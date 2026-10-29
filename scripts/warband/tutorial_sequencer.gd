class_name TutorialSequencer
extends Node
## GHOST OF THE WARBAND: the opening tutorial's one state machine.
##
## Four prisoners hang in one corner of the world, a fifth is loose, and the way
## out is a walk. The order is the lesson:
##   1. shift the soul through all four caged bodies (that is the whole premise);
##   2. the fifth prisoner jogs in with empty hands - the pair took his shiv off
##      him at the mouth - and stops at the cage line: taking his body is the
##      player's beat, and nothing fights for them;
##   3. the soul steps into him, and the first fight's lesson (`duel_lesson.gd`)
##      takes over: walk, pick the shiv out of the dirt, cut, and guard. Then the
##      player walks cage to cage cutting one latch at a time;
##   4. the fourth latch is the squad out and arming itself off the ground;
##   5. the escape: the soul walking out through the gap in the trees is what
##      turns the wood loose on the squad. There is no door to press and no kill
##      quota to fill - ESCAPING is where this machine ends.
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
## The watchers the wood fields at the camp: the pair Corvin puts down and the
## four that come out of the trees as the squad leaves (`CampScript.AMBUSH_COUNT`).
## The tally is the objective's - it does not gate the escape, because the leaving
## is the ambush.
const GUARD_COUNT := 6

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
				return "Corvin is at the cage line with empty hands. Take his body - F5 or [ ] - and get his shiv back."
			return "Cut a latch at each cage   %d/%d" % [_opened.size(), PRISONER_COUNT]
		State.FREED:
			return "Out and armed. Walk out through the mouth   ·   watchers down %d/%d" \
				% [_guards_down, GUARD_COUNT]
		State.ESCAPING:
			return "The trees answer. Run the trail - the town is at the far end."
	return ""

## The key line under the objective: exactly what to press, this beat. Every
## step names its own key, because a tutorial that says "take his body" and not
## "F5" has taught nothing. `G` is only ever advertised where it cuts a latch -
## never as a general interact key.
func hint() -> String:
	match _state:
		State.CAGED:
			return "[ ] or F1..F4 - enter another prisoner   ·   O - warband   ·   P - gear"
		State.ALL_SEEN:
			return "Stay in a body - Corvin is walking in with empty hands."
		State.RESCUER_ARRIVED:
			if not _rescuer_taken:
				return "F5 or [ ] - take Corvin's body   ·   K  -  take a weapon off the ground"
			return "G  -  cut a latch  ·  %d of %d cages" % [_opened.size(), PRISONER_COUNT]
		State.FREED:
			return "W A S D - walk out through the mouth   ·   the squad arms itself"
		State.ESCAPING:
			return "W A S D - run the trail through the wood   ·   the town is at the far end of it"
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
	# Four latches cut before he got here still free the squad the moment the
	# lesson reaches the beat that owns them.
	_maybe_free_squad()
	rescuer_ready.emit(rescuer_merc_id)
	return true

## The soul actually entered the rescuer's body. The tutorial never moves it
## there for you: the card and the objective both name the key, and this is what
## puts the camp's only blade in the player's hands.
func note_rescuer_taken() -> bool:
	if _state != State.RESCUER_ARRIVED or _rescuer_taken:
		return false
	_rescuer_taken = true
	announce()
	return true

func rescuer_taken() -> bool:
	return _rescuer_taken

## A cage latch was cut, one cage at a time. A latch is a fact, not a permission,
## so it is booked whatever beat the lesson is on - but the squad is only loosed
## at four and only from the beat that owns them, so a player who somehow gets to
## a cage early cuts metal and skips nothing.
func note_cage_opened(index: int) -> bool:
	if index < 0 or index >= PRISONER_COUNT or _opened.has(index):
		return false
	_opened.append(index)
	announce()
	_maybe_free_squad()
	return true


## Four latches and the beat that owns them: the squad is out. Called after every
## latch and again when the rescuer arrives, so four latches cut early still free
## the squad on the frame the lesson reaches them.
func _maybe_free_squad() -> void:
	if _opened.size() >= PRISONER_COUNT and _state == State.RESCUER_ARRIVED:
		_transition(State.FREED)

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
