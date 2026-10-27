extends SceneTree
## Child process fixture for `logging_regression`.
##
## `--mode=clean` quits normally so the logger must write its clean marker.
## `--mode=crash` forces a heartbeat, waits, then kills the process so the next
## launch must reconstruct a crash report. `--mode=off` just prints; the parent
## passes `--no-log` with it to prove the off switch writes no session at all.

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var mode := "clean"
	for argument in OS.get_cmdline_user_args():
		var text := str(argument)
		if text.begins_with("--mode="):
			mode = text.trim_prefix("--mode=")
	var log := root.get_node_or_null("Log")
	if mode == "off":
		print("LOGGING_OFF_CHILD")
		quit(0)
		return
	if mode == "clean":
		print("LOGGING_CLEAN_CHILD")
		if log != null:
			log.event("test", "clean child")
			log.force_sample()
		await process_frame
		quit(0)
		return
	print("LOGGING_CRASH_CHILD_READY")
	if log != null:
		log.event("test", "crash child ready")
		log.force_sample()
	await create_timer(2.5).timeout
	print("LOGGING_CRASH_CHILD_KILLING")
	OS.kill(OS.get_process_id())
