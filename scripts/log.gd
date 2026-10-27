extends Node
## Automatic session logging and crash forensics.
##
## Every run mirrors the engine's own output and the game's structured events
## into `user://logs/sessions/<session>.jsonl` (plus a readable `.log`), while a
## heartbeat marker is rewritten every few seconds. A run that never writes its
## clean marker is reconstructed on the next launch into
## `user://logs/crashes/crash-<time>-<session>.json` and `.txt`: environment,
## the last state sample, breadcrumbs, the recent engine errors with their
## GDScript stacks and the tail of the session log, with the session log archived
## next to the report.
##
## Crash detection is heartbeat based because a native crash cannot run a
## GDScript handler. `OS.add_logger` still gives us every engine message and
## error synchronously, and those lines are flushed to disk before the process
## can die, so the report usually ends on the exact failing line.
##
## Command-line / environment switches:
##   --no-log, IRONWOOD_LOG=0          disable this run entirely
##   --log-dir=<path>                  write somewhere other than user://logs
##   --log-level=<trace|debug|info|warn|error|off>
##   --log-verbose                     same as --log-level=trace
##   --log-keep=<sessions>             session retention (default 40)
##   --no-hang-watch                   do not start the stale-frame watchdog
##   --log-hang-ms=<milliseconds>      watchdog threshold (default 6000)

const Store = preload("res://scripts/log_store.gd")
const Capture = preload("res://scripts/log_capture.gd")
const Watchdog = preload("res://scripts/log_watchdog.gd")

const LEVEL_TRACE := 0
const LEVEL_DEBUG := 1
const LEVEL_INFO := 2
const LEVEL_WARN := 3
const LEVEL_ERROR := 4

const DEFAULT_ROOT := "user://logs"
const SCRIPT_ROOT := "user://logs/test"
const SAMPLE_MS := 2000
const MARKER_MS := 5000
const SCAN_MS := 60000
const SESSION_BYTES_LIMIT := 32 * 1024 * 1024
const BREADCRUMB_LIMIT := 256
const MARKER_BREADCRUMBS := 32
const RECENT_ERROR_LIMIT := 24
const MARKER_ERRORS := 8
const LOG_TAIL_LINES := 400
const KEEP_SESSIONS := 40
const KEEP_CRASHES := 60
const TOTAL_BYTES_LIMIT := 256 * 1024 * 1024
const ERROR_TEXT_LIMIT := 24000
const MESSAGE_LIMIT := 16384
const DATA_STRING_LIMIT := 4096
const CLEAN_LOG_AGE_SECONDS := 30.0
const UNREADABLE_MARKER_AGE_SECONDS := 15.0
## Only used when the OS process table cannot be read: a fresh heartbeat means
## another instance is probably still alive even though its pid is not ours.
const LIVE_GRACE_SECONDS := 15.0

var enabled := true
var log_root := DEFAULT_ROOT
var level := LEVEL_INFO
var hang_threshold_ms := 6000
var keep_sessions := KEEP_SESSIONS
var keep_crashes := KEEP_CRASHES

var session_id := ""
var _source := ""
var _sessions_dir := ""
var _crashes_dir := ""
var _jsonl_path := ""
var _text_path := ""
var _marker_path := ""
var _meta_path := ""

var _jsonl: FileAccess = null
var _text: FileAccess = null
var _capture = null
var _watchdog = null
var _watchdog_enabled := true
var _started := false
var _stopping := false
var _started_at := 0.0

var _write_mutex := Mutex.new()
var _state_mutex := Mutex.new()
var _marker_mutex := Mutex.new()
var _writing_thread := -1

var _environment: Dictionary = {}
var _context: Dictionary = {}
var _breadcrumbs: Array = []
var _recent_errors: Array = []
var _last_sample: Dictionary = {}
var _counts := {
	"messages": 0, "warnings": 0, "errors": 0, "events": 0,
	"samples": 0, "hangs": 0,
}
var _bytes := 0
var _records := 0
var _truncated := false

var _ended_unix := 0.0
var _last_marker_msec := 0
var _last_sample_msec := 0
var _last_scan_msec := 0
var _beat_msec := 0

var _pending_reports: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_configure()
	if not enabled:
		set_process(false)
		return
	_environment = _build_environment()
	_start_session()
	if not enabled:
		return
	_register_capture()
	_started = true
	_write_record("session_start", {
		"src": "logger",
		"sev": "info",
		"session_id": session_id,
		"source": _source,
		"started_iso": Store.utc_iso(_started_at),
		"level": level,
		"environment": _environment,
		"args": OS.get_cmdline_args(),
		"user_args": OS.get_cmdline_user_args(),
	}, "session start source=%s pid=%d root=%s" % [_source, OS.get_process_id(), log_root], true)
	_write_marker(true)
	print("IRONWOOD_LOG_DIR ", ProjectSettings.globalize_path(log_root))
	scan_for_crashes()
	# Reports are written before retention runs, so a crash on disk is never
	# pruned before it can be archived. Recent files are protected anyway.
	Store.prune(log_root, keep_sessions, keep_crashes, TOTAL_BYTES_LIMIT, session_id)
	_start_watchdog()
	_beat_msec = Time.get_ticks_msec()
	_last_sample_msec = 0
	_last_scan_msec = _beat_msec
	_started = true
	set_process(true)


func _process(_delta: float) -> void:
	if not enabled or not _started:
		return
	_beat_msec = Time.get_ticks_msec()
	if _beat_msec - _last_sample_msec >= SAMPLE_MS:
		_last_sample_msec = _beat_msec
		force_sample()
	if _beat_msec - _last_scan_msec >= SCAN_MS:
		_last_scan_msec = _beat_msec
		scan_for_crashes()


func _exit_tree() -> void:
	if not enabled or _stopping:
		return
	_stopping = true
	_stop_watchdog()
	_ended_unix = Time.get_unix_time_from_system()
	_write_record("session_end", {
		"src": "logger",
		"sev": "info",
		"clean": true,
		"ended_iso": Store.utc_iso(_ended_unix),
		"uptime_s": snappedf(_ended_unix - _started_at, 0.001),
		"counts": _copy_counts(),
	}, "clean exit uptime=%.3fs" % maxf(0.0, _ended_unix - _started_at), true)
	_write_marker(true, true)
	_write_mutex.lock()
	if _jsonl != null:
		_jsonl.flush()
		_jsonl.close()
		_jsonl = null
	if _text != null:
		_text.flush()
		_text.close()
		_text = null
	_write_mutex.unlock()
	Store.prune(log_root, keep_sessions, keep_crashes, TOTAL_BYTES_LIMIT, session_id)


func _notification(what: int) -> void:
	if not enabled or not _started:
		return
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			event("app", "window_close_requested")
			flush()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			event("app", "focus_in", {}, LEVEL_DEBUG)
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			event("app", "focus_out", {}, LEVEL_DEBUG)
		NOTIFICATION_APPLICATION_PAUSED:
			event("app", "paused")
			_write_marker(true)
		NOTIFICATION_APPLICATION_RESUMED:
			event("app", "resumed")
		NOTIFICATION_OS_MEMORY_WARNING:
			event("app", "memory_warning", {"static_mem": OS.get_static_memory_usage()}, LEVEL_WARN)
			_write_marker(true)
		NOTIFICATION_CRASH:
			flush()
			_write_record("crash_notification", {
				"src": "engine",
				"sev": "error",
				"note": "NOTIFICATION_CRASH delivered before shutdown",
			}, "NOTIFICATION_CRASH delivered before shutdown", true)
			_write_marker(true)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## A structured game breadcrumb. `data` must be plain data; vectors and objects
## are reduced to JSON-safe values. Breadcrumbs always land in the heartbeat
## marker, and the record is written when `severity` passes the active level.
func event(category: String, message: String, data: Dictionary = {}, severity: int = LEVEL_INFO) -> void:
	if not enabled or not _started:
		return
	var clean: Dictionary = _clean_variant(data)
	var stamp := Store.utc_iso()
	var crumb := {
		"ts": stamp,
		"cat": category.left(48),
		"msg": message.left(512),
		"data": clean,
	}
	_state_mutex.lock()
	_breadcrumbs.append(crumb)
	while _breadcrumbs.size() > BREADCRUMB_LIMIT:
		_breadcrumbs.pop_front()
	_state_mutex.unlock()
	if severity < level:
		return
	var text := "%s: %s" % [category, message]
	if not clean.is_empty():
		text += " " + JSON.stringify(clean, "", false, true)
	_write_record("event", {
		"src": "game",
		"sev": _level_name(severity),
		"cat": category.left(48),
		"msg": message.left(MESSAGE_LIMIT),
		"data": clean,
	}, text)


## Sticky session context: scene, network role, run depth, party size, anything
## the next crash report should know without a gameplay log line.
func context(key: String, value: Variant) -> void:
	_state_mutex.lock()
	_context[key] = _clean_variant(value)
	_state_mutex.unlock()


## Writes the periodic state sample and the heartbeat marker now. The sampler
## calls it every two seconds; tests and explicit checkpoints can call it too.
func force_sample() -> void:
	if not enabled or not _started:
		return
	var sample := _collect_sample()
	_state_mutex.lock()
	_last_sample = sample
	_state_mutex.unlock()
	_write_record("sample", {
		"src": "game",
		"sev": "info",
		"sample": sample,
	}, _sample_text(sample))
	# Every sample is a heartbeat: the marker must name the state we just wrote,
	# so a crash a fraction of a second later still reports it.
	_write_marker(true)


func flush() -> void:
	if not enabled:
		return
	_write_mutex.lock()
	if _jsonl != null:
		_jsonl.flush()
	if _text != null:
		_text.flush()
	_write_mutex.unlock()


func session_info() -> Dictionary:
	return {
		"enabled": enabled,
		"session_id": session_id,
		"source": _source,
		"log_root": log_root,
		"jsonl_path": _jsonl_path,
		"text_path": _text_path,
		"marker_path": _marker_path,
		"meta_path": _meta_path,
		"level": level,
		"bytes": _bytes,
		"records": _records,
		"truncated": _truncated,
		"counts": _copy_counts(),
		"environment": _environment,
	}


func sessions_dir() -> String:
	return _sessions_dir


func crashes_dir() -> String:
	return _crashes_dir


func pending_crash_reports() -> Array:
	return _pending_reports.duplicate(true)


func latest_crash_report() -> Dictionary:
	return _pending_reports[0].duplicate(true) if not _pending_reports.is_empty() else {}


func open_crash_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path(_crashes_dir))


func open_report(index: int = 0) -> void:
	if index < 0 or index >= _pending_reports.size():
		open_crash_folder()
		return
	var path := str(_pending_reports[index].get("text_path", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		open_crash_folder()
		return
	OS.shell_open(ProjectSettings.globalize_path(path))


# ---------------------------------------------------------------------------
# Configuration and session files
# ---------------------------------------------------------------------------

func _configure() -> void:
	var script := _script_path()
	log_root = SCRIPT_ROOT if not script.is_empty() else DEFAULT_ROOT
	var args := PackedStringArray()
	args.append_array(OS.get_cmdline_args())
	args.append_array(OS.get_cmdline_user_args())
	var index := 0
	while index < args.size():
		var argument := str(args[index])
		var value := ""
		var has_value := false
		if argument.contains("="):
			value = argument.split("=", true, 1)[1]
			has_value = true
		if argument == "--no-log" or argument.begins_with("--no-log="):
			enabled = false
		elif argument == "--log-verbose":
			level = LEVEL_TRACE
		elif argument.begins_with("--log-dir"):
			var path := value if has_value else _next_arg(args, index)
			if not path.is_empty():
				log_root = path.trim_suffix("/").trim_suffix("\\")
				if not has_value:
					index += 1
		elif argument.begins_with("--log-level"):
			var name := value if has_value else _next_arg(args, index)
			if not name.is_empty():
				level = _level_from_name(name)
				if not has_value:
					index += 1
		elif argument.begins_with("--log-keep"):
			var keep := value if has_value else _next_arg(args, index)
			if not keep.is_empty():
				keep_sessions = maxi(1, int(keep))
				if not has_value:
					index += 1
		elif argument == "--no-hang-watch":
			_watchdog_enabled = false
		elif argument.begins_with("--log-hang-ms"):
			var threshold := value if has_value else _next_arg(args, index)
			if not threshold.is_empty():
				hang_threshold_ms = maxi(250, int(threshold))
				if not has_value:
					index += 1
		index += 1

	# Environment switches are the last word, so a launcher can force logging on
	# or off without editing the shortcut.
	var env_off := OS.get_environment("IRONWOOD_LOG").strip_edges().to_lower()
	if env_off == "0" or env_off == "off" or env_off == "false":
		enabled = false
	var env_level := OS.get_environment("IRONWOOD_LOG_LEVEL").strip_edges()
	if not env_level.is_empty():
		level = _level_from_name(env_level)
	var env_dir := OS.get_environment("IRONWOOD_LOG_DIR").strip_edges()
	if not env_dir.is_empty():
		log_root = env_dir
	var env_keep := OS.get_environment("IRONWOOD_LOG_KEEP").strip_edges()
	if not env_keep.is_empty():
		keep_sessions = maxi(1, int(env_keep))
	var env_hang := OS.get_environment("IRONWOOD_LOG_HANG_MS").strip_edges()
	if not env_hang.is_empty():
		hang_threshold_ms = maxi(250, int(env_hang))
	if level >= LEVEL_ERROR + 1:
		enabled = false


func _script_path() -> String:
	for args in [OS.get_cmdline_args(), OS.get_cmdline_user_args()]:
		var list: PackedStringArray = args
		for index in list.size():
			if str(list[index]) == "--script" and index + 1 < list.size():
				return str(list[index + 1])
	return ""


func _next_arg(args: PackedStringArray, index: int) -> String:
	return str(args[index + 1]) if index + 1 < args.size() else ""


func _level_from_name(name: String) -> int:
	match name.strip_edges().to_lower():
		"trace": return LEVEL_TRACE
		"debug": return LEVEL_DEBUG
		"warn", "warning": return LEVEL_WARN
		"error": return LEVEL_ERROR
		"off", "none", "silent": return LEVEL_ERROR + 1
		_: return LEVEL_INFO


func _level_name(value: int) -> String:
	if value <= LEVEL_TRACE:
		return "trace"
	if value <= LEVEL_DEBUG:
		return "debug"
	if value <= LEVEL_INFO:
		return "info"
	if value <= LEVEL_WARN:
		return "warn"
	return "error"


func _session_source() -> String:
	var script := _script_path()
	if not script.is_empty():
		return script
	return str(ProjectSettings.get_setting("application/run/main_scene", "project"))


func _start_session() -> void:
	_started_at = Time.get_unix_time_from_system()
	_source = _session_source()
	_sessions_dir = log_root.path_join("sessions")
	_crashes_dir = log_root.path_join("crashes")
	if not Store.ensure_dir(_sessions_dir) or not Store.ensure_dir(_crashes_dir):
		enabled = false
		push_warning("Automatic logging disabled: could not create %s" % log_root)
		return
	session_id = "session-%s-%d-%s" % [
		Store.utc_stamp(_started_at), OS.get_process_id(), Store.slug(_source, 28)]
	_jsonl_path = _sessions_dir.path_join(session_id + ".jsonl")
	_text_path = _sessions_dir.path_join(session_id + ".log")
	_marker_path = _sessions_dir.path_join(session_id + ".active.json")
	_meta_path = _sessions_dir.path_join(session_id + ".meta.json")
	_jsonl = FileAccess.open(_jsonl_path, FileAccess.WRITE)
	_text = FileAccess.open(_text_path, FileAccess.WRITE)
	if _jsonl == null or _text == null:
		enabled = false
		push_warning("Automatic logging disabled: could not open %s" % _sessions_dir)
		return
	var meta := {
		"schema": Store.SCHEMA_VERSION,
		"session_id": session_id,
		"pid": OS.get_process_id(),
		"started_iso": Store.utc_iso(_started_at),
		"started_unix": _started_at,
		"source": _source,
		"level": level,
		"log_root": log_root,
		"project": {
			"name": str(ProjectSettings.get_setting("application/config/name", "")),
			"version": str(ProjectSettings.get_setting("application/config/version", "")),
			"main_scene": str(ProjectSettings.get_setting("application/run/main_scene", "")),
			"root": ProjectSettings.globalize_path("res://"),
		},
		"host": {
			"computer": OS.get_environment("COMPUTERNAME"),
			"user": OS.get_environment("USERNAME"),
			"cpu": OS.get_processor_name(),
			"cores": OS.get_processor_count(),
		},
		"environment": _environment,
	}
	Store.write_json(_meta_path, meta, true)


func _register_capture() -> void:
	_capture = Capture.new()
	_capture.message_sink = Callable(self, "capture_message")
	_capture.error_sink = Callable(self, "capture_error")
	OS.add_logger(_capture)


func _start_watchdog() -> void:
	if not _watchdog_enabled:
		return
	_watchdog = Watchdog.new()
	_watchdog.beat = Callable(self, "_watchdog_beat")
	_watchdog.sink = Callable(self, "_on_watchdog")
	_watchdog.threshold_ms = hang_threshold_ms
	_watchdog.running = true
	_watchdog.start(Callable(_watchdog, "_run"))


func _stop_watchdog() -> void:
	if _watchdog == null:
		return
	if _watchdog.is_started():
		_watchdog.running = false
		_watchdog.wait_to_finish()
	_watchdog = null


func _watchdog_beat() -> int:
	return _beat_msec


# ---------------------------------------------------------------------------
# Engine capture
# ---------------------------------------------------------------------------

## Called by `log_capture.gd` for every engine message (including plain prints).
## Never call `print`, `push_warning` or `push_error` from here.
func capture_message(message: String, error: bool) -> void:
	if not enabled or not _started:
		return
	var text := _trim_newlines(message)
	if text.length() > MESSAGE_LIMIT:
		text = text.left(MESSAGE_LIMIT) + " …[truncated]"
	var severity := "error" if error else "info"
	_write_record("message", {
		"src": "engine",
		"sev": severity,
		"msg": text,
		"thread": OS.get_thread_caller_id(),
	}, text)


## Called by `log_capture.gd` for warnings, errors, script errors and shader
## errors, with the full ScriptBacktrace (locals and members included).
func capture_error(function: String, file: String, line: int, code: String, rationale: String,
		editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	if not enabled or not _started:
		return
	var severity := _error_severity(error_type)
	var frames: Array = []
	var dumps: Array = []
	for trace in script_backtraces:
		if trace == null:
			continue
		var frame_count := mini(trace.get_frame_count(), 64)
		for frame_index in frame_count:
			frames.append({
				"function": trace.get_frame_function(frame_index),
				"file": trace.get_frame_file(frame_index),
				"line": trace.get_frame_line(frame_index),
			})
		var dump := trace.format()
		if dump.length() > ERROR_TEXT_LIMIT:
			dump = dump.left(ERROR_TEXT_LIMIT) + "\n…[backtrace truncated]"
		dumps.append(dump)
	var backtrace := "\n\n".join(dumps)
	var message := code
	if message.length() > MESSAGE_LIMIT:
		message = message.left(MESSAGE_LIMIT) + " …[truncated]"
	var entry := {
		"ts": Store.utc_iso(),
		"sev": severity,
		"code": message.left(512),
		"function": function,
		"file": file,
		"line": line,
		"error_type": error_type,
		"frames": frames.slice(0, mini(frames.size(), 3)),
	}
	_state_mutex.lock()
	_recent_errors.append(entry)
	while _recent_errors.size() > RECENT_ERROR_LIMIT:
		_recent_errors.pop_front()
	_state_mutex.unlock()
	var thread_id := OS.get_thread_caller_id()
	var payload := {
		"src": "engine",
		"sev": severity,
		"msg": message,
		"function": function,
		"file": file,
		"line": line,
		"rationale": rationale,
		"editor": editor_notify,
		"error_type": error_type,
		"error_name": _error_name(error_type),
		"backtrace": backtrace,
		"frames": frames,
		"thread": thread_id,
		"main_thread": thread_id == OS.get_main_thread_id(),
	}
	_write_record("message", payload, _engine_error_text(payload), true)
	_write_marker()


func _error_severity(error_type: int) -> String:
	match error_type:
		1: return "warning"
		2: return "script_error"
		3: return "shader_error"
		_: return "error"


func _error_name(error_type: int) -> String:
	match error_type:
		0: return "ERROR_TYPE_ERROR"
		1: return "ERROR_TYPE_WARNING"
		2: return "ERROR_TYPE_SCRIPT"
		3: return "ERROR_TYPE_SHADER"
		_: return "ERROR_TYPE_UNKNOWN"


func _trim_newlines(text: String) -> String:
	var result := text
	while result.ends_with("\n") or result.ends_with("\r"):
		result = result.left(result.length() - 1)
	return result


func _engine_error_text(payload: Dictionary) -> String:
	var head := "[%s] %s at %s (%s:%d)" % [
		str(payload.get("sev", "error")),
		str(payload.get("msg", "")).replace("\n", " "),
		str(payload.get("function", "")),
		str(payload.get("file", "")),
		int(payload.get("line", 0)),
	]
	var rationale := str(payload.get("rationale", ""))
	if not rationale.is_empty():
		head += " | " + rationale
	var backtrace := str(payload.get("backtrace", ""))
	if not backtrace.is_empty():
		head += "\n" + backtrace
	return head


# ---------------------------------------------------------------------------
# Records, heartbeats and samples
# ---------------------------------------------------------------------------

func _write_record(kind: String, fields: Dictionary, text: String, critical: bool = false) -> void:
	if not enabled or _jsonl == null:
		return
	var thread_id := OS.get_thread_caller_id()
	if _writing_thread == thread_id:
		return
	_write_mutex.lock()
	_writing_thread = thread_id
	var stamp := Store.utc_iso()
	var record := {
		"schema": Store.SCHEMA_VERSION,
		"k": kind,
		"ts": stamp,
		"unix": Time.get_unix_time_from_system(),
		"mono_ms": Time.get_ticks_msec(),
		"frame": Engine.get_process_frames(),
		"pid": OS.get_process_id(),
		"sid": session_id,
	}
	for key in fields:
		record[key] = fields[key]
	if _truncated and not critical:
		_writing_thread = -1
		_write_mutex.unlock()
		return
	if _truncated and critical and _bytes >= SESSION_BYTES_LIMIT * 2 and kind != "session_end":
		_writing_thread = -1
		_write_mutex.unlock()
		return
	if not _truncated and _bytes >= SESSION_BYTES_LIMIT:
		_truncated = true
		var notice := {
			"schema": Store.SCHEMA_VERSION,
			"k": "log_truncated",
			"ts": stamp,
			"pid": OS.get_process_id(),
			"sid": session_id,
			"limit": SESSION_BYTES_LIMIT,
			"bytes": _bytes,
			"note": "Further messages and samples from this session are dropped; errors and shutdown records continue.",
		}
		_jsonl.store_line(JSON.stringify(notice, "", false, true))
		_text.store_line("[%s] log_truncated after %d bytes" % [stamp, _bytes])
		_jsonl.flush()
		_text.flush()
		if not critical:
			_writing_thread = -1
			_write_mutex.unlock()
			return
	var json_line := JSON.stringify(record, "", false, true)
	var text_line := text if not text.is_empty() else "%s %s" % [kind, JSON.stringify(fields, "", false, true)]
	_jsonl.store_line(json_line)
	_text.store_line(text_line)
	_jsonl.flush()
	_text.flush()
	_bytes += json_line.length() + 1 + text_line.length() + 1
	_records += 1
	_bump_counts(kind, str(record.get("sev", "info")))
	_writing_thread = -1
	_write_mutex.unlock()


func _bump_counts(kind: String, severity: String) -> void:
	match kind:
		"message":
			_counts.messages = int(_counts.messages) + 1
			if severity == "warning":
				_counts.warnings = int(_counts.warnings) + 1
			elif severity.contains("error"):
				_counts.errors = int(_counts.errors) + 1
		"event":
			_counts.events = int(_counts.events) + 1
		"sample":
			_counts.samples = int(_counts.samples) + 1
		"hang", "hang_resume":
			_counts.hangs = int(_counts.hangs) + 1
		_:
			pass


func _copy_counts() -> Dictionary:
	_write_mutex.lock()
	var result := _counts.duplicate(true)
	_write_mutex.unlock()
	return result


func _copy_state() -> Dictionary:
	_state_mutex.lock()
	var result := {
		"context": _context.duplicate(true),
		"sample": _last_sample.duplicate(true),
		"breadcrumbs": _breadcrumbs.duplicate(true),
		"errors": _recent_errors.duplicate(true),
	}
	_state_mutex.unlock()
	return result


func _write_marker(force: bool = false, finished: bool = false) -> void:
	if not enabled or _marker_path.is_empty():
		return
	var now := Time.get_ticks_msec()
	if not force and now - _last_marker_msec < MARKER_MS:
		return
	_last_marker_msec = now
	var state := _copy_state()
	var counts := _copy_counts()
	var breadcrumbs: Array = state.breadcrumbs
	var errors: Array = state.errors
	var marker := {
		"schema": Store.SCHEMA_VERSION,
		"session_id": session_id,
		"pid": OS.get_process_id(),
		"clean": finished,
		"source": _source,
		"started_iso": Store.utc_iso(_started_at),
		"started_unix": _started_at,
		"beat_iso": Store.utc_iso(),
		"beat_unix": Time.get_unix_time_from_system(),
		"beat_mono_ms": now,
		"frame": Engine.get_process_frames(),
		"scene": str(state.sample.get("scene", "")),
		"context": state.context,
		"sample": state.sample,
		"breadcrumbs": breadcrumbs.slice(maxi(0, breadcrumbs.size() - MARKER_BREADCRUMBS)),
		"errors": errors.slice(maxi(0, errors.size() - MARKER_ERRORS)),
		"counts": counts,
		"level": level,
		"project_root": ProjectSettings.globalize_path("res://"),
	}
	if finished:
		marker["end_iso"] = Store.utc_iso(_ended_unix)
		marker["end_unix"] = _ended_unix
		marker["end_reason"] = "clean_exit"
	_marker_mutex.lock()
	Store.write_json(_marker_path, marker, false)
	_marker_mutex.unlock()


func _on_watchdog(kind: String, gap_ms: int, last_beat_ms: int, observed_ms: int) -> void:
	if not enabled or not _started:
		return
	var state := _copy_state()
	var payload := {
		"src": "watchdog",
		"sev": "warn",
		"kind": kind,
		"gap_ms": gap_ms,
		"threshold_ms": hang_threshold_ms,
		"last_beat_ms": last_beat_ms,
		"observed_ms": observed_ms,
		"sample": state.sample,
		"context": state.context,
		"breadcrumbs": state.breadcrumbs.slice(maxi(0, state.breadcrumbs.size() - 8)),
		"static_mem": OS.get_static_memory_usage(),
	}
	var text := "%s main-loop gap=%dms threshold=%dms scene=%s" % [
		kind, gap_ms, hang_threshold_ms, str(state.sample.get("scene", ""))]
	_write_record(kind, payload, text, true)
	if kind == "hang":
		_write_marker(true)


func _sample_text(sample: Dictionary) -> String:
	return "fps=%s process=%sms physics=%sms scene=%s role=%s nodes=%d mem=%dMB mobs=%d" % [
		str(sample.get("fps", 0.0)),
		str(sample.get("process_ms", 0.0)),
		str(sample.get("physics_ms", 0.0)),
		str(sample.get("scene", "")),
		str(sample.get("role", "")),
		int(sample.get("nodes", 0)),
		int(sample.get("static_mem", 0)) / (1024 * 1024),
		int(sample.get("mobs", 0)),
	]


func _collect_sample() -> Dictionary:
	var tree := get_tree()
	var scene: Node = tree.current_scene if tree != null else null
	var sample := {
		"fps": snappedf(Performance.get_monitor(Performance.TIME_FPS), 0.01),
		"fps_engine": snappedf(Engine.get_frames_per_second(), 0.01),
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.001),
		"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.001),
		"frame": Engine.get_process_frames(),
		"physics_frame": Engine.get_physics_frames(),
		"static_mem": OS.get_static_memory_usage(),
		"static_mem_peak": OS.get_static_memory_peak_usage(),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"object_nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_nodes": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"video_mem": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		"physics_active": int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		"physics_pairs": int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		"scene": scene.scene_file_path if scene != null else "",
		"scene_class": scene.get_class() if scene != null else "",
		"nodes": tree.get_node_count() if tree != null else 0,
		"mobs": tree.get_node_count_in_group("wild_mobs") if tree != null else 0,
		"cinder_devils": tree.get_node_count_in_group("cinder_devils") if tree != null else 0,
		"input": "captured" if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else "visible",
		"window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"memory": _memory_summary(),
		"multiplayer": _multiplayer_summary(),
		"game": _game_sample(scene),
		"player_state": _player_state_sample(),
	}
	return sample


func _memory_summary() -> Dictionary:
	var info := OS.get_memory_info()
	return {
		"physical": int(info.get("physical", 0)),
		"free": int(info.get("free", 0)),
		"available": int(info.get("available", 0)),
		"stack": int(info.get("stack", 0)),
	}


func _multiplayer_summary() -> Dictionary:
	var peer := multiplayer.multiplayer_peer
	var connected := false
	if peer != null and peer is MultiplayerPeer:
		connected = peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	return {
		"peer": peer != null,
		"connected": connected,
		"unique_id": multiplayer.get_unique_id(),
		"peers": multiplayer.get_peers().size(),
	}


func _game_sample(scene: Node) -> Dictionary:
	if scene == null:
		return {}
	var game := {
		"role": _scene_value(scene, "network_role"),
		"phase": _scene_value(scene, "phase"),
		"depth": _scene_value(scene, "depth"),
		"local_slot": _scene_value(scene, "local_slot"),
		"health": _scene_value(scene, "health"),
		"max_health": _scene_value(scene, "max_health"),
		"stamina": _scene_value(scene, "stamina"),
		"max_stamina": _scene_value(scene, "max_stamina"),
		"gold": _scene_value(scene, "gold"),
		"kills": _scene_value(scene, "kills"),
		"respawns": _scene_value(scene, "respawns"),
		"endpoint": _scene_value(scene, "_endpoint"),
		"world_port": _scene_value(scene, "_world_port"),
	}
	var player = scene.get("player")
	if player != null and is_instance_valid(player) and player is Node3D:
		game["player"] = {
			"position": [snappedf(player.global_position.x, 0.001), snappedf(player.global_position.y, 0.001), snappedf(player.global_position.z, 0.001)],
			"velocity": [snappedf(player.velocity.x, 0.001), snappedf(player.velocity.y, 0.001), snappedf(player.velocity.z, 0.001)],
			"on_floor": bool(player.is_on_floor()),
		}
	var actors = scene.get("actors")
	var local_slot := int(scene.get("local_slot")) if scene.get("local_slot") != null else -1
	if actors is Array and local_slot >= 0 and local_slot < actors.size():
		var actor = actors[local_slot]
		if actor != null and is_instance_valid(actor):
			game["local_actor"] = {
				"health": _scene_value(actor, "health"),
				"alive": _scene_value(actor, "alive"),
				"max_health": _scene_value(actor, "max_health"),
				"display_name": _scene_value(actor, "display_name"),
			}
	if actors is Array:
		var roster: Array = []
		for actor in actors:
			if actor == null or not is_instance_valid(actor):
				continue
			roster.append({
				"slot": _scene_value(actor, "slot"),
				"peer": _scene_value(actor, "peer_id"),
				"name": _scene_value(actor, "display_name"),
				"health": _scene_value(actor, "health"),
				"max_health": _scene_value(actor, "max_health"),
				"alive": _scene_value(actor, "alive"),
				"bot": _scene_value(actor, "is_bot"),
				"authoritative": _scene_value(actor, "authoritative"),
			})
		if not roster.is_empty():
			game["actors"] = roster
	if scene.has_method("_run_state_dict"):
		var run = scene.call("_run_state_dict")
		if typeof(run) == TYPE_DICTIONARY:
			game["run"] = _clean_variant(run)
	for key in game.keys():
		if game[key] == null:
			game.erase(key)
	return game


func _scene_value(object: Object, property: String) -> Variant:
	if object == null:
		return null
	var value = object.get(property)
	if value == null:
		return null
	return _clean_variant(value)


func _player_state_sample() -> Dictionary:
	var state := get_node_or_null("/root/PlayerState")
	if state == null:
		return {}
	var inventory_source = state.get("inventory")
	var stash_source = state.get("stash")
	var floor_source = state.get("floor_items")
	var quick = state.get("quick")
	var quick_back = state.get("quick_back")
	var equipped = state.get("equipped")
	var inventory: Array = _clean_variant(inventory_source) if inventory_source is Array else []
	var stash: Array = _clean_variant(stash_source) if stash_source is Array else []
	var floor_items: Array = _clean_variant(floor_source) if floor_source is Array else []
	return {
		"credits": int(state.get("credits")),
		"inventory": inventory,
		"inventory_count": inventory.size(),
		"stash": stash,
		"stash_count": stash.size(),
		"floor": floor_items,
		"floor_count": floor_items.size(),
		"quick": _clean_variant(quick) if typeof(quick) == TYPE_DICTIONARY else {},
		"quick_back": _clean_variant(quick_back) if typeof(quick_back) == TYPE_DICTIONARY else {},
		"equipped": _clean_variant(equipped) if typeof(equipped) == TYPE_DICTIONARY else {},
	}


# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

func _build_environment() -> Dictionary:
	var version := Engine.get_version_info()
	var memory := OS.get_memory_info()
	var screen_count := DisplayServer.get_screen_count()
	var screen_size := [0, 0]
	var screen_usable := [0, 0, 0, 0]
	var screen_dpi := 0
	var screen_scale := 1.0
	var refresh := 0.0
	if screen_count > 0:
		var screen := DisplayServer.get_primary_screen()
		var size := DisplayServer.screen_get_size(screen)
		var usable := DisplayServer.screen_get_usable_rect(screen)
		screen_size = [size.x, size.y]
		screen_usable = [usable.position.x, usable.position.y, usable.size.x, usable.size.y]
		screen_dpi = DisplayServer.screen_get_dpi(screen)
		screen_scale = DisplayServer.screen_get_scale(screen)
		refresh = DisplayServer.screen_get_refresh_rate(screen)
	var output_devices: Array = []
	for device in AudioServer.get_output_device_list():
		output_devices.append(str(device))
	var features: Dictionary = {}
	for feature in ["debug", "editor", "template", "distribution", "pc", "mobile", "web",
			"windows", "linuxbsd", "macos", "x86_64", "arm64", "double", "single"]:
		features[feature] = OS.has_feature(feature)
	var args: Array = []
	for argument in OS.get_cmdline_args():
		args.append(str(argument))
	var user_args: Array = []
	for argument in OS.get_cmdline_user_args():
		user_args.append(str(argument))
	var window_size := DisplayServer.window_get_size()
	return {
		"engine": {
			"version": str(version.get("string", "")),
			"major": int(version.get("major", 0)),
			"minor": int(version.get("minor", 0)),
			"patch": int(version.get("patch", 0)),
			"hash": str(version.get("hash", "")),
			"build": str(version.get("build", "")),
			"status": str(version.get("status", "")),
			"architecture": Engine.get_architecture_name(),
			"physics_hz": int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60)),
			"features": features,
		},
		"os": {
			"name": OS.get_name(),
			"version": OS.get_version(),
			"version_alias": OS.get_version_alias(),
			"locale": OS.get_locale(),
			"language": OS.get_locale_language(),
			"timezone": Time.get_time_zone_from_system(),
			"processor": OS.get_processor_name(),
			"cores": OS.get_processor_count(),
			"computer": OS.get_environment("COMPUTERNAME"),
			"user": OS.get_environment("USERNAME"),
			"processor_identifier": OS.get_environment("PROCESSOR_IDENTIFIER"),
			"memory": {
				"physical": int(memory.get("physical", 0)),
				"free": int(memory.get("free", 0)),
				"available": int(memory.get("available", 0)),
				"stack": int(memory.get("stack", 0)),
			},
			"executable": OS.get_executable_path(),
			"user_dir": OS.get_user_data_dir(),
		},
		"project": {
			"name": str(ProjectSettings.get_setting("application/config/name", "")),
			"version": str(ProjectSettings.get_setting("application/config/version", "")),
			"description": str(ProjectSettings.get_setting("application/config/description", "")),
			"main_scene": str(ProjectSettings.get_setting("application/run/main_scene", "")),
			"root": ProjectSettings.globalize_path("res://"),
			"features": Array(ProjectSettings.get_setting("config/features", PackedStringArray())),
		},
		"rendering": {
			"method": RenderingServer.get_current_rendering_method(),
			"driver": RenderingServer.get_current_rendering_driver_name(),
			"adapter": RenderingServer.get_video_adapter_name(),
			"vendor": RenderingServer.get_video_adapter_vendor(),
			"api_version": RenderingServer.get_video_adapter_api_version(),
			"video_mem": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		},
		"display": {
			"server": DisplayServer.get_name(),
			"window_size": [window_size.x, window_size.y],
			"window_mode": DisplayServer.window_get_mode(),
			"vsync": DisplayServer.window_get_vsync_mode(),
			"screen_count": screen_count,
			"screen_size": screen_size,
			"screen_usable": screen_usable,
			"dpi": screen_dpi,
			"scale": screen_scale,
			"max_scale": DisplayServer.screen_get_max_scale(),
			"refresh_rate": refresh,
		},
		"audio": {
			"driver": AudioServer.get_driver_name(),
			"mix_rate": AudioServer.get_mix_rate(),
			"output_device": AudioServer.get_output_device(),
			"output_devices": output_devices,
		},
		"input": {
			"joypads": Input.get_connected_joypads().size(),
		},
		"process": {
			"pid": OS.get_process_id(),
			"main_thread": OS.get_main_thread_id(),
			"executable": OS.get_executable_path(),
			"user_dir": OS.get_user_data_dir(),
			"static_memory": OS.get_static_memory_usage(),
			"static_memory_peak": OS.get_static_memory_peak_usage(),
			"args": args,
			"user_args": user_args,
		},
	}


# ---------------------------------------------------------------------------
# Crash detection and reports
# ---------------------------------------------------------------------------

## Scans sessions written by processes that are no longer running and turns each
## unclean one into a crash report. Safe to call repeatedly; a reported marker is
## flagged so it is never reported twice.
func scan_for_crashes() -> Array:
	var created: Array = []
	if not enabled:
		return created
	var active_names := Store.list_files(_sessions_dir, ".active.json")
	var active_ids := {}
	var candidates: Array = []
	for name in active_names:
		var sid := str(name).trim_suffix(".active.json")
		active_ids[sid] = true
		if sid.is_empty() or sid == session_id:
			continue
		var marker_path := _sessions_dir.path_join(str(name))
		var marker: Variant = Store.read_json(marker_path)
		if typeof(marker) != TYPE_DICTIONARY:
			# A torn marker can be a crash mid-write. Only trust it once it is old
			# enough that no live instance could still own the file.
			var age := Time.get_unix_time_from_system() - float(FileAccess.get_modified_time(marker_path))
			if age < UNREADABLE_MARKER_AGE_SECONDS:
				continue
			candidates.append({"sid": sid, "marker": {"session_id": sid, "clean": false},
				"name": str(name), "reason": "unreadable_marker"})
			continue
		var data: Dictionary = marker
		if _was_reported(sid) or bool(data.get("reported_crash", false)) or bool(data.get("clean", false)):
			continue
		if int(data.get("pid", 0)) == OS.get_process_id():
			continue
		candidates.append({"sid": sid, "marker": data, "name": str(name), "reason": "process_missing"})
	# `OS.is_process_running` only answers for processes this OS object created,
	# so another game instance needs the real OS process table. It is read once
	# per scan, and only when an unclean marker actually exists.
	var live_pids := {}
	var pid_table_ready := false
	if not candidates.is_empty():
		live_pids = _running_pids()
		pid_table_ready = not live_pids.is_empty()
	var now := Time.get_unix_time_from_system()
	for candidate in candidates:
		var marker_data: Dictionary = candidate.marker
		var pid := int(marker_data.get("pid", 0))
		var running := OS.is_process_running(pid) if pid > 0 else false
		if not running and pid > 0:
			running = bool(live_pids.get(pid, false))
		if running:
			continue
		if pid > 0 and not pid_table_ready:
			# No process table: require a stale heartbeat before calling it dead.
			var beat_unix := float(marker_data.get("beat_unix", 0.0))
			if beat_unix > 0.0 and now - beat_unix < LIVE_GRACE_SECONDS:
				continue
		created.append(_report_session(str(candidate.sid), marker_data, str(candidate.name), str(candidate.reason)))
	# A session that predates the marker (or crashed between opening its files
	# and the first marker) still has a log with no clean end record.
	for name in Store.list_files(_sessions_dir, ".jsonl"):
		var sid := str(name).trim_suffix(".jsonl")
		if sid.is_empty() or sid == session_id or active_ids.has(sid) or _was_reported(sid):
			continue
		var path := _sessions_dir.path_join(str(name))
		var age := Time.get_unix_time_from_system() - float(FileAccess.get_modified_time(path))
		if age < CLEAN_LOG_AGE_SECONDS:
			continue
		if _log_ends_cleanly(path):
			continue
		created.append(_report_session(sid, {"session_id": sid, "clean": false, "pid": 0}, "", "log_without_clean_exit"))
	return created


## Every live PID on this machine. Godot's `OS.is_process_running` is scoped to
## processes the calling `OS` object created, so a second game instance would be
## reported as crashed without this. One command per scan, never per marker.
func _running_pids() -> Dictionary:
	var result := {}
	var output: Array = []
	var code := 0
	if OS.get_name() == "Windows":
		code = OS.execute("tasklist", PackedStringArray(["/FO", "CSV", "/NH"]), output)
		if code != 0 or output.is_empty():
			output.clear()
			code = OS.execute("C:/Windows/System32/tasklist.exe", PackedStringArray(["/FO", "CSV", "/NH"]), output)
		if code != 0 or output.is_empty():
			return result
		var text := "\n".join(PackedStringArray(output))
		for line in text.split("\n"):
			var columns := str(line).split(",")
			if columns.size() < 2:
				continue
			var pid_text := str(columns[1]).replace("\"", "").strip_edges()
			if pid_text.is_valid_int():
				result[int(pid_text)] = true
	else:
		code = OS.execute("ps", PackedStringArray(["-A", "-o", "pid="]), output)
		if code != 0 or output.is_empty():
			return result
		var text := "\n".join(PackedStringArray(output))
		for line in text.split("\n"):
			var pid_text := str(line).strip_edges()
			if pid_text.is_valid_int():
				result[int(pid_text)] = true
	return result


func _log_ends_cleanly(path: String) -> bool:
	var tail := Store.tail_lines(path, 2)
	if tail.is_empty():
		return false
	var parsed: Variant = JSON.parse_string(tail[tail.size() - 1])
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var record: Dictionary = parsed
	return str(record.get("k", "")) == "session_end" and bool(record.get("clean", false))


func _was_reported(sid: String) -> bool:
	return FileAccess.file_exists(_reported_path(sid))


func _reported_path(sid: String) -> String:
	return _sessions_dir.path_join(sid + ".reported.json")


func _report_session(sid: String, marker: Dictionary, marker_name: String, reason: String) -> Dictionary:
	var log_path := _sessions_dir.path_join(sid + ".jsonl")
	var text_log_path := _sessions_dir.path_join(sid + ".log")
	var meta: Dictionary = {}
	var parsed_meta: Variant = Store.read_json(_sessions_dir.path_join(sid + ".meta.json"))
	if typeof(parsed_meta) == TYPE_DICTIONARY:
		meta = parsed_meta
	var archived_jsonl := _crashes_dir.path_join(sid + ".jsonl")
	var archived_text := _crashes_dir.path_join(sid + ".log")
	if not FileAccess.file_exists(archived_jsonl):
		Store.copy_file(log_path, archived_jsonl)
	if not FileAccess.file_exists(archived_text):
		Store.copy_file(text_log_path, archived_text)
	var detected_unix := Time.get_unix_time_from_system()
	var stamp := Store.utc_stamp(detected_unix)
	var json_path := _crashes_dir.path_join("crash-%s-%s.json" % [stamp, sid])
	var text_path := _crashes_dir.path_join("crash-%s-%s.txt" % [stamp, sid])
	var tail := Store.tail_lines(log_path, LOG_TAIL_LINES)
	var beat_unix := float(marker.get("beat_unix", 0.0))
	var beat_age := maxf(0.0, detected_unix - beat_unix) if beat_unix > 0.0 else -1.0
	var report := {
		"schema": Store.SCHEMA_VERSION,
		"kind": "crash_report",
		"detected_iso": Store.utc_iso(detected_unix),
		"detected_unix": detected_unix,
		"detector": {
			"session_id": session_id,
			"pid": OS.get_process_id(),
			"engine": str(Engine.get_version_info().get("string", "")),
			"root": ProjectSettings.globalize_path("res://"),
		},
		"reason": reason,
		"evidence": {
			"marker_present": not marker_name.is_empty(),
			"marker_file": marker_name,
			"pid": int(marker.get("pid", 0)),
			"pid_running": false,
			"clean": bool(marker.get("clean", false)),
			"reported_crash": bool(marker.get("reported_crash", false)),
			"last_beat_iso": str(marker.get("beat_iso", "")),
			"last_beat_age_s": snappedf(beat_age, 0.001),
			"log_ends_cleanly": _log_ends_cleanly(log_path),
			"log_modified_iso": Store.utc_iso(float(FileAccess.get_modified_time(log_path))) if FileAccess.file_exists(log_path) else "",
			"log_exists": FileAccess.file_exists(log_path),
		},
		"previous": marker,
		"environment": meta.get("environment", {}),
		"project": meta.get("project", {}),
		"host": meta.get("host", {}),
		"meta": meta,
		"context": marker.get("context", {}),
		"last_sample": marker.get("sample", {}),
		"breadcrumbs": marker.get("breadcrumbs", []),
		"errors": marker.get("errors", []),
		"counters": _int_counts(marker.get("counts", {})),
		"log": {
			"path": log_path,
			"text_path": text_log_path,
			"archived_jsonl": archived_jsonl if FileAccess.file_exists(archived_jsonl) else "",
			"archived_text": archived_text if FileAccess.file_exists(archived_text) else "",
			"bytes": Store.file_bytes(log_path),
			"lines": Store.line_count(log_path),
			"tail": Array(tail),
		},
		"text_path": text_path,
		"notes": [
			"No renderer minidump is produced by Godot's official release build; this report reconstructs the final seconds from the flushed log and the heartbeat marker.",
			"The archived session log next to this report is the unmodified record of the run.",
			"A process killed before its clean marker is written is reported here even when the exit itself was graceful.",
		],
	}
	Store.write_json(json_path, report, true)
	Store.write_text(text_path, _format_report(report))
	# A companion file marks the session as reported without round-tripping the
	# marker through JSON, which would turn every integer into a float.
	Store.write_json(_reported_path(sid), {
		"session_id": sid,
		"reported_iso": Store.utc_iso(detected_unix),
		"reported_unix": detected_unix,
		"reported_by": session_id,
		"report": json_path,
		"reason": reason,
	}, false)
	var entry := {
		"session_id": sid,
		"json_path": json_path,
		"text_path": text_path,
		"reason": reason,
		"detected_iso": str(report.detected_iso),
		"summary": _report_summary(report),
	}
	_pending_reports.push_front(entry)
	print("IRONWOOD_CRASH_REPORT ", ProjectSettings.globalize_path(text_path), " session=", sid, " reason=", reason)
	return entry


func _int_counts(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var result := {}
	var counts: Dictionary = value
	for key in counts:
		result[str(key)] = int(counts[key])
	return result


func _report_summary(report: Dictionary) -> String:
	var sample: Variant = report.get("last_sample", {})
	var scene_name := str(sample.get("scene", "")) if typeof(sample) == TYPE_DICTIONARY else ""
	var previous: Dictionary = report.get("previous", {})
	var errors: Array = report.get("errors", [])
	var last_error := ""
	if not errors.is_empty() and typeof(errors[errors.size() - 1]) == TYPE_DICTIONARY:
		last_error = str(errors[errors.size() - 1].get("code", ""))
	var scene_label := scene_name.get_file() if not scene_name.is_empty() else "script"
	return ("%s pid=%s %s" % [scene_label, str(previous.get("pid", 0)), last_error]).strip_edges()


func _format_report(report: Dictionary) -> String:
	var lines := PackedStringArray()
	var previous: Dictionary = report.get("previous", {})
	var evidence: Dictionary = report.get("evidence", {})
	var log: Dictionary = report.get("log", {})
	lines.append("IRONWOOD CRASH REPORT")
	lines.append("======================")
	lines.append("Detected:          %s" % str(report.get("detected_iso", "")))
	lines.append("Previous session:  %s  (pid %s)" % [str(previous.get("session_id", "")), str(previous.get("pid", ""))])
	lines.append("Session started:   %s" % str(previous.get("started_iso", "")))
	lines.append("Last heartbeat:    %s  (%s s before detection)" % [str(evidence.get("last_beat_iso", "")), str(evidence.get("last_beat_age_s", ""))])
	lines.append("Reason:            %s" % str(report.get("reason", "")))
	lines.append("Last scene:        %s" % str(report.get("last_sample", {}).get("scene", "")))
	lines.append("Log:               %s (%s bytes, %s lines)" % [str(log.get("path", "")), str(log.get("bytes", 0)), str(log.get("lines", 0))])
	lines.append("Archived log:      %s" % str(log.get("archived_jsonl", "")))
	lines.append("JSON report:       %s" % str(report.get("text_path", "")).replace(".txt", ".json"))
	lines.append("")
	lines.append("ENVIRONMENT")
	lines.append("-----------")
	lines.append(JSON.stringify(report.get("environment", {}), "  ", false, true))
	lines.append("")
	lines.append("CONTEXT")
	lines.append("-------")
	lines.append(JSON.stringify(report.get("context", {}), "  ", false, true))
	lines.append("")
	lines.append("LAST STATE SAMPLE")
	lines.append("-----------------")
	lines.append(JSON.stringify(report.get("last_sample", {}), "  ", false, true))
	lines.append("")
	lines.append("BREADCRUMBS (newest last)")
	lines.append("-------------------------")
	var breadcrumbs: Array = report.get("breadcrumbs", [])
	if breadcrumbs.is_empty():
		lines.append("(none)")
	else:
		for crumb in breadcrumbs:
			if typeof(crumb) != TYPE_DICTIONARY:
				continue
			lines.append("%s [%s] %s %s" % [
				str(crumb.get("ts", "")), str(crumb.get("cat", "")),
				str(crumb.get("msg", "")), JSON.stringify(crumb.get("data", {}), "", false, true)])
	lines.append("")
	lines.append("RECENT ENGINE ERRORS")
	lines.append("--------------------")
	var errors: Array = report.get("errors", [])
	if errors.is_empty():
		lines.append("(none captured in the heartbeat marker; the JSONL tail below is authoritative)")
	else:
		for error in errors:
			if typeof(error) != TYPE_DICTIONARY:
				continue
			lines.append("[%s] %s at %s (%s:%s) type=%s" % [
				str(error.get("ts", "")), str(error.get("sev", "")), str(error.get("function", "")),
				str(error.get("file", "")), str(error.get("line", 0)), str(error.get("error_type", 0))])
			var head := str(error.get("code", ""))
			if not head.is_empty():
				lines.append("  " + head.replace("\n", "\n  "))
			var frames: Array = error.get("frames", [])
			for frame in frames:
				if typeof(frame) == TYPE_DICTIONARY:
					lines.append("  at %s (%s:%s)" % [str(frame.get("function", "")), str(frame.get("file", "")), str(frame.get("line", 0))])
	lines.append("")
	lines.append("LOG TAIL (last %d lines)" % LOG_TAIL_LINES)
	lines.append("------------------------")
	var tail: Array = log.get("tail", [])
	if tail.is_empty():
		lines.append("(no log file)")
	else:
		for line in tail:
			lines.append(str(line))
	lines.append("")
	lines.append("COUNTERS")
	lines.append("--------")
	lines.append(JSON.stringify(report.get("counters", {}), "  ", false, true))
	lines.append("")
	lines.append("NOTES")
	lines.append("-----")
	for note in report.get("notes", []):
		lines.append("- " + str(note))
	lines.append("")
	lines.append("Attach this file, the JSON report and the archived session log to a bug report.")
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

func _clean_variant(value: Variant, depth: int = 0) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return value
		TYPE_FLOAT:
			return value if is_finite(value) else str(value)
		TYPE_STRING:
			var text := str(value)
			return text.left(DATA_STRING_LIMIT) if text.length() > DATA_STRING_LIMIT else text
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(value)
		TYPE_VECTOR2:
			return [value.x, value.y]
		TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR3:
			return [value.x, value.y, value.z]
		TYPE_VECTOR3I:
			return [value.x, value.y, value.z]
		TYPE_COLOR:
			return value.to_html()
		TYPE_ARRAY:
			if depth >= 3:
				return "[array]"
			var items: Array = []
			for index in mini(value.size(), 200):
				items.append(_clean_variant(value[index], depth + 1))
			return items
		TYPE_DICTIONARY:
			if depth >= 3:
				return "{dict}"
			var result := {}
			var count := 0
			for key in value:
				if count >= 100:
					break
				result[str(key)] = _clean_variant(value[key], depth + 1)
				count += 1
			return result
		TYPE_OBJECT:
			if value == null:
				return "<null>"
			return "<%s>" % value.get_class()
		_:
			return str(value).left(DATA_STRING_LIMIT)
