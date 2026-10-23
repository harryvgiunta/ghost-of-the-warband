extends RefCounted
## Static-only run-checkpoint helper for the Sunken Delve.
##
## Callers preload this script and use it as a namespace; it is deliberately not
## an autoload. The JSON file survives between sessions so a sealed run can be
## resumed at the last cleared wave.

const SAVE_PATH := "user://delve_state.json"
const VERSION := 1
const WAVE_COUNT := 3

const _WAVE_WEAPONS := {
	1: ["claw", "dagger"],
	2: ["claw", "sword"],
	3: ["sword", "dagger"],
}


static func wave_count() -> int:
	return WAVE_COUNT


static func wave_size(_wave: int) -> int:
	return 2


static func wave_weapons(wave: int) -> Array:
	var clamped := clampi(wave, 1, WAVE_COUNT)
	var weapons: Array = _WAVE_WEAPONS[clamped]
	return weapons.duplicate()


static func load_run(path: String = SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = parsed
	if not (data.has("version") and data.has("wave") and data.has("chest_ready") and data.has("seed")):
		return {}
	if typeof(data.version) != TYPE_INT and typeof(data.version) != TYPE_FLOAT:
		return {}
	if int(data.version) != VERSION:
		return {}
	if typeof(data.wave) != TYPE_INT and typeof(data.wave) != TYPE_FLOAT:
		return {}
	var wave := int(data.wave)
	if wave < 1 or wave > WAVE_COUNT:
		return {}
	if typeof(data.chest_ready) != TYPE_BOOL:
		return {}
	if typeof(data.seed) != TYPE_INT and typeof(data.seed) != TYPE_FLOAT:
		return {}
	return {
		"version": VERSION,
		"wave": wave,
		"chest_ready": bool(data.chest_ready),
		"seed": int(data.seed),
	}


static func save_run(wave: int, chest_ready: bool, seed_value: int, path: String = SAVE_PATH) -> void:
	var payload := {
		"version": VERSION,
		"wave": clampi(wave, 1, WAVE_COUNT),
		"chest_ready": chest_ready,
		"seed": seed_value,
	}
	var text := JSON.stringify(payload)
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.flush()
		file.close()
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		if DirAccess.rename_absolute(temp, path) == OK:
			return
	# Rename is not always possible across filesystems/handles; fall back to a
	# direct write so the checkpoint still lands.
	if FileAccess.file_exists(temp):
		DirAccess.remove_absolute(temp)
	var direct := FileAccess.open(path, FileAccess.WRITE)
	if direct == null:
		return
	direct.store_string(text)
	direct.flush()
	direct.close()


static func clear_run(path: String = SAVE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var temp := path + ".tmp"
	if FileAccess.file_exists(temp):
		DirAccess.remove_absolute(temp)
