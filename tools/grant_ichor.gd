extends SceneTree
## Puts warden's ichor in this machine's warband save, so the altar can be
## played with instead of rationed.
##
##   Godot --headless --path . --script res://tools/grant_ichor.gd -- --count=1000
##
## The save is read as a plain file rather than through `Warband.load_state()`: a
## load forfeits a party still standing below in the file, and a test grant must
## not cost somebody their delve. Only the one stash count is touched, and every
## other key is written back exactly as it was found.

const REAGENT := "ichor_vial"

func _initialize() -> void:
	var count := 1000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):
			count = maxi(1, int(arg.trim_prefix("--count=")))
	call_deferred("run", count)

func run(count: int) -> void:
	var warband := root.get_node_or_null("Warband")
	if warband == null:
		printerr("GRANT_ICHOR_FAIL no Warband autoload")
		quit(1)
		return
	var path := str(warband.save_path)
	if not FileAccess.file_exists(path):
		printerr("GRANT_ICHOR_FAIL no save at ", path)
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		printerr("GRANT_ICHOR_FAIL not a warband save: ", path)
		quit(1)
		return
	var data: Dictionary = parsed
	var stash: Variant = data.get("stash", {})
	if not stash is Dictionary:
		printerr("GRANT_ICHOR_FAIL the save has no stash: ", path)
		quit(1)
		return
	var pooled: Variant = (stash as Dictionary).get("pooled", {})
	if not pooled is Dictionary:
		pooled = {}
		(stash as Dictionary)["pooled"] = pooled
	var before := int((pooled as Dictionary).get(REAGENT, 0))
	(pooled as Dictionary)[REAGENT] = before + count
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("GRANT_ICHOR_FAIL cannot write ", path)
		quit(1)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("GRANT_ICHOR_OK ", REAGENT, " ", before, " -> ", before + count, "  ", path)
	quit()
