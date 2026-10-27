extends Logger
## Receives every engine message, warning and error and hands it to `Log`.
##
## The callbacks can run on any thread while the engine is already printing, so
## this object must never print, push a message or touch a node: it only forwards
## to the sinks. `Log` owns the mutexes, the re-entrancy guard and the files.

var message_sink := Callable()
var error_sink := Callable()


func _log_message(message: String, error: bool) -> void:
	if message_sink.is_valid():
		message_sink.call(message, error)


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_sink.is_valid():
		error_sink.call(function, file, line, code, rationale, editor_notify, error_type, script_backtraces)
