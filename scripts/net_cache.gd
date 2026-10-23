extends Node
## Remembers the last host address, player name and UDP port for both the
## Hollow forms and the standalone arena lobby. This is presentation data only;
## Session remains the one-shot host/join hand-off.

const SAVE_PATH := "user://net_cache.json"
const TEST_SAVE_PATH := "user://net_cache_test.json"

var player_name := "Ranger"
var address := "127.0.0.1"
var port := 7777
var save_path := SAVE_PATH

func _ready() -> void:
	if DisplayServer.get_name() == "headless" and OS.get_cmdline_args().has("--script"):
		save_path = TEST_SAVE_PATH
	load_cache()

func load_cache() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	var saved_name := _clean_name(str(data.get("player_name","")))
	if not saved_name.is_empty():
		player_name = saved_name
	var saved_address := str(data.get("address","")).strip_edges()
	if not saved_address.is_empty():
		address = saved_address
	var saved_port := int(data.get("port",port))
	if saved_port >= 1024 and saved_port <= 65535:
		port = saved_port

func remember(next_name: String, next_address: String, next_port: int) -> void:
	player_name = _clean_name(next_name)
	var clean_address := next_address.strip_edges()
	if not clean_address.is_empty():
		address = clean_address
	if next_port >= 1024 and next_port <= 65535:
		port = next_port
	save_cache()

func save_cache() -> void:
	var file := FileAccess.open(save_path,FileAccess.WRITE)
	if file == null:
		push_warning("Could not write network cache to %s" % save_path)
		return
	file.store_string(JSON.stringify({
		"version":1,
		"player_name":player_name,
		"address":address,
		"port":port,
	}))
	file.close()

func reset(persist: bool = true) -> void:
	player_name = "Ranger"
	address = "127.0.0.1"
	port = 7777
	if persist:
		save_cache()

func _clean_name(value: String) -> String:
	var clean := value.strip_edges().replace("\n"," ").replace("\r"," ").replace("\t"," ").left(16)
	return "Ranger" if clean.is_empty() else clean
