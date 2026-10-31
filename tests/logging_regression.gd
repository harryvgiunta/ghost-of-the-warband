extends SceneTree
## The automatic logger and crash forensics.
##
## Covers the JSONL/text session files, the environment block, structured events,
## engine print/warning/error capture with GDScript stacks, immediate flushing,
## the sampled state, heartbeat markers, the idle watchdog, level filtering,
## thread-safe writes, retention, and crash detection: synthetic sessions, a
## live process that must not be reported, a real child that quits cleanly, and
## a real child that kills itself. The final crash report must carry the
## environment, last state, breadcrumbs, errors and the archived log tail, and
## the title menu must surface it.

const Store = preload("res://scripts/log_store.gd")
const Watchdog = preload("res://scripts/log_watchdog.gd")
const CHILD := "res://tests/logging_child.gd"

var log
var checks := 0
var failures := 0
var dead_pid := 2000000000


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("LOGGING_FAIL " + message)
		print("LOGGING_FAIL  ", message)


func _run_records(path: String) -> Array:
	var rows: Array = []
	if not FileAccess.file_exists(path):
		return rows
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.strip_edges().is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		if typeof(parsed) == TYPE_DICTIONARY:
			rows.append(parsed)
	return rows


func _count_invalid_lines(path: String) -> int:
	var invalid := 0
	if not FileAccess.file_exists(path):
		return 0
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.strip_edges().is_empty():
			continue
		if typeof(JSON.parse_string(line)) != TYPE_DICTIONARY:
			invalid += 1
	return invalid


func _find(rows: Array, key: String, value: Variant) -> Dictionary:
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY and row.get(key) == value:
			return row
	return {}


func _find_last(rows: Array, key: String, value: Variant) -> Dictionary:
	var found := {}
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY and row.get(key) == value:
			found = row
	return found


func _has_event(rows: Array, message: String) -> bool:
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY and str(row.get("k", "")) == "event" and str(row.get("msg", "")) == message:
			return true
	return false


func _has_entry(entries: Array, session_id: String) -> bool:
	for entry in entries:
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("session_id", "")) == session_id:
			return true
	return false


func _session_for_pid(pid: int) -> String:
	var suffix := "-%d-logging_child" % pid
	for name in Store.list_files(log.sessions_dir(), ".jsonl"):
		var sid := str(name).trim_suffix(".jsonl")
		if sid.ends_with(suffix):
			return sid
	return ""


func _wait_for_session(pid: int, timeout: float) -> String:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var sid := _session_for_pid(pid)
		if not sid.is_empty():
			return sid
		await create_timer(0.05).timeout
	return _session_for_pid(pid)


func _wait_for_text(path: String, needle: String, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path).contains(needle):
			return true
		await create_timer(0.05).timeout
	return FileAccess.file_exists(path) and FileAccess.get_file_as_string(path).contains(needle)


func _wait_pid(pid: int, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if not OS.is_process_running(pid):
			return true
		await create_timer(0.05).timeout
	return not OS.is_process_running(pid)


func _spawn_child(user_args: Array) -> int:
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", CHILD, "--"])
	for argument in user_args:
		args.append(str(argument))
	return OS.create_process(OS.get_executable_path(), args)


func _emit_warning() -> void:
	push_warning("LOGGING_PROBE_WARNING")


func _emit_error() -> void:
	push_error("LOGGING_PROBE_ERROR")


func _emit_script_error() -> void:
	var value: Variant = null
	value.missing_method()


func _cleanup_probe_files() -> void:
	for sid in ["logging_probe_dead", "logging_probe_live", "logging_probe_clean", "logging_probe_foreign"]:
		for suffix in [".jsonl", ".log", ".meta.json", ".active.json", ".reported.json"]:
			Store.remove(log.sessions_dir().path_join(sid + suffix))
	for name in Store.list_files(log.crashes_dir()):
		if str(name).contains("logging_probe"):
			Store.remove(log.crashes_dir().path_join(str(name)))


func _write_probe_session(sid: String, pid: int, clean: bool) -> void:
	var sessions: String = log.sessions_dir()
	Store.write_text(sessions.path_join(sid + ".jsonl"), "\n".join(PackedStringArray([
		JSON.stringify({"schema": 1, "k": "session_start", "sid": sid, "pid": pid, "src": "probe", "sev": "info"}),
		JSON.stringify({"schema": 1, "k": "message", "sid": sid, "pid": pid, "src": "engine", "sev": "info",
			"msg": "LOGGING_SYNTHETIC_CRASH_LINE"}),
	])) + "\n")
	Store.write_text(sessions.path_join(sid + ".log"), "synthetic session\nLOGGING_SYNTHETIC_CRASH_LINE\n")
	Store.write_json(sessions.path_join(sid + ".meta.json"), {
		"schema": 1,
		"session_id": sid,
		"pid": pid,
		"project": {"name": "synthetic-project"},
		"host": {"computer": "synthetic-host"},
		"environment": {
			"engine": {"version": "synthetic-engine"},
			"os": {"name": "synthetic-os"},
			"rendering": {"adapter": "synthetic-gpu"},
		},
	}, true)
	var beat := Time.get_unix_time_from_system() - 120.0
	Store.write_json(sessions.path_join(sid + ".active.json"), {
		"schema": 1,
		"session_id": sid,
		"pid": pid,
		"clean": clean,
		"beat_iso": Store.utc_iso(beat),
		"beat_unix": beat,
		"scene": "res://probe.tscn",
		"context": {"probe": "yes"},
		"sample": {"scene": "res://probe.tscn", "static_mem": 12345},
		"breadcrumbs": [{"ts": Store.utc_iso(beat), "cat": "test", "msg": "synthetic crumb", "data": {}}],
		"errors": [{"ts": Store.utc_iso(beat), "sev": "error", "code": "SYNTHETIC_ERROR",
			"function": "probe", "file": "probe.gd", "line": 7, "error_type": 0, "frames": []}],
		"counts": {"messages": 3, "warnings": 0, "errors": 1, "events": 1, "samples": 1, "hangs": 0},
	}, false)


func _session_count() -> int:
	return Store.list_files(log.sessions_dir(), ".jsonl").size()


func _retention_probe() -> void:
	var root := "user://logging_prune_test"
	var sessions := root.path_join("sessions")
	Store.ensure_dir(sessions)
	for index in 6:
		Store.write_text(sessions.path_join("session-%d.jsonl" % index), "{}")
	var result := Store.prune(root, 3, 5, 0, "", false)
	check(int(result.get("sessions_removed", 0)) == 3, "Retention removes sessions past the keep count")
	check(Store.list_files(sessions, ".jsonl").size() == 3, "Retention keeps exactly the requested session count")
	for name in Store.list_files(sessions):
		Store.remove(sessions.path_join(str(name)))
	for index in 4:
		Store.write_text(sessions.path_join("session-b%d.jsonl" % index), "x".repeat(2000))
	var bytes_result := Store.prune(root, 10, 5, 5000, "", false)
	check(int(bytes_result.get("sessions_removed", 0)) >= 2, "Retention removes old sessions under the byte budget")
	var total := 0
	for name in Store.list_files(sessions):
		total += Store.file_bytes(sessions.path_join(str(name)))
	check(total <= 5000, "Retention leaves the session folder inside the byte budget")
	for name in Store.list_files(sessions):
		Store.remove(sessions.path_join(str(name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sessions))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root.path_join("crashes")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root))


func run() -> void:
	log = root.get_node_or_null("Log")
	check(log != null, "The Log autoload is installed")
	if log == null:
		finish()
		return
	_cleanup_probe_files()
	check(log.enabled, "File logging is enabled for a script run")
	var info: Dictionary = log.session_info()
	check(bool(info.get("enabled", false)), "The session reports itself enabled")
	check(str(info.get("session_id", "")).begins_with("session-"), "The session has a stable id")
	check(FileAccess.file_exists(str(info.get("jsonl_path", ""))), "The JSONL session file exists")
	check(FileAccess.file_exists(str(info.get("text_path", ""))), "The readable session mirror exists")
	check(FileAccess.file_exists(str(info.get("marker_path", ""))), "The heartbeat marker exists")
	check(FileAccess.file_exists(str(info.get("meta_path", ""))), "The session metadata exists")
	var process_table: Dictionary = log._running_pids()
	if not process_table.is_empty():
		check(process_table.has(OS.get_process_id()), "The OS process table sees this engine")

	# Environment and metadata are captured before gameplay starts.
	var meta: Variant = Store.read_json(str(info.meta_path))
	check(typeof(meta) == TYPE_DICTIONARY, "Session metadata parses")
	if typeof(meta) == TYPE_DICTIONARY:
		var environment: Dictionary = meta.get("environment", {})
		if environment.has("engine"):
			check(str(environment.engine.get("version", "")).contains("4.7"), "The engine version is recorded")
			check(not str(environment.engine.get("hash", "")).is_empty(), "The engine build hash is recorded")
			check(environment.has("os") and not str(environment.os.get("name", "")).is_empty(), "The OS is recorded")
			check(environment.has("rendering") and environment.has("display"), "Rendering and display blocks are recorded")
			check(environment.has("audio") and environment.has("input"), "Audio and input blocks are recorded")
			check(Array(environment.process.get("args", [])).size() > 0, "The command line is recorded")
			check(not str(environment.process.get("executable", "")).is_empty(), "The executable path is recorded")
			check(int(environment.process.get("static_memory", 0)) > 0, "Static memory usage is recorded")
		else:
			check(false, "The environment block exists")
		check(str(meta.get("project", {}).get("root", "")) == ProjectSettings.globalize_path("res://"), "The project root is recorded")

	# The JSONL stream is complete, parseable and starts with the session record.
	var records := _run_records(str(info.jsonl_path))
	check(_count_invalid_lines(str(info.jsonl_path)) == 0, "Every JSONL line is valid JSON")
	check(not records.is_empty() and str(records[0].get("k", "")) == "session_start", "The stream starts with session_start")
	check(int(records[0].get("pid", 0)) == OS.get_process_id(), "The session record names this process")

	# Structured event, context and sanitisation.
	log.context("test_phase", "logging_regression")
	log.event("test", "LOGGING_PROBE_EVENT", {"vector": Vector3(1, 2, 3), "count": 2})
	await process_frame
	records = _run_records(str(info.jsonl_path))
	check(_has_event(records, "LOGGING_PROBE_EVENT"), "A structured event reaches the JSONL stream")
	var event_record := _find(records, "msg", "LOGGING_PROBE_EVENT")
	check(event_record.get("data", {}).get("vector") == [1.0, 2.0, 3.0], "Vector payloads are sanitized for JSON")
	check(int(event_record.get("data", {}).get("count", 0)) == 2, "Scalar payloads survive")

	# Plain prints are captured exactly once.
	print("LOGGING_PROBE_PRINT")
	await process_frame
	records = _run_records(str(info.jsonl_path))
	var print_count := 0
	for record in records:
		if str(record.get("msg", "")) == "LOGGING_PROBE_PRINT":
			print_count += 1
	check(print_count == 1, "A plain print is captured once, not echoed back into the logger")
	var text_mirror := FileAccess.get_file_as_string(str(info.text_path))
	check(text_mirror.count("LOGGING_PROBE_PRINT") == 1, "The readable mirror contains the print once")

	# Warnings, errors and script errors carry the GDScript stack.
	_emit_warning()
	_emit_error()
	_emit_script_error()
	var immediate := FileAccess.get_file_as_string(str(info.jsonl_path))
	check(immediate.contains("LOGGING_PROBE_ERROR"), "An error line is flushed before the next frame")
	push_error("LOGGING_PROBE_IMMEDIATE")
	check(FileAccess.get_file_as_string(str(info.jsonl_path)).contains("LOGGING_PROBE_IMMEDIATE"),
		"An error is on disk immediately after push_error")
	await process_frame
	records = _run_records(str(info.jsonl_path))
	var warning := _find(records, "msg", "LOGGING_PROBE_WARNING")
	check(warning.get("sev", "") == "warning", "push_warning is captured as a warning")
	check(str(warning.get("error_name", "")) == "ERROR_TYPE_WARNING", "The warning type is named")
	var error_record := _find(records, "msg", "LOGGING_PROBE_ERROR")
	check(error_record.get("sev", "") == "error", "push_error is captured as an error")
	check(str(error_record.get("backtrace", "")).contains("GDScript backtrace"), "The error carries a GDScript backtrace")
	var frames: Array = error_record.get("frames", [])
	check(not frames.is_empty(), "The error carries structured frames")
	if not frames.is_empty():
		check(str(frames[0].get("file", "")).contains("logging_regression.gd"), "The frame names the calling test file")
	var script_error := _find(records, "msg", "Invalid call. Nonexistent function 'missing_method' in base 'Nil'.")
	check(script_error.get("sev", "") == "script_error", "A runtime script error is captured")
	check(int(script_error.get("error_type", -1)) == 2, "The runtime error type is ERROR_TYPE_SCRIPT")
	check(Array(script_error.get("frames", [])).size() >= 2, "The runtime error stack reaches its caller")
	check(str(script_error.get("backtrace", "")).contains("_emit_script_error"), "The runtime backtrace names the failing function")

	# The heartbeat marker names the sampled state and the recent errors.
	log.force_sample()
	var marker: Variant = Store.read_json(str(info.marker_path))
	check(typeof(marker) == TYPE_DICTIONARY, "The heartbeat marker parses")
	if typeof(marker) == TYPE_DICTIONARY:
		check(int(marker.get("pid", 0)) == OS.get_process_id(), "The marker belongs to this process")
		check(marker.get("clean") == false, "A running session is not marked clean")
		check(str(marker.get("session_id", "")) == str(info.session_id), "The marker names this session")
		var sample: Dictionary = marker.get("sample", {})
		check(not sample.is_empty(), "force_sample updates the marker immediately")
		check(int(sample.get("static_mem", 0)) > 0, "The sample carries static memory")
		check(int(sample.get("nodes", 0)) > 0, "The sample carries the tree node count")
		check(sample.has("player_state"), "The sample carries player state")
		var player_sample: Dictionary = sample.get("player_state", {})
		check(player_sample.has("credits"), "The sample reads PlayerState")
		check(marker.get("context", {}).get("test_phase") == "logging_regression", "The marker carries sticky context")
		var crumb_count := 0
		for crumb in marker.get("breadcrumbs", []):
			if str(crumb.get("msg", "")) == "LOGGING_PROBE_EVENT":
				crumb_count += 1
		check(crumb_count == 1, "The marker carries breadcrumbs")
		var marker_errors: Array = marker.get("errors", [])
		check(not marker_errors.is_empty(), "The marker carries recent errors")
		check(Time.get_unix_time_from_system() - float(marker.get("beat_unix", 0.0)) < 5.0, "The marker heartbeat is fresh")

	# Level filtering applies to game events; engine errors are always kept.
	log.level = 3
	log.event("test", "LOGGING_FILTERED", {}, 1)
	log.level = 2
	log.event("test", "LOGGING_VISIBLE", {}, 2)
	log.level = 4
	push_error("LOGGING_LEVEL_ERROR")
	log.level = 2
	await process_frame
	records = _run_records(str(info.jsonl_path))
	check(not _has_event(records, "LOGGING_FILTERED"), "An event below the active level is not written")
	check(_has_event(records, "LOGGING_VISIBLE"), "An event at the active level is written")
	check(not _find(records, "msg", "LOGGING_LEVEL_ERROR").is_empty(), "Engine errors are written even at the error level")

	# A worker thread can write without corrupting the stream.
	var thread := Thread.new()
	thread.start(func() -> void:
		for index in 40:
			log.event("thread", "LOGGING_THREAD_%d" % index))
	thread.wait_to_finish()
	await process_frame
	records = _run_records(str(info.jsonl_path))
	var threaded := 0
	for record in records:
		if str(record.get("cat", "")) == "thread" and str(record.get("msg", "")).begins_with("LOGGING_THREAD_"):
			threaded += 1
	check(threaded == 40, "Threaded events all reach the stream")

	# The watchdog reports a genuinely stalled main loop and its recovery.
	check(Watchdog.judge(6000, false, 6000) == "hang", "The watchdog crosses the hang threshold once")
	check(Watchdog.judge(4000, true, 6000) == "", "A reported stall stays reported while it lasts")
	check(Watchdog.judge(100, true, 6000) == "resume", "A recovered heartbeat reports a resume")
	check(log._watchdog != null, "The idle watchdog is running")
	if log._watchdog != null:
		log.hang_threshold_ms = 800
		log._watchdog.threshold_ms = 800
		OS.delay_msec(1600)
		await create_timer(1.0).timeout
		records = _run_records(str(info.jsonl_path))
		var hang := _find_last(records, "k", "hang")
		check(not hang.is_empty(), "A stalled main loop writes a hang record")
		check(int(hang.get("gap_ms", 0)) >= 800, "The hang record measures the stalled gap")
		var hang_sample: Dictionary = hang.get("sample", {})
		check(not hang_sample.is_empty(), "The hang record carries the last sample")
		var resume := _find_last(records, "k", "hang_resume")
		check(not resume.is_empty(), "The resumed main loop writes a resume record")
		log.hang_threshold_ms = 6000
		log._watchdog.threshold_ms = 6000

	# Synthetic crash sessions: dead marker, live marker, clean marker.
	check(not OS.is_process_running(dead_pid), "The synthetic dead pid is really dead")
	_write_probe_session("logging_probe_dead", dead_pid, false)
	_write_probe_session("logging_probe_live", OS.get_process_id(), false)
	_write_probe_session("logging_probe_clean", dead_pid + 1, true)
	# A pid that belongs to another live process must be skipped by the OS
	# process table, because `OS.is_process_running` cannot see it.
	var foreign_pid := 0
	for candidate in process_table:
		if int(candidate) > 0 and int(candidate) != OS.get_process_id() and not OS.is_process_running(int(candidate)):
			foreign_pid = int(candidate)
			break
	if foreign_pid > 0:
		_write_probe_session("logging_probe_foreign", foreign_pid, false)
	var created: Array = log.scan_for_crashes()
	check(_has_entry(created, "logging_probe_dead"), "A dead unclean session becomes a crash report")
	check(not _has_entry(created, "logging_probe_live"), "A live process is never reported as crashed")
	check(not _has_entry(created, "logging_probe_clean"), "A clean marker is never reported as crashed")
	if foreign_pid > 0:
		check(not _has_entry(created, "logging_probe_foreign"),
			"An unrelated live pid is not reported by the scan")
	var dead_entry := {}
	for entry in created:
		if str(entry.get("session_id", "")) == "logging_probe_dead":
			dead_entry = entry
	check(not dead_entry.is_empty(), "The synthetic crash entry is returned")
	if not dead_entry.is_empty():
		var report: Variant = Store.read_json(str(dead_entry.get("json_path", "")))
		check(typeof(report) == TYPE_DICTIONARY, "The crash report JSON parses")
		if typeof(report) == TYPE_DICTIONARY:
			check(str(report.get("reason", "")) == "process_missing", "The report names the missing process")
			var evidence: Dictionary = report.get("evidence", {})
			check(bool(evidence.get("marker_present", false)), "The report records the marker")
			check(int(evidence.get("pid", 0)) == dead_pid, "The report records the crashed pid")
			check(str(evidence.get("last_beat_iso", "")) != "", "The report records the last heartbeat")
			check(str(report.get("environment", {}).get("engine", {}).get("version", "")) == "synthetic-engine",
				"The report carries the crashed session's environment")
			check(str(report.get("last_sample", {}).get("scene", "")) == "res://probe.tscn",
				"The report carries the last state sample")
			check(str(report.get("context", {}).get("probe", "")) == "yes", "The report carries sticky context")
			check(int(report.get("counters", {}).get("errors", 0)) == 1, "The report carries the marker counters")
			var tail: Array = report.get("log", {}).get("tail", [])
			var tail_has_line := false
			for line in tail:
				if str(line).contains("LOGGING_SYNTHETIC_CRASH_LINE"):
					tail_has_line = true
			check(tail_has_line, "The report carries the session log tail")
			var archived := str(report.get("log", {}).get("archived_jsonl", ""))
			check(not archived.is_empty() and FileAccess.file_exists(archived), "The crashed session log is archived")
			var text_path := str(dead_entry.get("text_path", ""))
			check(FileAccess.file_exists(text_path), "The human-readable report exists")
			if FileAccess.file_exists(text_path):
				var text := FileAccess.get_file_as_string(text_path)
				check(text.contains("IRONWOOD CRASH REPORT"), "The text report has its header")
				check(text.contains("RECENT ENGINE ERRORS"), "The text report includes the error section")
		check(FileAccess.file_exists(log.sessions_dir().path_join("logging_probe_dead.reported.json")),
			"A reported session gets a companion marker")
		check(not _has_entry(log.scan_for_crashes(), "logging_probe_dead"),
			"A session is reported only once")

	# A real clean child writes its clean end record and is not reported.
	var clean_pid := _spawn_child(["--mode=clean"])
	check(clean_pid > 0, "The clean child starts")
	var clean_exited: bool = await _wait_pid(clean_pid, 20.0)
	check(clean_exited, "The clean child exits")
	var clean_sid := _session_for_pid(clean_pid)
	check(not clean_sid.is_empty(), "The clean child's session is found")
	if not clean_sid.is_empty():
		var clean_marker: Variant = Store.read_json(log.sessions_dir().path_join(clean_sid + ".active.json"))
		check(typeof(clean_marker) == TYPE_DICTIONARY and bool(clean_marker.get("clean", false)),
			"The clean child writes a clean marker")
		if typeof(clean_marker) == TYPE_DICTIONARY:
			check(str(clean_marker.get("end_reason", "")) == "clean_exit", "The clean marker names the exit")
		var clean_records := _run_records(log.sessions_dir().path_join(clean_sid + ".jsonl"))
		check(not clean_records.is_empty(), "The clean child wrote a session")
		if not clean_records.is_empty():
			var last_record: Dictionary = clean_records[clean_records.size() - 1]
			check(str(last_record.get("k", "")) == "session_end", "The clean child ends with session_end")
			check(bool(last_record.get("clean", false)), "The session_end record is clean")
		check(not _has_entry(log.scan_for_crashes(), clean_sid), "A clean child is not reported as a crash")

	# A real child that dies mid-run is not reported while it lives, then is.
	var crash_pid := _spawn_child(["--mode=crash"])
	check(crash_pid > 0, "The crash child starts")
	var crash_sid: String = await _wait_for_session(crash_pid, 20.0)
	check(not crash_sid.is_empty(), "The crash child's session is found")
	var crash_ready := false
	if not crash_sid.is_empty():
		crash_ready = await _wait_for_text(log.sessions_dir().path_join(crash_sid + ".jsonl"),
			"LOGGING_CRASH_CHILD_READY", 20.0)
	check(crash_ready, "The crash child reached its heartbeat checkpoint")
	check(OS.is_process_running(crash_pid), "The crash child is alive before the scan")
	var live_table: Dictionary = log._running_pids()
	if not live_table.is_empty():
		check(live_table.has(crash_pid), "The OS process table sees the live child")
	var live_scan: Array = log.scan_for_crashes()
	check(not _has_entry(live_scan, crash_sid), "A running crash child is not reported")
	var crash_exited: bool = await _wait_pid(crash_pid, 20.0)
	check(crash_exited, "The crash child dies")
	var dead_scan: Array = log.scan_for_crashes()
	check(_has_entry(dead_scan, crash_sid), "The dead crash child is reported on the next scan")
	if not crash_sid.is_empty():
		var crash_entry := {}
		for entry in dead_scan:
			if str(entry.get("session_id", "")) == crash_sid:
				crash_entry = entry
		if not crash_entry.is_empty():
			var crash_report: Variant = Store.read_json(str(crash_entry.get("json_path", "")))
			check(typeof(crash_report) == TYPE_DICTIONARY, "The child crash report parses")
			if typeof(crash_report) == TYPE_DICTIONARY:
				check(str(crash_report.get("reason", "")) == "process_missing", "The child crash reason is the missing process")
				var crash_sample: Dictionary = crash_report.get("last_sample", {})
				check(not crash_sample.is_empty(), "The child crash report carries the forced heartbeat sample")
				var crash_tail: Array = crash_report.get("log", {}).get("tail", [])
				var crash_tail_ok := false
				for line in crash_tail:
					if str(line).contains("LOGGING_CRASH_CHILD_READY"):
						crash_tail_ok = true
				check(crash_tail_ok, "The child crash report carries its log tail")

	# The title menu surfaces the reports written during this boot.
	var title = load("res://title.tscn").instantiate()
	root.add_child(title)
	await process_frame
	check(title.crash_notice != null and title.crash_notice.visible, "The title menu shows the crash notice")
	check(not title._crash_report.is_empty(), "The title menu names the latest report")
	title.queue_free()
	await process_frame

	# --no-log writes no session at all, not even for a child process.
	var sessions_before := _session_count()
	var off_args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", CHILD, "--", "--mode=off", "--no-log"])
	var output: Array = []
	var off_code := OS.execute(OS.get_executable_path(), off_args, output, true)
	check(off_code == 0, "The no-log child exits cleanly")
	check(_session_count() == sessions_before, "The no-log child creates no session file")
	var off_logged := false
	for name in Store.list_files(log.sessions_dir(), ".jsonl"):
		if FileAccess.get_file_as_string(log.sessions_dir().path_join(str(name))).contains("LOGGING_OFF_CHILD"):
			off_logged = true
	check(not off_logged, "The no-log child's output is not captured anywhere")

	_retention_probe()
	_cleanup_probe_files()
	finish()


func finish() -> void:
	print("LOGGING_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
