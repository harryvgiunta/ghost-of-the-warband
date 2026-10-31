extends Node
## Remembers the last host address, player name and UDP ports for the title's
## JOIN GAME and HOST GAME forms. This is presentation data only; the flow and
## the sessions own the actual hand-offs.
##
## The port a peer *joins* on and the port this machine *hosts* on are separate
## fields. Sharing one made a stale join port silently move the host socket: the
## host thought it was serving UDP 7777 while it was actually serving whatever
## the last join wrote, so a friend on the documented port timed out while a
## second instance on the same PC, reading the same cache file, joined fine.

const SAVE_PATH := "user://net_cache.json"
const TEST_SAVE_PATH := "user://net_cache_test.json"

var player_name := "Ranger"
var address := "127.0.0.1"
var port := 7777
## The port this machine last hosted on. Only a host action writes it.
var host_port := 7777
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
	var saved_host_port := int(data.get("host_port",host_port))
	if saved_host_port >= 1024 and saved_host_port <= 65535:
		host_port = saved_host_port

## Join intent: the name, address and port a guest last used. A host never
## reaches this path, so remembering a join cannot move the host socket.
func remember(next_name: String, next_address: String, next_port: int) -> void:
	player_name = _clean_name(next_name)
	var clean_address := next_address.strip_edges()
	if not clean_address.is_empty():
		address = clean_address
	if next_port >= 1024 and next_port <= 65535:
		port = next_port
	save_cache()

## Host intent: the name to seat and the port to open. The guest-side fields stay
## untouched, so a friend's form keeps offering the last join values.
func remember_host(next_name: String, next_port: int) -> void:
	player_name = _clean_name(next_name)
	if next_port >= 1024 and next_port <= 65535:
		host_port = next_port
	save_cache()

func save_cache() -> void:
	var file := FileAccess.open(save_path,FileAccess.WRITE)
	if file == null:
		push_warning("Could not write network cache to %s" % save_path)
		return
	file.store_string(JSON.stringify({
		"version":2,
		"player_name":player_name,
		"address":address,
		"port":port,
		"host_port":host_port,
	}))
	file.close()

func reset(persist: bool = true) -> void:
	player_name = "Ranger"
	address = "127.0.0.1"
	port = 7777
	host_port = 7777
	if persist:
		save_cache()

func _clean_name(value: String) -> String:
	var clean := value.strip_edges().replace("\n"," ").replace("\r"," ").replace("\t"," ").left(16)
	return "Ranger" if clean.is_empty() else clean
