extends Node
## Autoload `GameFlow`: the door between the warband's scenes.
##
## The campaign is one world: the camp, the trail and the town all stand in one
## scene, and walking is the only way between them. This node is the only thing
## that changes scene - the title's doors open the world, a checkpoint reload
## reopens it, and a guest whose session ended goes back to the title - so a test
## can drive a whole scene without being teleported out of it.
##
## `active` stays false until the flow is entered from the title menu, which is
## what keeps a regression harness's world from reloading a checkpoint under it.
##
## The title's four doors land here: NEW CAMPAIGN (`start_campaign`), RESUME
## CAMPAIGN (`enter_warband`), HOST GAME (`host_campaign`, a new game or the saved
## checkpoint) and JOIN GAME (`join_campaign`).

## The campaign is one world: the camp, the trail through the wood and the town
## all stand in this one scene, and walking is the only way between them.
const WORLD_SCENE := "res://scenes/warband_world.tscn"
## Where a guest goes when its session ends under it: the host left, or never
## answered.
const TITLE_SCENE := "res://title.tscn"

## HOST GAME's two doors: a fresh campaign in the cages, or the saved warband on
## its last checkpoint.
const HOST_NEW := "new"
const HOST_CHECKPOINT := "checkpoint"
## How long JOIN GAME waits on the title for the host's campaign. ENet gives up on
## an unreachable address by itself; this catches a host that is there but never
## sends a warband.
const JOIN_TIMEOUT_SECONDS := 20.0

const WarbandSessionScript := preload("res://scripts/warband/warband_session.gd")
const WarbandBannerScript := preload("res://scripts/warband/warband_banner.gd")
const WarbandContracts := preload("res://scripts/warband/warband_contracts.gd")
## Where the warband's socket lives. The flow is the one node that survives a
## hand-off, so it owns the session: a session created by the title screen would
## be freed with the title screen, and every peer would drop at the exact moment
## the world loaded. The node path is the RPC address, which is why it sits under
## an autoload - `/root/GameFlow/WarbandLink` is the same on every peer whatever
## scene each of them happens to be in.
const WARBAND_LINK := "WarbandLink"
const WARBAND_BANNER := "WarbandBanner"

## A line for the title: why a join came to nothing, why a session ended.
signal notice_posted(text: String)

var active := false
var last_scene := ""
## Where the world puts the warband down when it opens: `"camp"` for a fresh run
## (the cages), `"town"` for a resumed save without a bookmark, `"checkpoint"`
## for the autosave's bookmark, and `"guest"` for a co-op guest fielding the
## host's bodies. The world reads it once, in its own `_ready`.
var world_start := "camp"
var transitions := 0
## The co-op request in force: `{mode, address, port, name, scene}`. It stays here
## (not in the menu) so the flow - the only thing that outlives the menu - can
## honour it once the scene that fields the bodies exists.
var warband_intent: Dictionary = {}
## The live `WarbandSession`, or null outside co-op.
var session = null
## The persistent strip that names the role and repeats a refusal verbatim.
var banner = null
## What a guest's world needs from the host's campaign to stand the same bodies
## in the same wood: `{bodies, focus, layout}` from `WarbandSession.campaign_payload`.
## Empty until the host has answered.
var guest_field: Dictionary = {}
var _warband_scene := ""
var _notice := ""
var _join_clock := 0.0
## True while this node is closing its own session, so the session's goodbye is
## not mistaken for the host leaving.
var _closing := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

## JOIN GAME waits on the title until the host's campaign arrives.
func _process(delta: float) -> void:
	if str(warband_intent.get("mode", "")) != "join" or not guest_field.is_empty():
		set_process(false)
		return
	_join_clock += delta
	if _join_clock >= JOIN_TIMEOUT_SECONDS:
		_guest_over("The host at %s:%d never sent its warband." % [
			str(warband_intent.get("address", "")), int(warband_intent.get("port", 0))])

## RESUME CAMPAIGN: the saved warband where its last checkpoint stands, or the
## cages when there is nothing saved to resume.
func enter_warband() -> void:
	var warband := get_node_or_null("/root/Warband")
	if warband == null:
		return
	_end_warband_link("a campaign of this machine's own")
	active = true
	if warband.load_state() and warband.roster.count() > 0:
		world_start = "checkpoint" if warband.has_checkpoint() else "town"
		goto(WORLD_SCENE)
		return
	warband.reset_state()
	warband.save_state()
	world_start = "camp"
	goto(WORLD_SCENE)

## NEW CAMPAIGN: the five cages, whatever the save says.
func start_campaign() -> void:
	var warband := get_node_or_null("/root/Warband")
	_end_warband_link("a new campaign")
	active = true
	_fresh_campaign(warband)
	goto(WORLD_SCENE)

## A fresh warband and a fresh purse, written at once. The purse is the shared
## wallet, so a fresh campaign has to reset the journey too: otherwise the last
## run's gold and pack walk into the cages with the soul.
func _fresh_campaign(warband) -> void:
	var state := get_node_or_null("/root/PlayerState")
	if state != null:
		state.reset(true)
	if warband != null:
		warband.reset_state()
		warband.save_state()
	world_start = "camp"

## Put the warband back on the ground its last checkpoint remembers, without
## changing scene. The save is the snapshot: reloading it restores the roster,
## gear and essence as they stood at the bookmark, then any body that was down
## is woken (a checkpoint is where a squad gets its feet back - a body that had
## already bled out stays dead, and is the only loss a reload does not undo).
## The purse is deliberately untouched: `PlayerState` owns it and a reload must
## never replay a payment.
func restore_checkpoint() -> bool:
	var warband := get_node_or_null("/root/Warband")
	if warband == null or not warband.has_checkpoint():
		return false
	if not warband.load_state():
		return false
	if not warband.has_checkpoint():
		# The file on disk was older than the marker this process held.
		return false
	if warband.checkpoint_standing() <= 0:
		return false
	_wake_the_warband(warband)
	world_start = "checkpoint"
	return true

## The wipe's door: restore the bookmark and open the world on it.
func retry_checkpoint() -> bool:
	if not restore_checkpoint():
		return false
	goto(WORLD_SCENE)
	return true

## Every body the bookmark held that was merely down gets up at half health; the
## dead stay in the dirt. Whatever a body was wearing is already on the record.
func _wake_the_warband(warband) -> void:
	for merc_id in warband.roster.ids():
		if warband.roster.state_of(int(merc_id)) != WarbandContracts.HealthState.DOWNED:
			continue
		var pool: float = warband.roster.max_health_of(int(merc_id))
		warband.roster.set_health(int(merc_id), maxf(warband.roster.health_of(int(merc_id)), pool * 0.5))
		warband.roster.set_state(int(merc_id), WarbandContracts.HealthState.ALIVE)

## Seat the co-op session on a scene's bodies. Scenes call this from their own
## `_ready`: a scene binding is the moment its bodies exist, which is the earliest
## a session may be attached to them - and the latest, because the first snapshot
## must describe bodies the wire has seen.
func bind(scene: Node) -> void:
	if scene == null:
		return
	_seat_warband_link(scene)

func goto(path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("GameFlow: %s is not a scene" % path)
		return
	var warband := get_node_or_null("/root/Warband")
	if warband != null:
		# Bodies do not survive a scene change, so the soul registry must not
		# either: every next scene re-enters the body its peer already had.
		warband.save_state()
		warband.clear_possession()
	# A session lives and dies with the scene that fields its bodies: leaving that
	# scene ends it (a host's departure closes the socket, and every guest hears
	# it), so nobody keeps a controller that no longer exists. Opening the same
	# world again - a checkpoint reload, the menu's LOAD, a guest following its
	# host - keeps the socket and lets go of the bodies that are about to go.
	if session != null and not _warband_scene.is_empty():
		if path != _warband_scene:
			_end_warband_link("left the field")
		else:
			session.detach_scene()
	last_scene = path
	transitions += 1
	var tree := get_tree()
	if tree == null:
		return
	# A tutorial card may be holding the tree still; the next scene must not
	# open paused behind it.
	tree.paused = false
	tree.call_deferred("change_scene_to_file", path)

## The last line `notice_posted` carried, handed over once: the title shows it
## when it opens after a session ended under the player.
func take_notice() -> String:
	var text := _notice
	_notice = ""
	return text

func _post_notice(text: String) -> void:
	_notice = text
	notice_posted.emit(text)

# --- campaign co-op -----------------------------------------------------------
#
# One host, one warband. HOST GAME opens the world on this machine and the socket
# with it; JOIN GAME connects first, is sent the host's whole warband, and only
# then opens the world on it - the guest plays from the host's roster, stash and
# purse, and its own save is never read or written while the session lasts.

## HOST GAME. `start` is `HOST_NEW` (a fresh campaign in the cages) or
## `HOST_CHECKPOINT` (the saved warband on its bookmark, or the town end when it
## has none). A checkpoint door with nothing saved behind it opens a fresh run.
func host_campaign(port: int, player_name: String, start: String = HOST_NEW) -> void:
	var warband := get_node_or_null("/root/Warband")
	if warband == null:
		return
	_end_warband_link("another campaign was hosted")
	if start == HOST_CHECKPOINT and warband.load_state() and warband.roster.count() > 0:
		world_start = "checkpoint" if warband.has_checkpoint() else "town"
	else:
		_fresh_campaign(warband)
	_request_warband({"mode": "host", "address": "127.0.0.1", "port": port,
		"name": player_name, "scene": WORLD_SCENE})
	goto(WORLD_SCENE)

## JOIN GAME. The socket opens here, on the title; the host answers with its
## campaign (`_on_campaign_received`), and only then does the world open.
func join_campaign(address: String, port: int, player_name: String) -> void:
	_end_warband_link("another campaign was joined")
	_request_warband({"mode": "join", "address": address, "port": port,
		"name": player_name, "scene": WORLD_SCENE})
	if not session.join(address, port, player_name):
		_guest_over("Could not reach %s:%d." % [address, port])
		return
	_join_clock = 0.0
	set_process(true)
	print("WARBAND_FLOW join address=%s port=%d name=%s" % [address, port, player_name])
	_paint_warband_banner()

## Leave the session from this peer. A guest's departure hands its body back to
## the host's field; a host's closes the socket and every guest hears `The host
## left.`
func leave_warband() -> void:
	_end_warband_link("left the battle")

## "offline", "host" or "client".
func warband_role() -> String:
	return str(session.role()) if session != null else "offline"

func _request_warband(intent: Dictionary) -> void:
	warband_intent = intent.duplicate()
	guest_field = {}
	active = true
	_attach_warband_link()

## Create the session and its strip. Both hang under the flow, so both outlive
## every scene.
func _attach_warband_link() -> void:
	if session == null:
		session = WarbandSessionScript.new()
		session.name = WARBAND_LINK
		session.shared_warband = true
		add_child(session)
		session.role_changed.connect(_on_warband_role_changed)
		session.peer_joined.connect(_on_warband_peer_changed)
		session.peer_left.connect(_on_warband_peer_changed)
		session.ownership_changed.connect(_on_warband_ownership_changed)
		session.transfer_refused.connect(_on_warband_refusal)
		session.campaign_received.connect(_on_campaign_received)
		session.session_ended.connect(_on_session_ended)
	if banner == null:
		banner = WarbandBannerScript.new()
		banner.name = WARBAND_BANNER
		add_child(banner)
	_paint_warband_banner()

## The host's campaign reached this guest: lend its warband and open the world
## on it. It arrives again when the host's world opens anew, and the guest's
## world follows it there.
func _on_campaign_received(payload: Dictionary) -> void:
	var warband := get_node_or_null("/root/Warband")
	if warband == null or str(warband_intent.get("mode", "")) != "join":
		return
	var parsed: Variant = JSON.parse_string(str(payload.get("warband", "")))
	if not parsed is Dictionary:
		_guest_over("The host's warband could not be read.")
		return
	set_process(false)
	warband.lend(parsed, int(payload.get("gold", 0)))
	guest_field = {
		"bodies": payload.get("bodies", []),
		"focus": payload.get("focus", []),
		"layout": payload.get("layout", {}),
	}
	world_start = "guest"
	print("WARBAND_FLOW campaign roster=%d bodies=%d" % [warband.roster.count(),
		(guest_field["bodies"] as Array).size() if guest_field["bodies"] is Array else 0])
	goto(WORLD_SCENE)

## The world that fields the bodies has arrived. Attach the session to its
## controller - the bodies are already on the field, so this is the first moment
## a snapshot could be honest - and then open the socket, or tell the host this
## guest is ready to be put into a body.
func _seat_warband_link(scene: Node) -> void:
	if session == null or warband_intent.is_empty():
		return
	if str(scene.scene_file_path) != str(warband_intent.get("scene", "")):
		return
	var warband := get_node_or_null("/root/Warband")
	var controller = scene.get("controller")
	if warband == null or controller == null:
		return
	_warband_scene = str(warband_intent.get("scene", ""))
	session.setup(controller, warband)
	# The world is more than its bodies: the same session carries its mobs, the
	# loot on its ground and its missiles.
	session.attach_world(scene as Node3D)
	if str(warband_intent.get("mode", "")) == "join":
		if session.role() != "client":
			_guest_over("The host left.")
			return
		session.report_fielded()
		_paint_warband_banner()
		return
	if session.role() == "offline":
		var port := int(warband_intent.get("port", 0))
		var player_name := str(warband_intent.get("name", "Soul"))
		if not session.host(port, player_name):
			_fail_warband("Could not open UDP %d on this machine." % port)
			return
		print("WARBAND_FLOW host port=%d name=%s" % [port, player_name])
	else:
		# The host's world opened again under the same socket (a checkpoint
		# reload, the menu's LOAD): every guest rebuilds its own on it.
		session.broadcast_campaign()
	_paint_warband_banner()

func _paint_warband_banner(note: String = "") -> void:
	if banner == null:
		return
	if not note.is_empty():
		banner.show_state(note, true)
		return
	var role := warband_role()
	var port := int(warband_intent.get("port", 0))
	var souls: int = session.peer_count() if session != null else 0
	var text := ""
	if role == "host":
		text = "WARBAND  ·  HOSTING UDP %d  ·  %d soul%s" % [port, souls, "" if souls == 1 else "s"]
	elif role == "client" and souls >= 2:
		var address := str(warband_intent.get("address", ""))
		text = "WARBAND  ·  %s:%d  ·  %d soul%s" % [address, port, souls,
			"" if souls == 1 else "s"]
	elif str(warband_intent.get("mode", "")) == "join":
		text = "WARBAND  ·  joining %s:%d..." % [str(warband_intent.get("address", "")), port]
	elif not warband_intent.is_empty():
		text = "WARBAND  ·  opening the %s door..." % str(warband_intent.get("mode", ""))
	banner.show_state(text)

## The host could not open its socket: it plays on alone, and the strip says why.
func _fail_warband(message: String) -> void:
	print("WARBAND_FLOW failed: %s" % message)
	warband_intent.clear()
	_warband_scene = ""
	if banner != null:
		banner.show_state(message, true)

func _on_warband_role_changed(_role: String) -> void:
	_paint_warband_banner()

func _on_warband_peer_changed(_peer_id: int) -> void:
	_paint_warband_banner()

func _on_warband_ownership_changed(_assignments: Dictionary) -> void:
	_paint_warband_banner()

## A refusal in the router's words, always shown on the strip.
func _on_warband_refusal(_merc_id: int, reason: String) -> void:
	if banner != null and not reason.is_empty():
		banner.note_refusal(reason)

## The socket closed under this peer (the host left, the address never answered).
func _on_session_ended(reason: String) -> void:
	if _closing:
		return
	if str(warband_intent.get("mode", "")) == "join":
		_guest_over(reason)

## A guest's session is over: its own campaign comes back and, when the host's
## world was already up around it, the title opens with the reason on it.
func _guest_over(reason: String) -> void:
	var in_world := not _warband_scene.is_empty()
	print("WARBAND_FLOW guest over (%s)" % reason)
	_post_notice(reason)
	_end_warband_link(reason)
	if in_world:
		goto(TITLE_SCENE)

## Drop the socket and the strip, and give a guest its own warband back. The
## controller reference goes first: the scene that owns those bodies is on its
## way out, and a session left holding it would step a corpse between the free
## and the next scene's ready.
func _end_warband_link(reason: String) -> void:
	_closing = true
	if session != null:
		print("WARBAND_FLOW closed (%s)" % reason)
		session.controller = null
		session.leave()
		session.queue_free()
		session = null
	_closing = false
	if banner != null:
		banner.queue_free()
		banner = null
	_warband_scene = ""
	warband_intent.clear()
	guest_field = {}
	set_process(false)
	var warband := get_node_or_null("/root/Warband")
	if warband != null and bool(warband.get("lent")):
		warband.end_loan()
