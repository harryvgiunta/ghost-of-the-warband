extends Thread
## Watches the main thread's heartbeat from a worker thread.
##
## A native crash leaves no chance to write anything, but a frozen main loop is
## observable while the process is still alive. The thread reports a `hang` once
## the heartbeat is older than the threshold and a `hang_resume` when frames move
## again, so a crash report's log tail still says how long the game was stuck.
## The sink only writes through `Log`'s mutex-protected file handles.

const POLL_MSEC := 200

var beat := Callable()
var sink := Callable()
var threshold_ms := 6000
var running := true
var reported := false
var last_gap_ms := 0


func _run() -> void:
	reported = false
	last_gap_ms = 0
	while running:
		OS.delay_msec(POLL_MSEC)
		if not running:
			break
		if not beat.is_valid() or not sink.is_valid():
			continue
		var now := Time.get_ticks_msec()
		var last_beat := int(beat.call())
		var gap := maxi(0, now - last_beat)
		last_gap_ms = gap
		var verdict := judge(gap, reported, threshold_ms)
		if verdict == "hang":
			reported = true
			sink.call("hang", gap, last_beat, now)
		elif verdict == "resume":
			reported = false
			sink.call("hang_resume", gap, last_beat, now)


## Pure decision used by the thread and by `logging_regression`.
static func judge(gap_ms: int, already_reported: bool, threshold: int) -> String:
	var limit := maxi(1, threshold)
	if not already_reported and gap_ms >= limit:
		return "hang"
	if already_reported and gap_ms < maxi(1, int(limit * 0.5)):
		return "resume"
	return ""
