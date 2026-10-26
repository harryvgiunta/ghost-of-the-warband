extends Node
## One-shot intent handed from the hub to the arena scene. Command-line flags
## still win over this request, so scripted hosts and joins keep working.
##
## This autoload stays under /root across scene changes, so it also carries the
## in-session party hand-off: an open-world host can tell every connected peer
## to follow it into the delve without tearing down the ENet peer.

## Emitted on a client when the session authority leads the party into another
## scene. The current scene decides how to hand its player over.
signal party_descent(next_port: int)

const DEFAULT_PORT := 7777

var mode := ""
var address := "127.0.0.1"
var port := DEFAULT_PORT
var player_name := "Ranger"

func arm_arena(next_mode: String, next_address: String, next_port: int, next_name: String) -> void:
	mode = next_mode
	address = next_address
	port = clampi(next_port, 1024, 65535)
	player_name = next_name.strip_edges()
	if player_name.is_empty():
		player_name = "Ranger"

func arm_delve(next_mode: String, next_address: String, next_port: int, next_name: String) -> void:
	arm_arena(next_mode,next_address,next_port,next_name)

func arm_world(next_mode: String, next_address: String, next_port: int, next_name: String) -> void:
	arm_arena(next_mode,next_address,next_port,next_name)

func has_request() -> bool:
	return mode != ""

func take() -> Dictionary:
	var request := {"mode":mode, "address":address, "port":port, "name":player_name}
	clear()
	return request

func clear() -> void:
	mode = ""

## The open-world host broadcasts this before it leaves the frontier. The RPC
## lives on this autoload because /root/Session exists in every scene; a Main
## or Delve node path would be gone by the time the packet is serviced.
@rpc("authority","call_remote","reliable")
func descend_party(next_port: int) -> void:
	party_descent.emit(clampi(next_port,1024,65535))
