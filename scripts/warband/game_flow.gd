extends Node
## Autoload `GameFlow`: the door between the warband's scenes.
##
## The campaign is a chain of scenes that each know one next place: the cages
## hand the squad to the town, the town's gate launches an expedition, the arena
## hands the survivors back. No scene loads another directly - each emits
## `scene_requested(path)` and this node is the only thing that changes scene, so
## a test can drive a whole scene without being teleported out of it.
##
## `active` stays false until the flow is entered from the title menu or the
## campaign button, which is what keeps every scene regression able to emit its
## door signal without the tree moving underneath it.

## The campaign is one world: the camp, the trail through the wood and the town
## all stand in this one scene, and walking is the only way between them.
const WORLD_SCENE := "res://scenes/warband_world.tscn"
const ARENA_SCENE := "res://admin_arena.tscn"
## The arena was written against the old town scene's path and still asks for it.
## There is no separate town scene in the campaign any more, so that path means
## "the world, at the town end" - the arena hands the survivors back into the
## square they marched out of.
const ARENA_RETURN := "res://scenes/town_hub.tscn"

const WarbandSessionScript := preload("res://scripts/warband/warband_session.gd")
const WarbandLobbyScript := preload("res://scripts/warband/warband_lobby.gd")
## Where the warband's socket lives. The flow is the one node that survives a
## hand-off, so it owns the session: a session created by the title screen would
## be freed with the title screen, and every peer would drop at the exact moment
## the arena loaded. The node path is the RPC address, which is why it sits under
## an autoload - `/root/GameFlow/WarbandLink` is the same on every peer whatever
## scene each of them happens to be in.
const WARBAND_LINK := "WarbandLink"
const WARBAND_BANNER := "WarbandBanner"

signal warband_intent_changed(intent: Dictionary)

var active := false
var last_scene := ""
## Where the world puts the warband down when it opens: `"camp"` for a fresh run
## (the cages), `"town"` for a resumed save or the field's return. The world reads
## it once, in its own `_ready`.
var world_start := "camp"
var transitions := 0
## The lobby's last request: `{mode, address, port, name, scene}`. It stays here
## (not in the menu) so the flow - the only thing that outlives the menu - can
## honour it once the scene that fields the bodies exists.
var warband_intent: Dictionary = {}
## The live `WarbandSession`, or null between battles.
var session = null
## The persistent strip that names the role and repeats a refusal verbatim.
var banner = null
var _warband_scene := ""
var _seat_tries := 0
## Bodies a refusal already took off the table, so a retry cannot ask twice.
var _refused_bodies: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## The title menu's one door: resume a saved warband in town, or start the cages.
func enter_warband() -> void:
	var warband := get_node_or_null("/root/Warband")
	if warband == null:
		return
	active = true
	if warband.load_state() and warband.roster.count() > 0:
		world_start = "town"
		goto(WORLD_SCENE)
		return
	warband.reset_state()
	warband.save_state()
	world_start = "camp"
	goto(WORLD_SCENE)

## A brand-new campaign: the four cages, whatever the save says.
func start_campaign() -> void:
	active = true
	# The purse is the shared wallet, so a fresh campaign has to reset the journey
	# too: otherwise the last run's gold and pack walk into the cages with the soul.
	var state := get_node_or_null("/root/PlayerState")
	if state != null:
		state.reset(true)
	var warband := get_node_or_null("/root/Warband")
	if warband != null:
		warband.reset_state()
		warband.save_state()
	world_start = "camp"
	goto(WORLD_SCENE)

## Go straight to the town end of the world (debug door, and where a resumed
## campaign lands).
func enter_town() -> void:
	active = true
	world_start = "town"
	goto(WORLD_SCENE)

func launch_expedition() -> void:
	active = true
	goto(ARENA_SCENE)

## Connect a scene's door to this node. Scenes call this from their own `_ready`;
## connecting is harmless while `active` is false.
func bind(scene: Node) -> void:
	if scene == null or not scene.has_signal("scene_requested"):
		return
	var callable := Callable(self, "_on_scene_requested")
	if not scene.is_connected("scene_requested", callable):
		scene.scene_requested.connect(callable)
	# A scene binding is the moment its bodies exist, which is the earliest a
	# session may be attached to them - and the latest, because the first
	# snapshot must describe bodies the wire has seen.
	_seat_warband_link(scene)

func _on_scene_requested(path: String) -> void:
	if not active:
		return
	# A door that asks for the world is not the campaign's opening: the opening is
	# the title's own call, which says where to put the warband down. Everything
	# that arrives through a scene door - the field's return above all - comes back
	# into the world at the town end, where the square and the gate are.
	if path == ARENA_RETURN or path == WORLD_SCENE:
		world_start = "town"
		goto(WORLD_SCENE)
		return
	goto(path)

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
	# A battle lives and dies with the scene that fields its bodies: leaving that
	# scene ends the session (a host's departure closes the socket, and every
	# guest hears it), so nobody keeps a controller that no longer exists.
	if session != null and not _warband_scene.is_empty() and path != _warband_scene:
		_end_warband_link("left the field")
	last_scene = path
	transitions += 1
	var tree := get_tree()
	if tree == null:
		return
	# A tutorial card may be holding the tree still; the next scene must not
	# open paused behind it.
	tree.paused = false
	tree.call_deferred("change_scene_to_file", path)

# --- the warband battle ----------------------------------------------------
#
# The title screen's lobby is only a form. It stores an intent here and the flow
# seats a `WarbandSession` on the scene that next fields the warband's bodies, so
# the ENet peer outlives the menu. Everything below is additive: no existing
# door changed shape, and `goto` still clears `paused` for the hand-off.

## Open a battle on this machine and carry the intent into the scene that fields
## the warband's bodies.
func host_warband(port: int, host_name: String) -> void:
	_request_warband({"mode": "host", "address": "127.0.0.1", "port": port,
		"name": host_name, "scene": ARENA_SCENE})

## Join a friend's battle: the same scene, the same mode, and the first body no
## soul is already inside.
func join_warband(address: String, port: int, guest_name: String) -> void:
	_request_warband({"mode": "join", "address": address, "port": port,
		"name": guest_name, "scene": ARENA_SCENE})

## Leave the battle from this peer. A guest's departure hands its body back to
## the scene; a host's closes the socket and every guest hears `The host left.`
func leave_warband() -> void:
	_end_warband_link("left the battle")

## Ask to enter one body through the same channel the lobby strip watches. The
## host decides at once; a guest asks and the refusal - naming the router's own
## reason - comes back to its banner.
func warband_enter_body(merc_id: int) -> Dictionary:
	if session == null:
		return {"ok": false, "message": "No warband battle is open.", "body_id": merc_id,
			"previous_body_id": -1, "reason": SoulRouter.REASON_UNKNOWN, "pending": false}
	return session.request_body(merc_id)

## "offline", "host" or "client".
func warband_role() -> String:
	return str(session.role()) if session != null else "offline"

## The first body no soul is inside, in roster order. On a guest this is a guess
## the host confirms - the map it has is the host's last word, and a body taken
## in between comes back as a refusal instead of a second soul.
func first_free_body() -> int:
	var warband := get_node_or_null("/root/Warband")
	if warband == null:
		return -1
	var taken := {}
	if session != null:
		var map: Dictionary = session.ownership()
		for key in map:
			var owned := int(map[key])
			if owned > 0:
				taken[owned] = true
	for merc_id in warband.roster.ids():
		if taken.has(merc_id) or _refused_bodies.has(merc_id):
			continue
		if not warband.roster.is_alive(merc_id):
			continue
		if not warband.souls.has_body(merc_id):
			continue
		if warband.souls.occupied_by(merc_id) != 0:
			continue
		return merc_id
	return -1

func _request_warband(intent: Dictionary) -> void:
	_end_warband_link("another battle was asked for")
	warband_intent = intent.duplicate()
	_seat_tries = 0
	_refused_bodies = {}
	active = true
	warband_intent_changed.emit(warband_intent.duplicate())
	# The hand-off first (it ends any older session but this fresh one does not
	# exist yet), then the socket: `bind` runs after the scene's `_ready`, by
	# which time the link is there waiting for it.
	goto(str(intent.get("scene", ARENA_SCENE)))
	_attach_warband_link()

## Create the session and its strip if this is the first battle. Both hang under
## the flow, so both outlive every scene.
func _attach_warband_link() -> void:
	if session == null:
		session = WarbandSessionScript.new()
		session.name = WARBAND_LINK
		add_child(session)
		session.role_changed.connect(_on_warband_role_changed)
		session.peer_joined.connect(_on_warband_peer_changed)
		session.peer_left.connect(_on_warband_peer_changed)
		session.ownership_changed.connect(_on_warband_ownership_changed)
		session.transfer_refused.connect(_on_warband_refusal)
	if banner == null:
		banner = WarbandLobbyScript.Banner.new()
		banner.name = WARBAND_BANNER
		add_child(banner)
	_paint_warband_banner("Warband battle: waiting for the field.")

## The scene that fields the bodies has arrived. Attach the session to its
## controller - the bodies are already on the field, so this is the first moment
## a snapshot could be honest - and then open the socket or re-enter a body.
func _seat_warband_link(scene: Node) -> void:
	if session == null or warband_intent.is_empty():
		return
	var wanted := str(warband_intent.get("scene", ""))
	if wanted.is_empty() or str(scene.scene_file_path) != wanted:
		return
	var warband := get_node_or_null("/root/Warband")
	if warband == null:
		return
	var controller = scene.get("controller")
	if controller == null:
		return
	_warband_scene = wanted
	session.setup(controller, warband)
	var mode := str(warband_intent.get("mode", "host"))
	# A guest is a replica *before* the first body is dressed: `_dress` reads the
	# body's own authority to decide whether it predicts or waits, and the arena
	# spawned every body as the simulated side.
	if session.role() == "client" or (session.role() == "offline" and mode == "join"):
		_configure_replica(controller)
	if session.role() == "offline":
		_open_warband_session()
	else:
		_seat_warband_body()

## The scene spawns its bodies authoritative: the arena was written before the
## session existed and always asks for the simulated side. A guest must not be.
## Its own body has to integrate from its own keys and send intents to the host,
## while every other body follows the host's snapshots - the exact declaration
## `spawn_mercenaries(points, false)` makes, applied to bodies that are already
## on the field. `_authoritative` is private by convention, the same way
## `WarbandSession` already reaches into `PossessionController._release_peer`.
func _configure_replica(controller) -> void:
	controller._authoritative = false
	for body in controller.bodies():
		if not is_instance_valid(body):
			continue
		body.authoritative = false
		body.combat.damage_enabled = false

func _open_warband_session() -> void:
	if session == null:
		return
	var mode := str(warband_intent.get("mode", "host"))
	var port := int(warband_intent.get("port", 0))
	var player_name := str(warband_intent.get("name", "Soul"))
	if mode == "host":
		if not session.host(port, player_name):
			_fail_warband("Could not open UDP %d on this machine." % port)
			return
		print("WARBAND_FLOW host port=%d name=%s" % [port, player_name])
	else:
		var address := str(warband_intent.get("address", "127.0.0.1"))
		if not session.join(address, port, player_name):
			_fail_warband("Could not reach %s:%d." % [address, port])
			return
		print("WARBAND_FLOW join address=%s port=%d name=%s" % [address, port, player_name])
	_seat_warband_body()

## Put this peer's soul into a body. The host is normally seated by the scene
## itself (it is ENet peer 1); a guest waits for the host's map, which says who
## is already inside what, and then asks for the first free body.
func _seat_warband_body() -> void:
	if session == null or session.controller == null:
		return
	var warband := get_node_or_null("/root/Warband")
	if warband == null:
		return
	var me := int(session.controller.local_peer_id)
	if warband.souls.body_of(me) > 0 or int(session.ownership().get(me, 0)) > 0:
		_paint_warband_banner()
		return
	if session.role() == "client" and session.peer_count() < 2:
		# Not connected yet: the map has not arrived and the host cannot be asked.
		_paint_warband_banner()
		return
	var free_body := first_free_body()
	if free_body <= 0:
		_paint_warband_banner("The field has no free body left.")
		return
	_seat_tries += 1
	var result: Dictionary = session.request_body(free_body)
	print("WARBAND_FLOW seat merc=%d pending=%s" % [free_body, result.get("pending", false)])
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
	elif role == "client":
		var address := str(warband_intent.get("address", ""))
		text = "WARBAND  ·  %s:%d  ·  %d soul%s" % [address, port, souls,
			"" if souls == 1 else "s"]
	elif not warband_intent.is_empty():
		text = "WARBAND  ·  opening the %s door..." % str(warband_intent.get("mode", ""))
	banner.show_state(text)

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
	_seat_warband_body()

## A refusal in the router's words. It is always shown; a body taken between the
## guess and the ask is not an error, so a guest tries the next one (three times,
## never the same body twice) and the reason stays on the strip meanwhile.
func _on_warband_refusal(merc_id: int, reason: String) -> void:
	if banner != null and not reason.is_empty():
		banner.note_refusal(reason)
	if reason != SoulRouter.REASON_OCCUPIED:
		return
	_refused_bodies[merc_id] = true
	if warband_role() != "client" or _seat_tries >= 3:
		return
	_seat_warband_body()

## Drop the socket and the strip. The controller reference goes first: the scene
## that owns those bodies is on its way out, and a session left holding it would
## step a corpse between the free and the next scene's ready.
func _end_warband_link(reason: String) -> void:
	if session != null:
		print("WARBAND_FLOW closed (%s)" % reason)
		session.controller = null
		session.leave()
		session.queue_free()
		session = null
	if banner != null:
		banner.queue_free()
		banner = null
	_warband_scene = ""
	warband_intent.clear()
	_seat_tries = 0
	_refused_bodies = {}
