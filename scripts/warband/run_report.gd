class_name RunReport
extends RefCounted
## One battle, as the warband remembers it.
##
## A report is a *ledger entry*, never a payment: every number in it has already
## happened through the wallets (`PlayerState.credits`, `Warband.cruor`) and the
## shared stash, so loading a save can replay the record as often as it likes and
## the warband is never paid twice.
##
## The payload is deliberately engine-free - strings, ints, floats and an array of
## small dictionaries - so `JSON.stringify()` round-trips it without a serializer
## and an older save that never held a report still loads: `read_dict()` fills
## in a blank record for anything it cannot read.
##
## A live run is filled in by `Warband` (see its persistence section) and closed
## when the field is left; `docs/warband.md` calls this "run persistence".

const Contracts = preload("res://scripts/warband/warband_contracts.gd")

## What kind of battle the record describes. `expedition` is the deployed line
## fighting cultist waves; `sandbox` is a field that hands out no verdict.
const MODE_EXPEDITION := "expedition"
const MODE_SANDBOX := "sandbox"

## How the battle ended. A wipe is never counted as a clear, and a field the
## player walked off while the cult still stood is neither.
const OUTCOME_CLEARED := "cleared"
const OUTCOME_WIPED := "wiped"
const OUTCOME_ABANDONED := "abandoned"

const OUTCOMES := [OUTCOME_CLEARED, OUTCOME_WIPED, OUTCOME_ABANDONED]
## Body states, spelled the way `WarbandContracts.state_name()` spells them and
## lower-cased so the payload never carries an enum number.
const STATE_ALIVE := "alive"
const STATE_DOWNED := "downed"
const STATE_DEAD := "dead"
const STATES := [STATE_ALIVE, STATE_DOWNED, STATE_DEAD]

## The exact payload keys, in reading order. A save/load cycle must reproduce all
## of them; the regression walks this list field by field.
const FIELDS := [
	"mode", "outcome", "started_at", "ended_at", "seconds",
	"waves", "waves_cleared", "kills", "items", "gold", "cruor", "bodies",
]
## The lifetime counters `Warband` keeps next to the bounded history.
const TOTAL_FIELDS := [
	"runs", "wins", "wipes", "abandoned", "best_wave", "kills", "items", "gold", "cruor",
]

## How many reports the save keeps. The screen shows the newest; the rest is
## history the next phase can browse without the file growing forever.
const HISTORY_LIMIT := 20

var mode := MODE_EXPEDITION
## Empty until the field is left (the verdict needs the whole battle).
var outcome := ""
## Unix seconds, so a loaded save renders its stamp in the player's own timezone.
var started_at := 0
var ended_at := 0
var seconds := 0
## The deepest wave the battle reached (1 = the first wave was fielded) and how
## many of them were actually broken. A wipe on wave one is `waves = 1,
## waves_cleared = 0`: the two numbers answer different questions, and the
## lifetime `best_wave` is the first of them - how far the warband got.
var waves := 0
var waves_cleared := 0
var kills := 0
## Pieces the field yielded (the shared stash's and the bodies' holdings, net).
var items := 0
## What the run put in the purse and the essence wallet.
var gold := 0
var cruor := 0
## `[{"name","health","max_health","state"}]` for every body that took the field.
var bodies: Array[Dictionary] = []

## Begin a record at this moment. `Warband.begin_run()` is the only caller.
func start(now: int = 0) -> void:
	started_at = now if now > 0 else int(Time.get_unix_time_from_system())

# --- payload ---------------------------------------------------------------

func to_dict() -> Dictionary:
	var payload := {
		"mode": mode,
		"outcome": outcome,
		"started_at": started_at,
		"ended_at": ended_at,
		"seconds": seconds,
		"waves": waves,
		"waves_cleared": waves_cleared,
		"kills": kills,
		"items": items,
		"gold": gold,
		"cruor": cruor,
		"bodies": [],
	}
	var body_list: Array = []
	for body in bodies:
		body_list.append({
			"name": str(body.get("name", "")),
			"health": float(body.get("health", 0.0)),
			"max_health": float(body.get("max_health", 0.0)),
			"state": str(body.get("state", STATE_DEAD)),
		})
	payload["bodies"] = body_list
	return payload

## Read a payload into this record. Unknown or malformed fields fall back to
## the blank record, so a hand-edited or older file can never stop the warband
## loading. `Warband` builds one of these per saved report; nothing else has to.
func read_dict(data: Dictionary) -> void:
	mode = _mode(data.get("mode", MODE_EXPEDITION))
	outcome = _outcome(data.get("outcome", ""))
	started_at = maxi(0, int(data.get("started_at", 0)))
	ended_at = maxi(0, int(data.get("ended_at", 0)))
	seconds = maxi(0, int(data.get("seconds", 0)))
	waves = maxi(0, int(data.get("waves", 0)))
	waves_cleared = maxi(0, int(data.get("waves_cleared", 0)))
	kills = maxi(0, int(data.get("kills", 0)))
	items = maxi(0, int(data.get("items", 0)))
	gold = maxi(0, int(data.get("gold", 0)))
	cruor = maxi(0, int(data.get("cruor", 0)))
	bodies = sanitize_bodies(data.get("bodies", []))

## One clean body list from anything a file, a scene or a test handed over.
static func sanitize_bodies(value: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not value is Array:
		return out
	for entry in value as Array:
		if not entry is Dictionary:
			continue
		var body: Dictionary = entry
		var max_health := maxf(0.0, float(body.get("max_health", 0.0)))
		out.append({
			"name": str(body.get("name", "")),
			"health": clampf(float(body.get("health", 0.0)), 0.0, max_health),
			"max_health": max_health,
			"state": str(body.get("state", STATE_DEAD)) if str(body.get("state", "")) in STATES
				else STATE_DEAD,
		})
	return out

# --- vocabulary ------------------------------------------------------------

## The payload key for a `WarbandContracts.HealthState`.
static func state_key(state: int) -> String:
	match state:
		Contracts.HealthState.DOWNED:
			return STATE_DOWNED
		Contracts.HealthState.DEAD:
			return STATE_DEAD
	return STATE_ALIVE

## The screen's spelling of a stored outcome.
static func outcome_label(key: String) -> String:
	match str(key):
		OUTCOME_CLEARED:
			return "Cleared"
		OUTCOME_WIPED:
			return "Wiped"
		OUTCOME_ABANDONED:
			return "Left the field"
	return "Unrecorded"

## `2026-10-27 14:05`, or an honest dash when the stamp is missing.
static func stamp_text(unix_seconds: int) -> String:
	if unix_seconds <= 0:
		return "-"
	var zone: Dictionary = Time.get_time_zone_from_system()
	var stamp := Time.get_datetime_dict_from_unix_time(unix_seconds + int(zone.get("bias", 0)) * 60)
	return "%04d-%02d-%02d %02d:%02d" % [
		int(stamp.get("year", 0)), int(stamp.get("month", 0)), int(stamp.get("day", 0)),
		int(stamp.get("hour", 0)), int(stamp.get("minute", 0))]

# --- lifetime totals -------------------------------------------------------

static func blank_totals() -> Dictionary:
	var totals := {}
	for key in TOTAL_FIELDS:
		totals[key] = 0
	return totals

static func sanitize_totals(data: Variant) -> Dictionary:
	var totals := blank_totals()
	if not data is Dictionary:
		return totals
	for key in TOTAL_FIELDS:
		totals[key] = maxi(0, int((data as Dictionary).get(key, 0)))
	return totals

## Book one finished report into the lifetime tally. `best_wave` only ever grows:
## a short, ugly run never takes the warband's record away.
static func tally(totals: Dictionary, report: Dictionary) -> Dictionary:
	var outcome := str(report.get("outcome", ""))
	totals["runs"] = int(totals.get("runs", 0)) + 1
	if outcome == OUTCOME_CLEARED:
		totals["wins"] = int(totals.get("wins", 0)) + 1
	elif outcome == OUTCOME_WIPED:
		totals["wipes"] = int(totals.get("wipes", 0)) + 1
	elif outcome == OUTCOME_ABANDONED:
		totals["abandoned"] = int(totals.get("abandoned", 0)) + 1
	totals["best_wave"] = maxi(int(totals.get("best_wave", 0)), int(report.get("waves", 0)))
	totals["kills"] = int(totals.get("kills", 0)) + int(report.get("kills", 0))
	totals["items"] = int(totals.get("items", 0)) + int(report.get("items", 0))
	totals["gold"] = int(totals.get("gold", 0)) + int(report.get("gold", 0))
	totals["cruor"] = int(totals.get("cruor", 0)) + int(report.get("cruor", 0))
	return totals

# --- internals -------------------------------------------------------------

static func _mode(value: Variant) -> String:
	var text := str(value)
	if text == MODE_SANDBOX:
		return MODE_SANDBOX
	return MODE_EXPEDITION

static func _outcome(value: Variant) -> String:
	var text := str(value)
	return text if text in OUTCOMES else ""

