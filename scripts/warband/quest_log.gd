class_name WarbandQuests
extends RefCounted
## GHOST OF THE WARBAND: the campaign's ledger of what the quartermaster wants.
##
## A quest is a definition row (`DEFS`) and one fact per body: which of the five
## states it is in and how far its one goal has got (`_states`, `_progress`).
## The row says which *kind* of goal it is, and every kind counts one thing:
##
##   KILL    a mob id (`note_kill`)            - "kill 20 of the watchers"
##   RESCUE  a body brought out of a cage      - "free 4 soldiers"
##   COLLECT an item taken into the stash      - "bring me the ichor"
##   APPLY   a reagent worked into a weapon    - "...and bind it to steel"
##   REACH   a named place (`note_reached`)    - "find the Crypt" (a shell)
##
## Those five are the whole vocabulary on purpose: the two common shapes the
## campaign needs - kill X of a thing, rescue X bodies - are rows in this table,
## not code paths, so a new bounty is a definition and a `note_*` call from the
## world rather than a new state machine. Nothing here knows about a scene, a
## node, a card or a HUD: the log is pure state, which is what makes it savable
## and testable, and `QuestGiver` is the one thing that turns it into dialogue.
##
## Progress rides in `warband_state.json` (save version 5) beside the roster and
## the stash, so a checkpoint carries the objectives the player has accepted.

signal changed
## Raised the frame a quest's goal is met (before it is turned in).
signal quest_completed(quest_id: String)

enum State { HIDDEN, OFFERED, ACTIVE, COMPLETE, CLOSED }
enum Goal { KILL, RESCUE, COLLECT, APPLY, REACH }

## Save shape of the progress section. v1 is the only version so far.
const SAVE_VERSION := 1
## The four quests the campaign opens with, in chain order. `next` is what the
## quartermaster hands over when the row before it is turned in.
const IDS := [
	"free_the_soldiers",
	"cull_the_watchers",
	"find_the_crypt",
	"bind_the_ichor",
]

## The one gate every campaign quest is measured against: twenty watchers is
## what the quartermaster asks for, and four bodies is a cage line.
const WATCHER_KILLS := 20
const SOLDIER_RESCUES := 4
const WATCHER_ID := "hollow_warden"
const ICHOR_ID := "ichor_vial"

## One row per order, and every row is the whole of what an order says: a
## title, one line of what is wanted, one key line, and the next link. There is
## no prose here any more - the ledger row on the HUD is what a player reads, and
## a keeper hands an order over with a single tip.
const DEFS := {
	"free_the_soldiers": {
		"title": "THE CAGES IN THE WOOD",
		"kicker": "THE QUARTERMASTER",
		"giver": "quartermaster",
		"kind": Goal.RESCUE,
		"target": "",
		"count": SOLDIER_RESCUES,
		"line": "Free the soldiers caged in the wood",
		"hint": "G at a cage with a blade in your hand",
		"keys": "G - cut a cage latch",
		"done": "Four cages open.",
		"next": "cull_the_watchers",
	},
	"cull_the_watchers": {
		"title": "CULL THE HOLLOW WATCHERS",
		"kicker": "THE QUARTERMASTER",
		"giver": "quartermaster",
		"kind": Goal.KILL,
		"target": WATCHER_ID,
		"count": WATCHER_KILLS,
		"line": "Kill the hollow watchers",
		"hint": "RMB - guard   ·   LMB - swing",
		"keys": "LMB - swing   ·   RMB - guard   ·   WHEEL - stab / overhead",
		"done": "Twenty down.",
		"next": "find_the_crypt",
	},
	"find_the_crypt": {
		"title": "FIND THE CRYPT",
		"kicker": "THE QUARTERMASTER",
		"giver": "quartermaster",
		"kind": Goal.REACH,
		"target": "crypt",
		"count": 1,
		"line": "Find the Crypt",
		"hint": "M - the map",
		"keys": "M - the map",
		"done": "You found it.",
		"next": "",
	},
	"bind_the_ichor": {
		"title": "ICHOR IN THE STEEL",
		"kicker": "THE QUARTERMASTER",
		"giver": "quartermaster",
		"kind": Goal.APPLY,
		"target": ICHOR_ID,
		"count": 1,
		"line": "Bind the warden's ichor into a weapon",
		"hint": "G - the ichor bench",
		"keys": "G - the ichor bench   ·   R - loose the sigil",
		"done": "The steel drinks.",
		"next": "",
	},
}

## `id -> State`, kept sparse: a quest with no entry is HIDDEN.
var _states: Dictionary = {}
## `id -> int` kills/rescues/items counted so far.
var _progress: Dictionary = {}
## Item ids already credited through `note_collected`/`note_applied`, so a
## re-read of the stash cannot count one vial twice.
var _credited: Array[String] = []


# --- reading ---------------------------------------------------------------

func has(quest_id: String) -> bool:
	return DEFS.has(quest_id)

## The definition row for a quest, or `{}`. Static so a card builder can read
## the copy without an instance.
static func def_of(quest_id: String) -> Dictionary:
	return DEFS.get(quest_id, {})

func state_of(quest_id: String) -> int:
	return int(_states.get(quest_id, State.HIDDEN))

## `"hidden"`, `"offered"`, `"active"`, `"complete"` or `"closed"` - the word a
## test or a log line can assert instead of an enum.
static func state_name_of(state: int) -> String:
	match state:
		State.OFFERED:
			return "offered"
		State.ACTIVE:
			return "active"
		State.COMPLETE:
			return "complete"
		State.CLOSED:
			return "closed"
	return "hidden"

func state_name(quest_id: String) -> String:
	return state_name_of(state_of(quest_id))

## What the goal is counting towards (mob id, item id or place id, "" for a
## rescue count).
func goal_target(quest_id: String) -> String:
	return str(def_of(quest_id).get("target", ""))

func goal_kind(quest_id: String) -> int:
	return int(def_of(quest_id).get("kind", Goal.KILL))

func goal_count(quest_id: String) -> int:
	return maxi(1, int(def_of(quest_id).get("count", 1)))

func progress_of(quest_id: String) -> int:
	return clampi(int(_progress.get(quest_id, 0)), 0, goal_count(quest_id))

func is_offered(quest_id: String) -> bool:
	return state_of(quest_id) == State.OFFERED

func is_active(quest_id: String) -> bool:
	return state_of(quest_id) == State.ACTIVE

func is_complete(quest_id: String) -> bool:
	return state_of(quest_id) == State.COMPLETE

func is_closed(quest_id: String) -> bool:
	return state_of(quest_id) == State.CLOSED

## Every quest the quartermaster (or any other giver) has put on the table but
## the player has not taken yet, in chain order.
func offerable(giver: String = "") -> Array[String]:
	return _ids_in([State.OFFERED], giver)

## The objectives the tracker shows: accepted ones first, then the ones waiting
## to be turned in, in chain order.
func tracked() -> Array[String]:
	var out := _ids_in([State.ACTIVE], "")
	out.append_array(_ids_in([State.COMPLETE], ""))
	return out

func active_ids() -> Array[String]:
	return _ids_in([State.ACTIVE], "")

func completed_ids(giver: String = "") -> Array[String]:
	return _ids_in([State.COMPLETE], giver)

## The quest the HUD line should speak for: the first accepted one, else the
## first one waiting to be turned in, else "".
func tracked_id() -> String:
	var tracked_ids := tracked()
	return tracked_ids[0] if not tracked_ids.is_empty() else ""

## The one-line objective ("Free the soldiers caged in the wood   2 / 4"), or ""
## when nothing is on the books.
func objective() -> String:
	var quest_id := tracked_id()
	if quest_id.is_empty():
		return ""
	return "%s   %s" % [str(def_of(quest_id).get("line", "")), _count_line(quest_id)]

## The quest tracker's rows, ready for the HUD: one per tracked quest.
func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for quest_id in tracked():
		var row := def_of(quest_id)
		out.append({
			"id": quest_id,
			"title": str(row.get("title", quest_id)),
			"line": str(row.get("line", "")),
			"detail": _count_line(quest_id),
			"done": is_complete(quest_id),
		})
	return out

## `"12 / 20"` for a counted goal, and a word for the goals that are not a
## number (a place you have or have not stood in).
func _count_line(quest_id: String) -> String:
	var kind := goal_kind(quest_id)
	if kind == Goal.REACH:
		return "FOUND" if is_complete(quest_id) else "NOT FOUND"
	var had := progress_of(quest_id)
	if had <= 0:
		return "0 / %d" % goal_count(quest_id)
	return "%d / %d" % [had, goal_count(quest_id)]


# --- writing ---------------------------------------------------------------

## Put a quest on the table. A quest that is already past HIDDEN is left alone;
## the caller cannot rewind a chain by offering it again.
func offer(quest_id: String) -> bool:
	if not DEFS.has(quest_id) or state_of(quest_id) != State.HIDDEN:
		return false
	_states[quest_id] = State.OFFERED
	_progress[quest_id] = 0
	changed.emit()
	return true

## Take an offered quest. Returns `{ok, message, quest_id, line}`; accepting a
## quest that is not offered is refused, so a double tap on a talk key cannot
## accept the same order twice.
func accept(quest_id: String) -> Dictionary:
	if not DEFS.has(quest_id):
		return {"ok": false, "message": "That is not an order.", "quest_id": quest_id, "line": ""}
	if state_of(quest_id) != State.OFFERED:
		return {"ok": false, "message": "Nothing was offered.", "quest_id": quest_id,
			"line": _line_of(quest_id)}
	_states[quest_id] = State.ACTIVE
	if is_immediately_satisfied(quest_id):
		_finish(quest_id)
	changed.emit()
	return {"ok": true, "message": "Accepted: %s" % str(def_of(quest_id).get("title", quest_id)),
		"quest_id": quest_id, "line": _line_of(quest_id)}

## Turn a finished quest in and hand over the next row in the chain. The chain
## is the only place a follow-up is named, so a quest with no `next` simply
## closes.
## Returns `{ok, message, quest_id, done, next}`.
func turn_in(quest_id: String) -> Dictionary:
	if state_of(quest_id) != State.COMPLETE:
		return {"ok": false, "message": "", "quest_id": quest_id, "done": "", "next": ""}
	_states[quest_id] = State.CLOSED
	var done_line := str(def_of(quest_id).get("done", ""))
	var next_id := str(def_of(quest_id).get("next", ""))
	if not next_id.is_empty() and state_of(next_id) == State.HIDDEN:
		offer(next_id)
	changed.emit()
	return {"ok": true, "message": done_line, "quest_id": quest_id, "done": done_line,
		"next": next_id}

## A rescue happened: one more body out of a cage.
func note_rescue(count: int = 1) -> Array[String]:
	var moved: Array[String] = []
	if count <= 0:
		return moved
	for quest_id in _ids_in([State.ACTIVE], ""):
		if goal_kind(quest_id) != Goal.RESCUE:
			continue
		if advance(quest_id, count):
			moved.append(quest_id)
	return moved

## A kill landed on `mob_id` ("hollow_warden", "briar_wolf", ...). Bodies that
## do not name a mob id are not counted: a tally that answers to every death is
## not a bounty.
func note_kill(mob_id: String) -> Array[String]:
	var moved: Array[String] = []
	var wanted := mob_id.strip_edges()
	if wanted.is_empty():
		return moved
	for quest_id in _ids_in([State.ACTIVE], ""):
		if goal_kind(quest_id) != Goal.KILL:
			continue
		if goal_target(quest_id) != wanted:
			continue
		if advance(quest_id, 1):
			moved.append(quest_id)
	return moved

## An item reached the stash. Credited once per take: the log cannot be farmed
## by opening the stash twice.
func note_collected(item_id: String) -> Array[String]:
	var moved: Array[String] = []
	for quest_id in _ids_in([State.ACTIVE], ""):
		if goal_kind(quest_id) != Goal.COLLECT:
			continue
		if goal_target(quest_id) != item_id:
			continue
		if advance(quest_id, 1):
			moved.append(quest_id)
	return moved

## A reagent was worked into a weapon (the ichor bench). Counted once per item
## id, so laying the same vial to ten blades is one fact.
func note_applied(item_id: String, amount: int = 1) -> Array[String]:
	var moved: Array[String] = []
	for quest_id in _ids_in([State.ACTIVE], ""):
		if goal_kind(quest_id) != Goal.APPLY:
			continue
		var wanted := goal_target(quest_id)
		if not wanted.is_empty() and wanted != item_id:
			continue
		# A quest that names its reagent is credited once by definition; one that
		# accepts any reagent is credited per item id.
		var key := quest_id
		if wanted.is_empty():
			key = "%s|%s" % [quest_id, item_id]
		if _credited.has(key):
			continue
		_credited.append(key)
		if advance(quest_id, amount):
			moved.append(quest_id)
	return moved

## The body stood in a named place ("crypt"). Places have no geometry here; the
## scene that owns the ground decides it has been reached.
func note_reached(place_id: String) -> Array[String]:
	var moved: Array[String] = []
	var wanted := place_id.strip_edges()
	if wanted.is_empty():
		return moved
	for quest_id in _ids_in([State.ACTIVE], ""):
		if goal_kind(quest_id) != Goal.REACH:
			continue
		if goal_target(quest_id) != wanted:
			continue
		if advance(quest_id, 1):
			moved.append(quest_id)
	return moved

## Count `amount` towards one quest. Returns true when the quest moved (and
## emits `quest_completed` the frame the count is met).
func advance(quest_id: String, amount: int = 1) -> bool:
	if state_of(quest_id) != State.ACTIVE:
		return false
	var target := goal_count(quest_id)
	var had := progress_of(quest_id)
	if had >= target:
		return false
	var now := clampi(had + maxi(1, amount), 0, target)
	_progress[quest_id] = now
	if now >= target:
		_finish(quest_id)
	else:
		changed.emit()
	return true

func _finish(quest_id: String) -> void:
	_states[quest_id] = State.COMPLETE
	_progress[quest_id] = goal_count(quest_id)
	changed.emit()
	quest_completed.emit(quest_id)

## A goal met by the very thing that turned the quest on (the player is already
## holding the vial he is being asked to show). Completing it the same frame it
## is accepted is honest; making him walk away and back is not.
func is_immediately_satisfied(quest_id: String) -> bool:
	var kind := goal_kind(quest_id)
	if kind != Goal.COLLECT and kind != Goal.APPLY:
		return false
	return progress_of(quest_id) >= goal_count(quest_id)

## Clear the ledger (a new campaign). The definition table is constant.
func reset() -> void:
	_states.clear()
	_progress.clear()
	_credited.clear()
	changed.emit()


# --- persistence -----------------------------------------------------------

func to_dict() -> Dictionary:
	var states := {}
	for quest_id in _states:
		if DEFS.has(str(quest_id)):
			states[str(quest_id)] = int(_states[quest_id])
	var progress := {}
	for quest_id in _progress:
		if DEFS.has(str(quest_id)):
			progress[str(quest_id)] = int(_progress[quest_id])
	return {"version": SAVE_VERSION, "states": states, "progress": progress,
		"credited": _credited.duplicate()}

func from_dict(data: Variant) -> void:
	reset()
	if not (data is Dictionary):
		return
	var source: Dictionary = data
	# A section written by a newer build is read for the keys this build knows:
	# an unknown quest id is dropped by `_read_states`, never half-applied.
	var states: Variant = source.get("states", {})
	if states is Dictionary:
		for quest_id in states:
			var key := str(quest_id)
			if not DEFS.has(key):
				continue
			var state := clampi(int(states[quest_id]), State.OFFERED, State.CLOSED)
			_states[key] = state
	var progress: Variant = source.get("progress", {})
	if progress is Dictionary:
		for quest_id in progress:
			var key := str(quest_id)
			if not DEFS.has(key):
				continue
			_progress[key] = clampi(int(progress[quest_id]), 0, goal_count(key))
	var credited: Variant = source.get("credited", [])
	if credited is Array:
		for entry in credited:
			_credited.append(str(entry))
	# A quest saved as COMPLETE but with a short count (an older file, or a
	# hand-edited one) is repaired to its goal rather than read as a contradiction.
	for quest_id in _states:
		if int(_states[quest_id]) >= State.COMPLETE:
			_progress[quest_id] = goal_count(str(quest_id))
	changed.emit()

## A save's quest section is untrusted input: the same reader, refusing anything
## that is not a dictionary, so a corrupt file opens with no objectives rather
## than a crash.
static func sanitise(data: Variant) -> Dictionary:
	if not (data is Dictionary):
		return {}
	return data


# --- internals -------------------------------------------------------------

func _ids_in(states: Array, giver: String) -> Array[String]:
	var out: Array[String] = []
	for quest_id in IDS:
		var row: Dictionary = DEFS[quest_id]
		if not giver.is_empty() and str(row.get("giver", "")) != giver:
			continue
		if states.has(state_of(quest_id)):
			out.append(quest_id)
	return out

func _line_of(quest_id: String) -> String:
	return str(def_of(quest_id).get("line", ""))
