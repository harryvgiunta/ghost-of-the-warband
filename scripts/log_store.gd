extends RefCounted
## File-system helpers for the automatic session logger and its crash reports.
##
## Everything here is static and shell-like: the logger uses it on the boot path
## and the regression can exercise retention against a scratch folder. Paths are
## `user://` or absolute; `DirAccess` calls globalize them because the static
## absolute helpers only take OS paths.

const SCHEMA_VERSION := 1
## Live instances and a just-crashed session keep writing their logs; never
## prune a group that changed recently, even under retention pressure.
const KEEP_RECENT_SECONDS := 90.0

const SESSION_SUFFIXES := [".active.json", ".meta.json", ".reported.json", ".jsonl", ".log"]


static func utc_iso(unix_time: float = -1.0) -> String:
	var seconds := Time.get_unix_time_from_system() if unix_time < 0.0 else unix_time
	var whole := int(floor(seconds))
	var millis := clampi(int(floor((seconds - float(whole)) * 1000.0)), 0, 999)
	var date := Time.get_datetime_dict_from_unix_time(whole)
	return "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ" % [
		int(date.year), int(date.month), int(date.day),
		int(date.hour), int(date.minute), int(date.second), millis]


static func utc_stamp(unix_time: float = -1.0) -> String:
	var seconds := Time.get_unix_time_from_system() if unix_time < 0.0 else unix_time
	var date := Time.get_datetime_dict_from_unix_time(int(floor(seconds)))
	return "%04d%02d%02dT%02d%02d%02dZ" % [
		int(date.year), int(date.month), int(date.day),
		int(date.hour), int(date.minute), int(date.second)]


## A filename-safe fragment used in session ids: `res://main.tscn` becomes
## `main`, `res://tests/logging_regression.gd` becomes `logging_regression`.
static func slug(text: String, max_length: int = 32) -> String:
	var source := text.get_file().get_basename().to_lower()
	var result := ""
	for index in source.length():
		var character := source.substr(index, 1)
		var code := character.unicode_at(0)
		var keep := (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
		if keep:
			result += character
		elif not result.is_empty() and not result.ends_with("_"):
			result += "_"
	result = result.trim_prefix("_").trim_suffix("_")
	if result.is_empty():
		result = "session"
	return result.left(maxi(1, max_length))


static func ensure_dir(path: String) -> bool:
	var global := ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(global):
		return true
	return DirAccess.make_dir_recursive_absolute(global) == OK


static func file_exists(path: String) -> bool:
	return FileAccess.file_exists(path)


static func file_bytes(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length := file.get_length()
	file.close()
	return length


static func line_count(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	return FileAccess.get_file_as_string(path).count("\n")


static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed


static func write_json(path: String, value: Variant, pretty: bool = false) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "  " if pretty else "", false, true))
	file.flush()
	file.close()
	return true


static func write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	file.close()
	return true


static func append_line(path: String, line: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.seek_end()
	file.store_line(line)
	file.flush()
	file.close()
	return true


static func copy_file(from_path: String, to_path: String) -> bool:
	if not FileAccess.file_exists(from_path):
		return false
	ensure_dir(to_path.get_base_dir())
	return DirAccess.copy_absolute(
		ProjectSettings.globalize_path(from_path),
		ProjectSettings.globalize_path(to_path)) == OK


static func tail_lines(path: String, count: int) -> PackedStringArray:
	if not FileAccess.file_exists(path):
		return PackedStringArray()
	var lines := FileAccess.get_file_as_string(path).split("\n")
	if not lines.is_empty() and lines[lines.size() - 1].is_empty():
		lines.remove_at(lines.size() - 1)
	var begin := maxi(0, lines.size() - maxi(0, count))
	return PackedStringArray(lines.slice(begin))


static func list_files(directory: String, suffix: String = "") -> PackedStringArray:
	var result := PackedStringArray()
	var global := ProjectSettings.globalize_path(directory)
	if not DirAccess.dir_exists_absolute(global):
		return result
	for name in DirAccess.get_files_at(global):
		var file_name := str(name)
		if suffix.is_empty() or file_name.ends_with(suffix):
			result.append(file_name)
	result.sort()
	return result


static func remove(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


static func session_id_from_file(file_name: String) -> String:
	for suffix in SESSION_SUFFIXES:
		if file_name.ends_with(suffix):
			return file_name.trim_suffix(suffix)
	return ""


static func _session_groups(directory: String) -> Array:
	var newest := {}
	for name in list_files(directory):
		var id := session_id_from_file(str(name))
		if id.is_empty():
			continue
		var modified := FileAccess.get_modified_time(directory.path_join(str(name)))
		if not newest.has(id) or int(newest[id]) < modified:
			newest[id] = modified
	var groups: Array = []
	for id in newest:
		groups.append({"id": id, "mtime": int(newest[id])})
	return groups


static func _group_files(directory: String, id: String) -> PackedStringArray:
	var result := PackedStringArray()
	var prefix := id + "."
	for name in list_files(directory):
		if str(name).begins_with(prefix) and not session_id_from_file(str(name)).is_empty():
			result.append(str(name))
	return result


static func _delete_group(directory: String, id: String) -> int:
	var freed := 0
	for name in _group_files(directory, id):
		var path := directory.path_join(str(name))
		freed += file_bytes(path)
		remove(path)
	return freed


static func _crash_archive_files(directory: String, report_name: String) -> PackedStringArray:
	var result := PackedStringArray()
	var marker := report_name.find("session-")
	if marker < 0:
		return result
	var id := report_name.substr(marker)
	for suffix in [".json", ".txt"]:
		if id.ends_with(suffix):
			id = id.trim_suffix(suffix)
			break
	for name in list_files(directory):
		var file_name := str(name)
		if file_name == report_name:
			result.append(file_name)
		elif file_name == report_name.get_basename() + ".txt":
			result.append(file_name)
		elif file_name.begins_with(id + "."):
			result.append(file_name)
	return result


static func _delete_crash_report(directory: String, report_name: String) -> int:
	var freed := 0
	for name in _crash_archive_files(directory, report_name):
		var path := directory.path_join(str(name))
		freed += file_bytes(path)
		remove(path)
	return freed


static func _dir_bytes(directory: String) -> int:
	var total := 0
	for name in list_files(directory):
		total += file_bytes(directory.path_join(str(name)))
	return total


## Enforces the session/crash retention budget. The protected session (the one
## currently writing) is never deleted. Returns what was removed.
static func prune(root: String, keep_session_count: int, keep_crash_count: int, max_bytes: int,
		protected_id: String = "", protect_recent: bool = true) -> Dictionary:
	var sessions_dir := root.path_join("sessions")
	var crashes_dir := root.path_join("crashes")
	var sessions_removed := 0
	var crashes_removed := 0
	var bytes_freed := 0
	var recent_cutoff := Time.get_unix_time_from_system() - KEEP_RECENT_SECONDS

	var groups := _session_groups(sessions_dir)
	groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.mtime) > int(b.mtime))
	var kept_sessions := 0
	var session_units: Array = []
	for group in groups:
		var id := str(group.id)
		if id == protected_id:
			continue
		if protect_recent and float(group.mtime) > recent_cutoff:
			continue
		session_units.append(group)
		if kept_sessions < keep_session_count:
			kept_sessions += 1
			continue
		bytes_freed += _delete_group(sessions_dir, id)
		sessions_removed += 1

	var reports: Array = []
	for name in list_files(crashes_dir, ".json"):
		var file_name := str(name)
		if not file_name.begins_with("crash-"):
			continue
		reports.append({"name": file_name, "mtime": FileAccess.get_modified_time(crashes_dir.path_join(file_name))})
	reports.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.mtime) > int(b.mtime))
	var kept_reports := 0
	var crash_units: Array = []
	for report in reports:
		if protect_recent and float(report.mtime) > recent_cutoff:
			continue
		crash_units.append(report)
		if kept_reports < keep_crash_count:
			kept_reports += 1
			continue
		bytes_freed += _delete_crash_report(crashes_dir, str(report.name))
		crashes_removed += 1

	if max_bytes <= 0:
		return {"sessions_removed": sessions_removed, "crashes_removed": crashes_removed, "bytes_freed": bytes_freed}

	var total := _dir_bytes(sessions_dir) + _dir_bytes(crashes_dir)
	# Under pressure the oldest sessions go first, then the oldest crash reports.
	session_units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.mtime) > int(b.mtime))
	for group in session_units:
		if total <= max_bytes:
			break
		var id := str(group.id)
		if id == protected_id:
			continue
		if protect_recent and float(group.mtime) > recent_cutoff:
			continue
		var freed := _delete_group(sessions_dir, id)
		if freed <= 0:
			continue
		total -= freed
		bytes_freed += freed
		sessions_removed += 1
	crash_units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.mtime) > int(b.mtime))
	for report in crash_units:
		if total <= max_bytes:
			break
		if protect_recent and float(report.mtime) > recent_cutoff:
			continue
		var freed := _delete_crash_report(crashes_dir, str(report.name))
		if freed <= 0:
			continue
		total -= freed
		bytes_freed += freed
		crashes_removed += 1

	return {"sessions_removed": sessions_removed, "crashes_removed": crashes_removed, "bytes_freed": bytes_freed}
