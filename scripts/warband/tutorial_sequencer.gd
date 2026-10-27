class_name TutorialSequencer
extends Node
## GHOST OF THE WARBAND: the opening tutorial's one state machine.
##
## Four prisoners hang in the cultist camp, a fifth is loose and the gate is the
## only way out. The order is the lesson: shift the soul through all four caged
## bodies, wait for the man with the shiv, then take his body, loot the steel and
## kill the two gate guards before the gate will let anyone leave.
##
## This node owns no scene lookups - no bodies, no labels, no nodes. The scene
## feeds it facts (`note_body_entered`, `note_guard_killed`, ...) and it answers
## with a state, one objective line and three signals. Every transition is
## guarded, so a scene that fires events early (a stray `note_gate_reached`, a
## freed call before the rescuer ever arrived) is ignored instead of throwing the
## tutorial out of sequence.
##
## Facts arrive at most once per name: a possessed body re-entered twice, a drop
## collected by a sweep and by hand, or two guard deaths landing on one frame all
## still count once.

signal state_changed(state: int, objective: String)
signal rescuer_ready(merc_id: int)
signal gate_ready()

enum State { CAGED, ALL_SEEN, RESCUER_ARRIVED, FREED, ESCAPING, TOWN }

## Bodies the lesson is built around. The scene must cage exactly this many.
const PRISONER_COUNT := 4
## Gate guards that have to fall before the escape is on.
const GUARD_COUNT := 2
## Cultist steel that has to be in hand: one piece is enough to arm a soul.
const REQUIRED_WEAPONS := 1

## The loose prisoner's mercenary id, set through `begin()`.
var rescuer_merc_id := -1

var _state := State.CAGED
var _started := false
var _seen: Array[int] = []
var _guards_down := 0
var _weapons := 0
var _freed_called := false
var _rescuer_noted := false
var _gate_noted := false

## Announce the opening state. Idempotent: re-entering the camp (or a scene that
## calls setup twice) never rewinds progress.
func begin(rescuer_id: int = -1) -> void:
	if _started:
		return
	_started = true
	rescuer_merc_id = rescuer_id
	announce()

## Re-emit the current state and objective so the HUD can redraw after a count
## changed without a transition ("1/4 prisoners seen").
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
		State.TOWN:
			return "town"
	return "unknown"

## What the HUD shows. Read fresh on every call, so the counters are never a
## stale label somebody forgot to refresh.
func objective() -> String:
	match _state:
		State.CAGED:
			return "Shift your soul between the four prisoners   %d/%d" % [_seen.size(), PRISONER_COUNT]
		State.ALL_SEEN:
			return "All four seen. The fifth prisoner is working the latches."
		State.RESCUER_ARRIVED:
			return "He is through. Take his body."
		State.FREED:
			return "Take the cultist steel and put down the gate guards   steel %d  guards %d/%d" \
				% [_weapons, _guards_down, GUARD_COUNT]
		State.ESCAPING:
			return "Both guards are down. Walk into the gate."
		State.TOWN:
			return "The gate is open. Out of the camp."
	return ""

func seen_count() -> int:
	return _seen.size()

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
## seen first, and only ever once.
func note_rescuer_arrived() -> bool:
	if _state != State.ALL_SEEN or _rescuer_noted:
		return false
	_rescuer_noted = true
	_transition(State.RESCUER_ARRIVED)
	rescuer_ready.emit(rescuer_merc_id)
	return true

## The cages are open. The scene calls this after the rescuer's latch, never
## before: freeing the squad is what the whole first beat pays for.
func note_freed() -> bool:
	if _state != State.RESCUER_ARRIVED or _freed_called:
		return false
	_freed_called = true
	_transition(State.FREED)
	return true

## A gate guard died. Counted only during the fight; a kill before the squad is
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

## The freed body stepped into the gate arch. Only meaningful once the fight is
## over; a body leaning on the gate during the lesson advances nothing.
func note_gate_reached() -> bool:
	if _state != State.ESCAPING or _gate_noted:
		return false
	_gate_noted = true
	_transition(State.TOWN)
	gate_ready.emit()
	return true

func _check_escape() -> void:
	if _state != State.FREED:
		return
	if _guards_down >= GUARD_COUNT and _weapons >= REQUIRED_WEAPONS:
		_transition(State.ESCAPING)
	else:
		announce()

func _transition(next: int) -> void:
	if next == _state:
		return
	_state = next
	announce()
