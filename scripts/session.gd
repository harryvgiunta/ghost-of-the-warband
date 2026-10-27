extends Node
## One-shot intent handed from the hub to the arena scene. Command-line flags
## still win over this request, so scripted hosts and joins keep working.
##
## This autoload stays under /root across scene changes, so it also carries the
## in-session party hand-off: an open-world host can tell every connected peer
## to follow it into the delve without tearing down the ENet peer.

## Emitted on a client when the session authority leads it into another scene.
## The current scene decides how to hand its player over.
signal party_descent(next_port: int)
## Emitted on the authority when a connected rider asks to follow the party down.
signal descent_requested(from_peer: int)
## Emitted on a client when the authority refuses that request.
signal descent_refused(reason: String)
## Emitted on a client when the open world's authority has entered the delve.
## The frontier stops replicating (nothing there is simulated any more) but stays
## walkable, so the player reaches the hatch and descends on its own terms.
signal host_entered_delve(next_port: int)
## Emitted on a client when the party is back in the open world.
signal delve_returned

const DEFAULT_PORT := 7777

var mode := ""
var address := "127.0.0.1"
var port := DEFAULT_PORT
var player_name := "Ranger"
## The port of the delve the party is currently below in, or 0 while the
## authority is in the open world. Survives the scene change with the autoload.
var delve_open_port := 0

func arm_arena(next_mode: String, next_address: String, next_port: int, next_name: String) -> void:
	mode = next_mode
	address = next_address
	port = clampi(next_port, 1024, 65535)
	player_name = next_name.strip_edges()
	if player_name.is_empty():
		player_name = "Ranger"
	_note("session_armed", {"mode": mode, "address": address, "port": port, "name": player_name})

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
	if not mode.is_empty():
		_note("session_cleared", {"mode": mode, "port": port})
	mode = ""

## The authority sends this to one peer when it leads it into the delve. The RPC
## lives on this autoload because /root/Session exists in every scene; a Main or
## Delve node path would be gone by the time the packet is serviced.
@rpc("authority","call_remote","reliable")
func descend_party(next_port: int) -> void:
	_note("party_descent", {"port": next_port})
	party_descent.emit(clampi(next_port,1024,65535))


## A rider asks the authority for passage down instead of tearing the party
## apart. Answered per peer by `descend_party` or `refuse_descent`.
@rpc("any_peer","call_remote","reliable")
func request_descent() -> void:
	var sender := multiplayer.get_remote_sender_id() if multiplayer != null else 0
	if sender > 0:
		_note("descent_requested", {"peer": sender})
		descent_requested.emit(sender)


@rpc("authority","call_remote","reliable")
func refuse_descent(reason: String) -> void:
	_note("descent_refused", {"reason": reason.strip_edges().left(120)})
	descent_refused.emit(reason.strip_edges().left(120))


## The open world's authority has gone below. Clients keep the connection and
## the town, but the frontier stops being simulated until the party returns.
@rpc("authority","call_remote","reliable")
func delve_open(next_port: int) -> void:
	delve_open_port = clampi(next_port,1024,65535)
	_note("delve_open", {"port": delve_open_port})
	host_entered_delve.emit(delve_open_port)


func clear_delve_open() -> void:
	if delve_open_port != 0:
		_note("delve_open_cleared", {"port": delve_open_port})
	delve_open_port = 0


## The party took the rope: every peer is back in the open world and the
## frontier's own simulation resumes, so the town is live again.
@rpc("authority","call_remote","reliable")
func close_delve() -> void:
	delve_open_port = 0
	_note("delve_closed")
	delve_returned.emit()


## The logger lives on /root and is always loaded in this project; the lookup is
## still optional so a script-only harness that skips autoloads cannot break a
## scene hand-off.
func _note(message: String, data: Dictionary = {}) -> void:
	var log := get_node_or_null("/root/Log")
	if log != null:
		log.event("net", message, data)
