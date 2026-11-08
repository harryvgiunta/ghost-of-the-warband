class_name WarbandSession
extends Node
## The socket of a warband battle: one ENet peer, the host as the authority, and
## the bodies of `PossessionController` as the replicated state.
##
## The controller stays the scene's clock and `SoulRouter` stays the rule book;
## this node owns only what crosses the wire:
##
##   * **transfers** - a guest asks to enter a body (`request_body`), the host
##     validates it through the router and answers either with a refusal that
##     names the reason or with the resulting `{peer: merc_id}` map, so no two
##     souls can end up inside one body and every peer agrees on the field;
##   * **snapshots** - the host writes every body at 20 Hz, keyed by *merc id*
##     (never the arena slot, which is a spawn-order artifact), packed through
##     `NetLimits` so a snapshot never needs ENet fragmentation;
##   * **intents** - movement, aim and combat verbs ride `PossessionSync`, which
##     the controller already drives from its own frame. The host resolves every
##     hit; a guest only ever predicts its own locomotion, and the host steps a
##     guest's body only on frames it actually received (never on frames it
##     invented to fill a gap);
##   * **the world** - when a `WarbandWorld` is attached, the host also owns its
##     mobs (15 Hz, 70 m around any body), the loot that hits its ground and the
##     missiles in flight. A guest's mobs are `replica`s and never run AI, its
##     arrows are visuals with an empty hit mask, and only the host resolves a
##     kill. All of it rides this one peer;
##   * **the shared warband** - in campaign co-op (`shared_warband`) the host's
##     warband is the one pool every soul plays from. A guest that announces
##     itself is sent the whole campaign (`receive_campaign`), lends it
##     (`WarbandState.lend`) and never writes it; every change on the host goes
##     out again (`receive_warband`), so the roster, the stash and the purse a
##     guest sees are the host's. A guest whose world is up says so
##     (`field_ready`) and the host seats it in the first free body; a soul with
##     no free body waits - the one already inside the last body keeps it - and
##     takes the next body that comes free, in the order the souls lost theirs.
##
## The scene spawns the bodies before `setup`; the session replicates them and
## never ticks `physics_step`, never reads `Input`, and never decides who is
## inside what - it asks `SoulRouter` and obeys. Both peers must mount it at the
## same node path, because that path is the RPC address.

const NetLimits = preload("res://scripts/net_limits.gd")
const NetReplication = preload("res://scripts/net_replication.gd")
const WarbandState = preload("res://scripts/warband/warband_state.gd")
const ArrowScript = preload("res://scripts/arrow.gd")
const Perf = preload("res://scripts/perf_probe.gd")

## Every stream below is keyed on the **physics tick**, one per frame at 60 Hz,
## and every rate is an exact divisor of that clock: 3 ticks is 20 Hz, 4 is 15,
## 12 is 5, 15 is 4, 30 is 2. Nothing is counted in rendered frames and nothing is
## banked, so a 144 Hz client and a 21 fps host send on the same ticks forever -
## and the tick a packet is labelled with is always the step that produced the
## pose inside it.
const SNAPSHOT_TICKS := 3
## The world's mobs. 15 Hz is enough for a replica that interpolates between two
## poses, and a fourth of the body rate keeps the datagrams from doubling.
const MOB_SEND_TICKS := 4
## A mob only matters to a soul that could reach it: beyond this, the mob is the
## wood's business and the wire stays quiet. It is measured from *that guest's*
## own body, never from whoever happens to be nearest: a soul two hundred metres
## from the rest of the party was being sent the whole of their fight - mobs it
## could not see, drawn, animated and shadowed on its machine, and enough extra
## datagrams to lose the ones it could.
const MOB_REACH_METRES := 70.0
## How far past the reach a body already in a peer's stream stays in it. Without
## a band the mob standing on the boundary flaps in and out of the stream as a
## player walks, and every flap is a body that vanishes from a screen.
const MOB_RELEASE_METRES := 92.0
## How often the mob stream repeats an unchanged body anyway: one second of ticks,
## so a lost delta cannot freeze a mob for good.
const MOB_REFRESH_TICKS := 60
## Loot is a one-shot announcement, so it is polled slowly; a missile's visual
## start must look immediate, so it is polled every third tick.
const LOOT_SEND_TICKS := 12
const MISSILE_SEND_TICKS := 3
## The number of physics ticks in a second: the clock every stride in this file
## divides. It is the netcode primitive's figure, not a second copy of it.
const TICK_HZ := NetReplication.WIRE_TICK_HZ
## The group every wilderness mob joins; a late spawn must be a replica too.
const WILD_MOB_GROUP := "wild_mobs"
## How many payload keys the client remembers. An announcement is rare, and the
## book is capped so a long campaign cannot grow it forever.
const DELIVERY_BOOK_CAP := 512
## ENet slots. A field is three bodies, so a peer past the third watches rather
## than rides: the slots stay eight because a spectator costs nothing.
const MAX_CLIENTS := 8
## The longest the host lets warband changes pile up before the next copy goes
## out. The first change after a quiet spell leaves on the next tick, so a TAB a
## guest asked for is back on its screen within a round trip.
const MIRROR_TICKS := 15
## How often the host looks for a free body for a soul that has none.
const SEAT_TICKS := 30

## Every stream and the stride it fires on, by name - the cadence contract in one
## place. Each stride divides `TICK_HZ` exactly, or a rate stops being the rate it
## says it is (a 7-tick stride is 8.57 Hz, and the second it lands on slides). The
## unit regression reads this: the cadence is only exact because every figure here
## is a divisor of the clock.
const CADENCE := {
	"snapshot": SNAPSHOT_TICKS,
	"mob": MOB_SEND_TICKS,
	"missile": MISSILE_SEND_TICKS,
	"loot": LOOT_SEND_TICKS,
	"mirror": MIRROR_TICKS,
	"seat": SEAT_TICKS,
}

signal role_changed(role: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
## The host's `{peer: merc_id}` map, as this peer last adopted it.
signal ownership_changed(assignments: Dictionary)
## A transfer this peer asked for was refused; `reason` is the router's words.
signal transfer_refused(merc_id: int, reason: String)
## A gear change this guest asked the host for was refused; nothing moved, and
## `message` is the host's own words ("Aldous is not with the party.").
signal gear_refused(message: String)
## The host's campaign reached this guest: `{warband, gold, bodies, focus,
## layout}`. Sent once when the guest announces itself and again whenever the
## host's world opens anew (a checkpoint reload, the host's LOAD row).
signal campaign_received(payload: Dictionary)
## The socket closed under this peer for a reason it did not choose: the words
## are what a player is told ("The host left.", "Could not join.").
signal session_ended(reason: String)

var controller: PossessionController
var warband: WarbandState

var _role := "offline"
var _player_name := ""
## peer_id -> player name, mirrored from the host with every ownership map.
var _names: Dictionary = {}
## The map this peer last received, so a soul that disappears from it is released.
var _adopted: Dictionary = {}
var _peer: ENetMultiplayerPeer
var _signals_wired := false
## The simulation tick this peer last beat on: one heartbeat per tick, whoever
## calls it, so a scene that also drives the session cannot double-send.
var _beat_tick := -1
## The high-frequency downlink: every pose this host sends, held for the simulated
## link when one was asked for (`NetReplication.requested_link`). Control traffic
## - ownership, the campaign, loot, gear - never comes through here: a delayed
## handshake is a broken handshake, not a slow one.
var _link = NetReplication.LagQueue.new()

## Send one high-frequency stream, through the simulated link when one is
## configured. `peer_id` 0 is the whole party.
##
## `lossy` mirrors the channel the packet really travels on: the pose streams are
## `unreliable` and may be thrown away by a bad link, while a death, a leave or an
## intent is `reliable` and must never be - a harness that dropped those would be
## failing the game, not measuring it.
##
## A link outlives the peer it was carrying: a packet still held when a guest
## leaves must be dropped, not sent into a socket that no longer names it, or a
## session's last second is a page of `unknown peer ID`. The guard is inside the
## deferred call for that reason, and an ordinary link never builds one.
func _stream(send: Callable, peer_id: int = 0, lossy: bool = false) -> void:
	if not _link.active():
		send.call()
		return
	var guarded := func():
		if not _has_peers():
			return
		if peer_id != 0 and not multiplayer.get_peers().has(peer_id):
			return
		send.call()
	_link.defer(guarded, lossy)
## Campaign co-op: one warband, the host's, for every soul on the field (see the
## class notes). Off for the arena bout, where both machines carry one save.
var shared_warband := false
## Host only: guests whose world is up and who can be put into a body.
var _fielded: Dictionary = {}
## Host only: souls on the field with no body, in the order they lost one.
var _waiting: Array[int] = []
## Host only: the body each guest is driving, so the frame-driven flag follows
## the soul whichever way it changed bodies.
var _driven: Dictionary = {}
var _mirror_dirty := false
## The tick the last campaign copy went out on (`MIRROR_TICKS` since then).
var _mirror_tick := -10 ** 9

# --- the world beyond the bodies -------------------------------------------
#
# The campaign is one world: the mobs, the loot on the ground and the missiles
# in flight are the host's alone. The guest is told about them on the same peer,
# never allowed to run a mob's brain, and never trusted with a hit.
## The `WarbandWorld` this session replicates, or null between worlds.
var world: Node3D
## Pickup/projectile instance ids the host has already announced.
var _sent_loot: Dictionary = {}
var _sent_missiles: Dictionary = {}
## Mob names whose final (dead) state was already sent, per peer. A living guard
## is sent every tick; a corpse is sent exactly once to each guest that was
## being told about it, so a replica can fall.
var _dead_sent: Dictionary = {}
## The last state sent for each mob, so a calm body is not re-sent 15 times a
## second. Bounded by the mob count and cleared with the scene, as the one book a
## peer with no entry of its own reads (`changed_mob_entries`).
var _mob_sent: Dictionary = {}
## Host only, per peer: the mob names that peer is being told about right now.
## A body leaving this set is named once so the guest can put its copy down
## without waiting out a timeout.
var _mob_live: Dictionary = {}
## The host's unlocked armory, delivered before this machine's world existed:
## kept here and handed to the director the moment `attach_world` gives it one.
var _roguelite_pool: Array = []
## Host only, per peer: that peer's own copy of `_mob_sent`. A shared book is
## wrong once each guest is told about a different ground - a body near the
## host's body would look "already sent" to the guest that was never sent it.
var _mob_sent_by_peer: Dictionary = {}
## Guard name -> guard for the stream tick being applied. A hall holds three
## hundred bodies, and the state batch names them one at a time.
var _guards_by_name: Dictionary = {}
var _guards_stamp := -1
## The last campaign copy sent, text and purse, so an unchanged one is skipped.
var _mirror_sent := false
var _mirror_text := ""
var _mirror_gold := -1
## Payload keys a client already spawned, so a repeated announcement is a no-op.
var _delivered_loot: Dictionary = {}
var _delivered_arrows: Dictionary = {}
var _world_watch := false

## Bind the session to the soul it carries. The controller's own `PossessionSync`
## is reused as-is: it is the only path that may turn a remote intent into a
## body.
func setup(possession_controller: PossessionController, warband_node: WarbandState) -> void:
	controller = possession_controller
	warband = warband_node
	if controller == null:
		push_error("WarbandSession needs a PossessionController")
		return
	if controller.sync == null:
		controller.sync = PossessionSync.new()
		controller.sync.name = "PossessionSync"
		controller.add_child(controller.sync)
	controller.sync.setup(warband, controller)
	var asked := NetReplication.requested_link()
	_link.configure(asked.x, asked.y, asked.z)
	# A world opened under a socket that already has a guest on it keeps the
	# rewind history from its first frame, not from the next connection.
	controller.lag_tracking = _role == "host" and peer_count() > 1
	# A guest's own keys ask the host; the host's own keys stay local moves.
	controller.transfer_requester = Callable(self, "request_body")
	if not controller.possession_changed.is_connected(_on_controller_possession_changed):
		controller.possession_changed.connect(_on_controller_possession_changed)
	if warband != null and not warband.changed.is_connected(_on_warband_changed):
		warband.changed.connect(_on_warband_changed)
	var purse := get_node_or_null("/root/PlayerState")
	if purse != null and purse.has_signal("changed") \
			and not purse.changed.is_connected(_on_warband_changed):
		purse.changed.connect(_on_warband_changed)
	bind_gear_requests()

## The scene that fielded the bodies is going away while the socket stays open:
## a checkpoint reload, the host's LOAD row, a guest following the host into its
## new world. Nothing on the wire may touch a body that is about to be freed, and
## every soul is seated again on the next field.
func detach_scene() -> void:
	if controller != null and is_instance_valid(controller):
		if controller.possession_changed.is_connected(_on_controller_possession_changed):
			controller.possession_changed.disconnect(_on_controller_possession_changed)
		controller.transfer_requester = Callable()
	controller = null
	_detach_world()
	_fielded.clear()
	_waiting.clear()
	_driven.clear()
	# A new scene's mobs are new bodies: the delta book and the one-shot books
	# belong to the wood that is going away.
	_mob_sent.clear()
	_dead_sent.clear()
	_sent_loot.clear()

## "offline", "host" or "client".
func role() -> String:
	return _role

## Every soul on the field, this peer included, sorted by peer id.
func connected_peers() -> Array[int]:
	var out: Array[int] = []
	if _peer == null or multiplayer == null:
		return out
	if _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return out
	var self_id := multiplayer.get_unique_id()
	if self_id <= 0:
		return out
	out.append(self_id)
	for peer_id in multiplayer.get_peers():
		out.append(int(peer_id))
	out.sort()
	return out

func peer_count() -> int:
	return connected_peers().size()

func player_name() -> String:
	return _player_name

func name_of(peer_id: int) -> String:
	return str(_names.get(peer_id, ""))

## The `{peer: merc_id}` map in force: derived from the controller on the host
## (which is why a transfer the host made itself is in it too) and the last map
## the host sent everywhere else. `0` means a soul with no body.
func ownership() -> Dictionary:
	var map := {}
	if controller == null:
		return map
	if _role == "client":
		return _adopted.duplicate()
	for peer_id in connected_peers():
		map[peer_id] = maxi(0, controller.merc_for_peer(peer_id))
	return map

# --- opening and closing ---------------------------------------------------

func host(port: int, host_name: String) -> bool:
	if controller == null:
		return false
	if _role != "offline":
		leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, MAX_CLIENTS) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	_peer = peer
	_player_name = host_name.strip_edges()
	_names = {1: _player_name}
	_adopted = {}
	_beat_tick = -1
	# The host is ENet peer 1 and its soul is the controller's own by default.
	controller.local_peer_id = 1
	_role = "host"
	_wire_signals()
	role_changed.emit(_role)
	return true

## Open the socket to a host. The scene is not needed for this: a campaign guest
## connects from the title, is sent the host's warband, and only then opens the
## world that fields it (`setup` binds the controller when it exists).
func join(address: String, port: int, guest_name: String) -> bool:
	if _role != "offline":
		leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address.strip_edges(), port) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	_peer = peer
	_player_name = guest_name.strip_edges()
	_names = {}
	_adopted = {}
	_beat_tick = -1
	_role = "client"
	# The world scene, when it fielded the bodies, already handed this session
	# its mobs; a guest never runs their AI, so they become replicas now.
	_mark_world_replicas()
	bind_gear_requests()
	_wire_signals()
	role_changed.emit(_role)
	return true

## Give the body back and drop the socket. Safe to call in any role.
func leave() -> void:
	var was := _role
	_role = "offline"
	if controller != null:
		_release_body_of(controller.local_peer_id, "Left the battle.")
	_teardown()
	_adopted = {}
	if was != "offline":
		role_changed.emit(_role)

# --- ownership -------------------------------------------------------------

## Ask to enter a body: the host decides at once, a guest asks and waits for the
## answer. Returns the router-shaped payload; a guest's answer carries
## `pending = true` because the decision has not landed yet.
func request_body(merc_id: int) -> Dictionary:
	if controller == null:
		return {"ok": false, "message": "No warband body to enter.", "body_id": merc_id,
			"previous_body_id": -1, "reason": SoulRouter.REASON_UNKNOWN, "pending": false}
	if _role == "client":
		if not _has_peers():
			return {"ok": false, "message": "The host is not reachable yet.", "body_id": merc_id,
				"previous_body_id": -1, "reason": SoulRouter.REASON_NONE, "pending": false}
		if not _known_body(merc_id):
			return _refuse(controller.local_peer_id, merc_id, SoulRouter.REASON_UNKNOWN)
		request_transfer.rpc_id(1, merc_id)
		return {"ok": true, "message": "Asked the host.", "body_id": merc_id,
			"previous_body_id": controller.merc_for_peer(controller.local_peer_id),
			"reason": SoulRouter.REASON_NONE, "pending": true}
	return _host_transfer(controller.local_peer_id, merc_id)

## Guest -> host. The sender's id comes from ENet, never from the payload, so a
## guest can only ever move its own soul; the body is checked against the roster
## before the router is touched.
@rpc("any_peer", "call_remote", "reliable")
func request_transfer(merc_id: int) -> void:
	if _role != "host" or controller == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0 or sender == controller.local_peer_id:
		return
	_host_transfer(sender, merc_id)

## Guest -> host handshake, so a late joiner learns who is inside what and who
## the other souls are. A campaign guest is sent the campaign itself in answer.
@rpc("any_peer", "call_remote", "reliable")
func announce(guest_name: String) -> void:
	if _role != "host":
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	_names[sender] = guest_name.strip_edges()
	if shared_warband and controller != null:
		receive_campaign.rpc_id(sender, campaign_payload())
	_broadcast_ownership()

## Host -> everyone: the occupancy map plus the names that go with it.
@rpc("authority", "call_remote", "reliable")
func receive_ownership(assignments: Dictionary, names: Dictionary) -> void:
	_names = names.duplicate()
	_adopt_ownership(assignments)

## Host -> the one soul whose request lost.
@rpc("authority", "call_remote", "reliable")
func receive_refusal(merc_id: int, reason: String) -> void:
	transfer_refused.emit(merc_id, reason)

## Guest -> host: this soul's world is up and it can be put into a body. The
## host seats it in the first free one, or keeps it watching when none is.
@rpc("any_peer", "call_remote", "reliable")
func field_ready() -> void:
	if _role != "host" or controller == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0 or not multiplayer.get_peers().has(sender):
		return
	# One announcement per join: a client that repeats it (a retry, a modified
	# build) must not be able to re-announce every corpse and drop on every peer's
	# channel at will. A soul whose world genuinely rebuilt says so through
	# `receive_campaign`, which is the host's own call.
	if _fielded.has(sender):
		return
	_fielded[sender] = true
	if controller.merc_for_peer(sender) <= 0 and not _waiting.has(sender):
		_waiting.append(sender)
	# A seat is a move, and its own map leaves with it; with nothing free the
	# guest is told the truth (no body) rather than left believing it has one.
	_seat_waiting()
	_broadcast_ownership()
	# The lent copy was taken when the guest announced itself; the field may have
	# moved while its world was building. This peer needs the copy whatever the
	# last one was, so it is sent rather than marked.
	_push_warband(true)
	_mirror_dirty = true
	# And the bodies already on the ground: a guest that joins after the fight
	# still has to be able to search what it sees. The one-shot books are cleared
	# so the next poll re-announces every corpse pose and every open drop; the
	# guest's own delivery book ignores anything it already has.
	_dead_sent.clear()
	_sent_loot.clear()
	_send_corpses()


## Host -> every guest: every body still holding something. A late joiner's world
## has no record of a kill that happened before it arrived.
func _send_corpses() -> void:
	if _role != "host" or world == null or not _has_peers():
		return
	var vacuum = world.get("loot")
	if vacuum == null or not vacuum.has_method("corpse_ids"):
		return
	for corpse_id in vacuum.call("corpse_ids"):
		report_corpse(int(corpse_id))

## The guest's half of `field_ready`.
func report_fielded() -> void:
	if _role == "client" and _has_peers():
		field_ready.rpc_id(1)

## Host -> one guest (or every guest): the campaign it is about to play.
@rpc("authority", "call_remote", "reliable")
func receive_campaign(payload: Dictionary) -> void:
	if _role != "client":
		return
	campaign_received.emit(payload)

## Host -> every guest: the warband as it stands now. A guest's lent copy is
## replaced whole, and a body whose kit moved is re-dressed from it.
@rpc("authority", "call_remote", "reliable")
func receive_warband(text: String, gold_amount: int) -> void:
	var target: WarbandState = warband if warband != null else get_node_or_null("/root/Warband")
	if _role != "client" or target == null or not target.lent:
		return
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return
	var worn := _worn_signatures(target)
	target.lend(parsed, gold_amount)
	_redress(target, worn)

# --- gear on the shared warband ---------------------------------------------
#
# A guest plays the host's copy of the warband, so the paperdoll's verbs - wear a
# piece, take one off, swap the weapon set, re-kit a body or the band, hold a piece
# back from auto-equip - are requests, not writes. `WarbandState.ask_gear` hands
# each one here; the host runs the same verb on its own books and the answer comes
# back with the mirror. A refused request is the one thing the mirror cannot show
# (nothing changed), so it is sent as its own line.

## Point a lent warband's gear verbs at this session, or away from it. Called on
## `join`, on `setup` and on teardown, so a copy never points at a dead session.
func bind_gear_requests() -> void:
	var target: WarbandState = warband if warband != null else get_node_or_null("/root/Warband")
	if target == null:
		return
	target.gear_requester = Callable(self, "_send_gear_request") \
		if _role == "client" else Callable()

## Host -> every guest: the host's purse, when it moved and the books did not.
@rpc("authority", "call_remote", "reliable")
func receive_purse(gold_amount: int) -> void:
	if _role != "client":
		return
	var target: WarbandState = warband if warband != null else get_node_or_null("/root/Warband")
	if target == null or not target.lent:
		return
	target.lend_purse(gold_amount)

## Host -> every guest: one piece the warband booked, so a guest's looted list is
## the same list. The booking itself stays on the host (`WarbandLoot.booked`).
func announce_booked(item_id: String, collector_peer: int) -> void:
	if _role != "host" or not shared_warband or not _has_peers():
		return
	if item_id.is_empty():
		return
	var who := name_of(int(collector_peer))
	if who.is_empty():
		who = "the host" if int(collector_peer) == 1 else "another soul"
	receive_booked.rpc(item_id, int(collector_peer), who)

## Host -> every guest: a booked piece, and whose hands took it. A line for this
## peer's own take reads as its own hands; another soul's carries its name.
@rpc("authority", "call_remote", "reliable")
func receive_booked(item_id: String, collector_peer: int, collector_name: String) -> void:
	if _role != "client" or world == null:
		return
	if not world.has_method("note_booked"):
		return
	var mine := multiplayer != null and multiplayer.get_unique_id() == collector_peer
	world.call("note_booked", item_id, "" if mine else collector_name)

## Guest -> host. `_has_peers` is the reachability check the other requests use;
## false means the request never left and the verb refuses like it used to.
func _send_gear_request(request: Dictionary) -> bool:
	if _role != "client" or not shared_warband or not _has_peers():
		return false
	gear_request.rpc_id(1, request)
	return true

## Guest -> host: one gear verb for the shared warband. The host is the only
## place the kit changes; a guest can do exactly what the host could do, because
## the request runs through the same verb.
@rpc("any_peer", "call_remote", "reliable")
func gear_request(request: Dictionary) -> void:
	if _role != "host" or not shared_warband or warband == null:
		return
	var result: Dictionary = warband.apply_gear_request(request)
	if bool(result.get("ok", false)):
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender > 0 and multiplayer.get_peers().has(sender):
		receive_gear_refusal.rpc_id(sender, str(result.get("message", "")))

## Host -> the one guest whose gear change was refused. Nothing moved on the
## host's books, so this line is the whole of the answer.
@rpc("authority", "call_remote", "reliable")
func receive_gear_refusal(message: String) -> void:
	gear_refused.emit(message)

## The host's world opened anew under a session that stays up: every guest is
## sent the campaign again and rebuilds its own world on it.
func broadcast_campaign() -> void:
	if _role != "host" or not shared_warband or controller == null or not _has_peers():
		return
	# Every guest rebuilds its world on this, and each says `field_ready` again
	# once its new field is up: the one-announcement latch is opened for them, or
	# a reload would leave the whole band unseated.
	_fielded.clear()
	receive_campaign.rpc(campaign_payload())

## What a guest needs to field the host's world: the warband (as its save would
## be written), the purse, the merc ids standing on the field (a downed one
## included), where the party is, and the world's own layout answer.
func campaign_payload() -> Dictionary:
	var fielded: Array = []
	var focus := Vector3.ZERO
	if controller != null:
		for actor in controller.bodies():
			if not is_instance_valid(actor):
				continue
			var merc_id := controller.merc_of(actor)
			if merc_id > 0 and warband.roster.has(merc_id) \
					and warband.roster.state_of(merc_id) != WarbandContracts.HealthState.DEAD:
				fielded.append(merc_id)
				if focus.is_zero_approx():
					focus = actor.global_position
		var anchor = controller.focus_body()
		if anchor != null:
			focus = (anchor as Node3D).global_position
	var layout := {}
	if world != null and world.has_method("guest_layout"):
		layout = world.call("guest_layout")
	return {
		"warband": JSON.stringify(warband.to_dict()),
		"gold": warband.gold(),
		"bodies": fielded,
		"focus": [focus.x, focus.y, focus.z],
		"layout": layout,
	}

# --- snapshots -------------------------------------------------------------

## Host -> everyone. Unreliable: the next snapshot supersedes this one, and the
## entries were already split to fit a single datagram each.
@rpc("authority", "call_remote", "unreliable")
func receive_snapshot(tick: int, entries: Array) -> void:
	if controller == null:
		return
	_sync_local_peer()
	# The guest's playout clock: every arrival names a tick of the host's
	# simulation, and the render tick it settles on is what its own actions are
	# judged against.
	controller.ingest_snapshot(tick)
	var actors: Array = controller.bodies()
	for entry in entries:
		if typeof(entry) != TYPE_ARRAY:
			continue
		var pair: Array = entry
		if pair.size() < 2:
			continue
		var merc_id := int(pair[0])
		# A merc id this peer does not have is dropped before it reaches a node:
		# the wire can never invent a body or touch a stale one.
		if not _known_body(merc_id):
			continue
		var state: Variant = pair[1]
		var actor := controller.body_of(merc_id)
		if actor == null or typeof(state) != TYPE_DICTIONARY:
			continue
		actor.apply_snapshot(state, tick, actors)

# --- the world beyond the bodies -------------------------------------------
#
# Everything below is additive to the body replication above: the host owns the
# world's mobs, the loot and the missiles, and a guest receives them. A guest
# never runs a mob's brain and never trusts its own hits, which is why the mob
# classes' existing `replica` flag is the whole switching mechanism.

## Bind a `WarbandWorld` to this session. Called by `GameFlow` the moment the
## scene that fields the bodies binds, so it is also the moment the guards exist.
## Idempotent: re-attaching the same world only re-wires it.
func attach_world(world_node: Node3D) -> void:
	if world_node == null:
		return
	var same := world == world_node
	world = world_node
	if not same:
		_reset_world_trackers()
	_watch_world_tree()
	_wire_world_guards()
	_wire_world_loot()
	if _role == "client":
		_mark_world_replicas()
		if not _roguelite_pool.is_empty():
			_apply_roguelite_event({"t": "pool", "ids": _roguelite_pool})
		# A run may already be live: ask the host for its state, its props and
		# the bodies it has standing, in one round trip.
		if multiplayer.has_multiplayer_peer():
			send_roguelite_request({"t": "sync"})

## Every living mob in `world.guards` within `limit_metres` of any body in
## `bodies_in` (the whole field when it is empty), as `[name, snapshot]`. A name
## that is in `keep` - the mobs this peer is already being told about - stays in
## the answer out to `MOB_RELEASE_METRES`, so a body on the boundary cannot flap
## in and out of the stream. Bodies without a snapshot are skipped instead of
## being sent as an entry a client could never read.
func collect_mob_entries(limit_metres: float, bodies_in: Array = [],
		keep: Dictionary = {}) -> Array:
	var entries: Array = []
	if world == null:
		return entries
	var body_list: Array = bodies_in
	if body_list.is_empty():
		var bodies: Variant = world.get("bodies")
		if bodies is Array:
			body_list = bodies
	var release := maxf(limit_metres, MOB_RELEASE_METRES)
	for guard in _world_guards():
		if not is_instance_valid(guard) or not _mob_living(guard):
			continue
		if not guard is Node3D or not guard.has_method("snapshot"):
			continue
		var at: Vector3 = (guard as Node3D).global_position
		if not _near_any_body(at, body_list, limit_metres):
			var held := not keep.is_empty() and keep.has(str((guard as Node).name))
			if not held or not _near_any_body(at, body_list, release):
				continue
		entries.append([str((guard as Node).name), guard.call("snapshot")])
	return entries

## Apply a batch of mob states to the guards with those names. A name this peer
## does not own is dropped before it reaches a node: the wire can never invent a
## mob, exactly as it can never invent a body. Public so the unit regression can
## drive it without a socket.
func apply_mob_states(tick: int, states: Array) -> void:
	if world == null:
		return
	for entry in states:
		if typeof(entry) != TYPE_ARRAY:
			continue
		var pair: Array = entry
		if pair.size() < 2:
			continue
		var guard = _guard_named(str(pair[0]), tick)
		if guard == null or not guard.has_method("apply_snapshot"):
			continue
		var state: Variant = pair[1]
		if typeof(state) != TYPE_DICTIONARY:
			continue
		# The switch the mob classes already honour: no AI, no local authority,
		# and `apply_snapshot` becomes the only writer of pose and health. A class
		# that can hide a copy the host never fielded is asked to do so first.
		if guard.has_method("mark_replica"):
			guard.call("mark_replica")
		else:
			guard.set("replica", true)
		guard.call("apply_snapshot", state, tick)

## Pickups the host has not announced yet, as `[item_id, position]`. The instance
## id is booked here so a pickup that stays on the ground is sent exactly once.
func collect_new_loot() -> Array:
	var out: Array = []
	if world == null:
		return out
	var pickups: Variant = world.get("pickups")
	if not pickups is Array:
		return out
	var pickup_list: Array = pickups
	for pickup in pickup_list:
		if not is_instance_valid(pickup) or not pickup is Node3D:
			continue
		if bool(pickup.get("collected")):
			continue
		var key: int = (pickup as Node).get_instance_id()
		if _sent_loot.has(key):
			continue
		var item_id := str(pickup.get("item_id"))
		if item_id.is_empty():
			continue
		_sent_loot[key] = true
		out.append([item_id, (pickup as Node3D).global_position])
	return out

## Missiles the host has not announced yet, as `[origin, direction, speed]`.
## A guest only draws them; the host is the only place a hit is resolved.
func collect_new_missiles() -> Array:
	var out: Array = []
	if world == null:
		return out
	var missiles: Variant = world.get("projectiles")
	if not missiles is Array:
		return out
	var missile_list: Array = missiles
	for missile in missile_list:
		if not is_instance_valid(missile) or not missile is Node3D:
			continue
		var key: int = (missile as Node).get_instance_id()
		if _sent_missiles.has(key):
			continue
		var velocity: Variant = missile.get("velocity")
		if typeof(velocity) != TYPE_VECTOR3:
			continue
		var speed := (velocity as Vector3).length()
		if speed <= 0.05:
			continue
		_sent_missiles[key] = true
		out.append([(missile as Node3D).global_position, (velocity as Vector3) / speed, speed])
	return out

## Host -> everyone: the mobs a soul could reach. Unreliable, like the body
## snapshots; the next batch supersedes this one and each batch already fits one
## datagram.
@rpc("authority", "call_remote", "unreliable")
func receive_mobs(tick: int, states: Array) -> void:
	apply_mob_states(tick, states)

## Host -> one guest: the mobs this guest is no longer being told about at stream
## tick `tick`, because they left its reach. Reliable, and a copy is put down here
## rather than left for a timeout - a body that left the stream used to stand
## frozen wherever it was when it left, for as long as the stale clock took to
## notice. The tick rides along because it is the host's stream clock that the
## states are numbered on, and a state from before the leave is a datagram still
## in flight rather than news.
@rpc("authority", "call_remote", "reliable")
func receive_mob_leaves(tick: int, names: Array) -> void:
	if world == null:
		return
	for raw in names:
		var guard = _guard_named(str(raw))
		if guard == null or not is_instance_valid(guard):
			continue
		if guard.has_method("set_streamed"):
			guard.call("set_streamed", false, tick)
		elif guard is Node3D:
			# A mob class this build does not know how to put down still must not
			# stand there: hiding it is the one answer every body shares.
			(guard as Node3D).visible = false

## Host -> everyone: a piece of loot hit the ground. Reliable, because a drop
## that is missed is a piece the guest can never see or take.
@rpc("authority", "call_remote", "reliable")
func receive_loot(item_id: String, at: Vector3) -> void:
	if world == null or item_id.is_empty():
		return
	var key := "%s@%.2f,%.2f,%.2f" % [item_id, at.x, at.y, at.z]
	if _delivered_loot.has(key):
		return
	_remember(_delivered_loot, key)
	if world.has_method("spawn_pickup"):
		# `announced`: the one drop a guest's ground takes is the host's.
		world.call("spawn_pickup", item_id, at, true)

## Host -> everyone: a shot or a thrown blade. Visual only - a guest's copy can
## draw the flight but its mask is empty, so it can never resolve a hit.
@rpc("authority", "call_remote", "unreliable")
func receive_arrow(origin: Vector3, direction: Vector3, speed: float) -> void:
	if world == null or speed <= 0.0:
		return
	var heading := direction.normalized()
	if heading.is_zero_approx():
		return
	var key := "%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%.2f" % [origin.x, origin.y, origin.z,
		heading.x, heading.y, heading.z, speed]
	if _delivered_arrows.has(key):
		return
	_remember(_delivered_arrows, key)
	var arrow := ArrowScript.new()
	arrow.authoritative_damage = false
	arrow.hit_mask = 0
	world.add_child(arrow)
	arrow.launch(origin, heading, speed, 0.0, [])

## Host -> everyone: a shaft left the party quiver. Mirrored for the same reason a
## kill's gold is: the quiver is one ledger, and a guest whose copy never lost a
## shaft would shoot free. Reliable, because an arrow is a real spend.
@rpc("authority", "call_remote", "reliable")
func receive_ammo_spent(count: int) -> void:
	if count <= 0:
		return
	var warband := get_node_or_null("/root/Warband")
	if warband != null and warband.has_method("take_arrows"):
		warband.call("take_arrows", count)

## The host's own half of a spend it just booked locally: tell the peers. A guest
## that called this has nobody to tell - the host already sent its copy.
func report_ammo_spent(count: int) -> void:
	if _role != "host" or count <= 0 or not _has_peers():
		return
	receive_ammo_spent.rpc(count)

# --- the shared ground ------------------------------------------------------
#
# Looting is host-authoritative like every other booking: the warband's pool,
# the corpse records and the drop nodes are the host's, so a guest's press is an
# intent and never a local take. The guest still needs to see what it is
# searching, which is why the host copies the corpse records and every take back
# down the same peer. Nothing here trusts the guest with an id it could invent:
# `loot_for_peer` validates the body, the reach and the item on the host.

## Host -> everyone: a fallen body this session may search. Sent once when the
## body is registered, with what it still holds, and the id is the host's own, so
## the guest's screen and the host's takes name the same row.
## Host -> everyone: one arena event. State, props, spawns, drafts, keys and
## flashes all ride the same envelope, because they are all one director's
## decisions and a guest applies them in the order the host made them.
@rpc("authority", "call_remote", "reliable")
func receive_roguelite(event: Dictionary) -> void:
	if typeof(event) != TYPE_DICTIONARY:
		return
	if str(event.get("t", "")) == "pool":
		_roguelite_pool = event.get("ids", [])
	if world == null:
		return
	_apply_roguelite_event(event)


func _apply_roguelite_event(event: Dictionary) -> void:
	if world == null:
		return
	var run = world.get("roguelite")
	if run != null and run.has_method("apply_event"):
		run.apply_event(event)


func send_roguelite_event(event: Dictionary) -> void:
	if _role != "host":
		return
	for peer_id in _guest_ids():
		receive_roguelite.rpc_id(peer_id, event)


func send_roguelite_request(request: Dictionary) -> void:
	if _role != "client":
		return
	roguelite_request.rpc_id(1, request)


## Guest -> host: one arena request, attributed on arrival by the sender's own
## id. The wire never lets a guest name another body as the doer.
@rpc("any_peer", "call_remote", "reliable")
func roguelite_request(request: Dictionary) -> void:
	if _role != "host" or typeof(request) != TYPE_DICTIONARY:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	if world == null:
		return
	var run = world.get("roguelite")
	if run == null or not run.has_method("handle_request"):
		return
	if str(request.get("t", "")) == "sync":
		run.handle_request(sender, {"t": "sync"})
		send_roguelite_event({"t": "pool", "ids": _host_pool()})
		return
	run.handle_request(sender, request)


## What this host lends: the autoload's own ledger, never the loan it holds.
func _host_pool() -> Array:
	var meta = get_node_or_null("/root/Roguelite")
	if meta == null or not meta.has_method("lent_pool"):
		return []
	return meta.lent_pool()


## The armory is part of what a guest is lent with the warband, so it is sent
## when the socket opens rather than waiting for the first run.
func sync_roguelite_pool() -> void:
	if _role != "host":
		return
	var ids := _host_pool()
	for peer_id in _guest_ids():
		receive_roguelite.rpc_id(peer_id, {"t": "pool", "ids": ids})


@rpc("authority", "call_remote", "reliable")
func receive_corpse(corpse_id: int, body_name: String, label: String,
		items: Array, at: Vector3, remains: bool = false) -> void:
	var vacuum = world.get("loot") if world != null else null
	if vacuum == null or not vacuum.has_method("import_corpse"):
		return
	vacuum.call("import_corpse", corpse_id, body_name, label, items, at, remains)

## Host -> everyone: what that body holds now. An empty list is a stripped body.
@rpc("authority", "call_remote", "reliable")
func receive_corpse_items(corpse_id: int, items: Array) -> void:
	var vacuum = world.get("loot") if world != null else null
	if vacuum == null or not vacuum.has_method("set_corpse_items"):
		return
	vacuum.call("set_corpse_items", corpse_id, items)

## Host -> everyone: a drop left the ground where `at` names it.
@rpc("authority", "call_remote", "reliable")
func receive_drop_taken(item_id: String, at: Vector3) -> void:
	var vacuum = world.get("loot") if world != null else null
	if vacuum == null or not vacuum.has_method("pickups"):
		return
	# One take is one node: a second identical drop lying beside the first is
	# still on the ground on the host, so only the nearest match goes here.
	var best = null
	var best_distance := 3.0
	for pickup in vacuum.call("pickups"):
		if not is_instance_valid(pickup) or bool(pickup.get("collected")):
			continue
		if str(pickup.get("item_id")) != item_id:
			continue
		var distance: float = (pickup as Node3D).global_position.distance_to(at)
		if distance <= best_distance:
			best_distance = distance
			best = pickup
	if best != null:
		best.collect()

## Tell the peers about a body the scene just registered.
func report_corpse(corpse_id: int) -> void:
	if _role != "host" or corpse_id <= 0 or world == null:
		return
	var vacuum = world.get("loot")
	if vacuum == null or not vacuum.has_method("corpse_items"):
		return
	var items: Array = vacuum.call("corpse_items", corpse_id)
	if items.is_empty():
		return
	if not _has_peers():
		return
	receive_corpse.rpc(corpse_id, str(vacuum.call("corpse_name", corpse_id)),
		str(vacuum.call("corpse_label", corpse_id)), items,
		vacuum.call("corpse_position", corpse_id),
		bool(vacuum.call("corpse_is_remains", corpse_id)))

## Host: a body's record moved under the loot window. Only the host's copy emits
## this for a real take; a guest's copy is written by the RPC above and would
## otherwise echo the change back into the wire.
func _on_loot_corpse_changed(corpse_id: int, items: Array) -> void:
	if _role != "host" or not _has_peers():
		return
	# An empty list is `forget_corpse`; it travels as a take to nothing, and the
	# guest's row goes with it.
	receive_corpse_items.rpc(corpse_id, items)

## Host: any drop taken, by any soul, leaves every screen at the same time. The
## guest that took it has already had its press answered; this is the removal.
func _on_loot_drop_taken(item_id: String, at: Vector3) -> void:
	if _role != "host" or not _has_peers():
		return
	receive_drop_taken.rpc(item_id, at)

## Bind the world's one vacuum to this peer. The guest only receives; the host
## only sends, so the same signal cannot bounce twice.
func _wire_world_loot() -> void:
	if world == null:
		return
	var vacuum = world.get("loot")
	if vacuum == null or not vacuum.has_signal("corpse_changed"):
		return
	if vacuum.has_signal("corpse_registered") \
			and not vacuum.corpse_registered.is_connected(report_corpse):
		vacuum.corpse_registered.connect(report_corpse)
	if not vacuum.corpse_changed.is_connected(_on_loot_corpse_changed):
		vacuum.corpse_changed.connect(_on_loot_corpse_changed)
	if vacuum.has_signal("drop_taken") and not vacuum.drop_taken.is_connected(_on_loot_drop_taken):
		vacuum.drop_taken.connect(_on_loot_drop_taken)

# --- internals: the host ---------------------------------------------------

## One decision, shared by the host's own hotkeys and by the RPC above.
func _host_transfer(peer_id: int, merc_id: int) -> Dictionary:
	if controller == null:
		return _refuse(peer_id, merc_id, SoulRouter.REASON_UNKNOWN)
	if not _known_body(merc_id):
		return _refuse(peer_id, merc_id, SoulRouter.REASON_UNKNOWN)
	if peer_id != controller.local_peer_id and not multiplayer.get_peers().has(peer_id):
		return _refuse(peer_id, merc_id, "That soul is not in this battle.")
	var result: Dictionary = controller.activate(peer_id, merc_id)
	if not bool(result.get("ok", false)):
		return _refuse(peer_id, merc_id, str(result.get("reason", SoulRouter.REASON_UNKNOWN)))
	# The map goes out on the controller's own `possession_changed`, which every
	# move makes - this one, an eject, a hotkey - so no path can skip it.
	return result

## The router's rules already refused; this only makes sure the one soul that
## asked hears about it, and never the lucky soul that was asking for a body
## that turned out to be free.
func _refuse(peer_id: int, merc_id: int, reason: String) -> Dictionary:
	var previous := controller.merc_for_peer(peer_id) if controller != null else -1
	if controller != null and peer_id == controller.local_peer_id:
		transfer_refused.emit(merc_id, reason)
	elif multiplayer.get_peers().has(peer_id):
		receive_refusal.rpc_id(peer_id, merc_id, reason)
	return {"ok": false, "message": reason, "body_id": merc_id,
		"previous_body_id": previous, "reason": reason, "pending": false}

func _broadcast_ownership() -> void:
	if _role != "host" or not _has_peers():
		return
	# A scene hand-off nulls the controller for the length of a reload. The map is
	# derived from it, so a broadcast in that window would tell every guest that
	# nobody owns anything - a blank HUD and a soul with no body until the next
	# campaign arrives. The field is announced again when it is back.
	if controller == null or warband == null:
		return
	receive_ownership.rpc(ownership(), _names.duplicate())

func _has_peers() -> bool:
	return _peer != null and multiplayer != null and not multiplayer.get_peers().is_empty()

## Bodies this peer may name: in the roster (so an invented id is impossible)
## and registered by the scene (so a body that was never spawned cannot be hit).
func _known_body(merc_id: int) -> bool:
	if merc_id <= 0 or warband == null:
		return false
	if not warband.roster.has(merc_id):
		return false
	return warband.souls.has_body(merc_id)

# --- internals: the guest --------------------------------------------------

## Take the host's map as it stands. Every soul whose body changes lets go first
## and only then are the new bodies taken, so two souls trading bodies never meet
## a body that is still the other's. The router takes the host's word
## (`PossessionController.adopt`): the host has already applied every rule.
func _adopt_ownership(assignments: Dictionary) -> void:
	var next := {}
	for key in assignments:
		next[int(key)] = int(assignments[key])
	if controller == null:
		# The world is still building: the map is kept for `ownership()`, and the
		# host sends it again once this soul says its field is up.
		_adopted = next
		ownership_changed.emit(_adopted.duplicate())
		return
	_sync_local_peer()
	for peer_id in controller.possessing_peers():
		if int(next.get(peer_id, 0)) != controller.merc_for_peer(peer_id):
			_release_body_of(peer_id, "That soul let the body go.")
	for key in next:
		var peer_id := int(key)
		var merc_id := int(next[key])
		if merc_id <= 0 or not _known_body(merc_id):
			continue
		if controller.merc_for_peer(peer_id) == merc_id:
			continue
		controller.adopt(peer_id, merc_id)
	_adopted = next
	ownership_changed.emit(_adopted.duplicate())

## A guest's world has stood up a body the host fielded after this map arrived -
## a hire, a rescue, the reserve called up - and the map already names a soul in
## it: take the host's map again, so that soul is seated here as it is there.
func readopt_ownership() -> void:
	if _role != "client" or controller == null:
		return
	_adopt_ownership(_adopted)

## Give a body back on this process. The router is told first because it is the
## rule book; the controller then hands the body to the scene, where it keeps
## whatever AI flag the scene gave it.
func _release_body_of(peer_id: int, reason: String) -> void:
	if controller == null:
		return
	var owned := warband != null and warband.souls.body_of(peer_id) != -1
	var in_scene := controller.body_for_peer(peer_id) != null \
		or (peer_id == controller.local_peer_id and controller.active_actor != null)
	if warband != null:
		warband.souls.release_peer(peer_id, reason)
	if not owned and not in_scene:
		return
	var actor := controller.body_for_peer(peer_id)
	if actor != null:
		actor.frame_driven = false
	# `PossessionController` publishes a release for its own soul only; the
	# remote half is the same detach routine (body flags, intents, camera), and a
	# second copy of it here would drift from the one the controller keeps.
	controller._release_peer(peer_id, reason)

## A guest cannot know its ENet id before the handshake lands, and the map it is
## about to adopt is keyed by that id, so the soul id is refreshed first.
func _sync_local_peer() -> void:
	if controller == null or _role != "client" or multiplayer == null:
		return
	var id := multiplayer.get_unique_id()
	if id > 0 and controller.local_peer_id != id:
		controller.local_peer_id = id

# --- internals: the wire ---------------------------------------------------

## The wire's heartbeat: one beat per simulation tick, on the physics clock.
##
## It used to ride the rendered frame with three float accumulators, and that is
## the seam this replaced. A send clock on the render frame is quantised to the
## frame: a 47 fps host produced 2-and-3-frame gaps for a 3-tick interval, fed
## every receiver's jitter estimator a wobble it then paid for in playout delay,
## and could not hold 20 Hz at all below 20 fps. Keyed on the tick number instead,
## the cadence is exact on every machine - and because the tick label is the step
## that produced the pose beside it, a hitch can no longer put a stale pose under
## a fresh number. A tick that never ran is a tick that was never sent; there is
## nothing to bank and nothing to replay.
func _physics_process(_delta: float) -> void:
	if _link.active():
		_link.drain()
	if _role == "client":
		# A guest keeps no send clock: it predicts its own body and waits for the
		# host's snapshots. Only its soul id can move under it.
		_sync_local_peer()
		return
	if _role != "host" or controller == null or warband == null:
		return
	# The engine's physics frame, not the controller's simulation tick: the two
	# advance together (one per physics step), but the controller's counter only
	# runs while it has bodies spawned, and a host between worlds still has to
	# seat a guest and mirror a purse. The body stream is labelled with the
	# controller's tick because that is the number the rewind history is keyed on;
	# the mobs are labelled with this one. Both are 60 Hz counts, and no receiver
	# ever compares the two.
	var tick := Engine.get_physics_frames()
	if tick == _beat_tick:
		return
	_beat_tick = tick
	Perf.begin("net.session")
	_tick_session(tick)
	Perf.end()

func _tick_session(tick: int) -> void:
	if not _waiting.is_empty() and tick % SEAT_TICKS == 0:
		_seat_waiting()
	if not _has_peers():
		return
	if shared_warband:
		Perf.begin("net.mirror")
		_tick_mirror(tick)
		Perf.end()
	if tick % SNAPSHOT_TICKS == 0:
		Perf.begin("net.snapshot")
		_send_snapshots()
		Perf.end()
	Perf.begin("net.world")
	_tick_world(tick)
	Perf.end()

# --- internals: the shared warband -------------------------------------------

## Every move the controller makes is a map change: a guest's request, the
## host's own hotkey, an eject on death, a release with nowhere left to go. The
## map goes out inside the same call, never on a later frame: whatever a peer
## sends after hearing of a move must reach the host after the map that move
## produced, and a map deferred to the next frame arrives behind it. A guest's new
## body is also the one the host steps only on frames that guest sent, and a soul
## left without a body joins the queue for the next free one.
func _on_controller_possession_changed(peer_id: int, merc_id: int) -> void:
	if _role != "host" or controller == null:
		return
	_broadcast_ownership()
	if peer_id != controller.local_peer_id:
		var previous = _driven.get(peer_id)
		var body := controller.body_of(merc_id) if merc_id > 0 else null
		if previous != null and is_instance_valid(previous) and previous != body:
			previous.frame_driven = false
		if body != null:
			# The authority may only step a peer's body on frames that peer
			# actually sent; an invented frame is the one correction no one can
			# reconcile.
			body.frame_driven = true
			_driven[peer_id] = body
		else:
			_driven.erase(peer_id)
	if merc_id > 0:
		_waiting.erase(peer_id)
	elif _on_field(peer_id) and not _waiting.has(peer_id):
		_waiting.append(peer_id)

## A soul the host is responsible for seating: its own, or a guest whose world is up.
func _on_field(peer_id: int) -> bool:
	if controller != null and peer_id == controller.local_peer_id:
		return true
	return _fielded.has(peer_id) and multiplayer.get_peers().has(peer_id)

## Put every waiting soul into the first free body, the soul that lost its body
## first going first. With nothing free they keep watching: a body that already
## has a soul inside is that soul's, and nobody is moved out of it.
func _seat_waiting() -> void:
	if _role != "host" or controller == null or warband == null:
		return
	for peer_id in _waiting.duplicate():
		if not _on_field(peer_id) or controller.merc_for_peer(peer_id) > 0:
			_waiting.erase(peer_id)
			continue
		var free := _free_body()
		if free <= 0:
			return
		# The body's roster record is what the guest dresses it from: the copy goes
		# out in the same call and before the map, so a mercenary that joined the
		# warband since the last copy is already in it when the seat arrives.
		if shared_warband:
			# A seat is a new guest: the copy goes out whatever the last one was.
			_push_warband(true)
		_host_transfer(peer_id, free)

## The first living, unoccupied body on the field, in roster order - one the
## world says can move first (a prisoner still caged in the opening comes last).
func _free_body() -> int:
	var fallback := -1
	for merc_id in warband.souls.possessable_ids():
		var actor := controller.body_of(merc_id)
		if actor == null or not is_instance_valid(actor) or not actor.alive or actor.downed:
			continue
		if world == null or not world.has_method("is_free_body") \
				or bool(world.call("is_free_body", merc_id)):
			return merc_id
		if fallback < 0:
			fallback = merc_id
	return fallback

func _on_warband_changed() -> void:
	if _role == "host" and shared_warband:
		_mirror_dirty = true

## Send the warband on the first change after a quiet spell, and at most every
## `MIRROR_TICKS` while it keeps changing.
func _tick_mirror(tick: int) -> void:
	if not _mirror_dirty or tick - _mirror_tick < MIRROR_TICKS:
		return
	_push_warband()

## The host's warband as its file would hold it, to every guest. Reliable and in
## order, which is what lets a seat name a mercenary the guest has just been told
## about.
func _push_warband(force: bool = false) -> void:
	_mirror_dirty = false
	_mirror_tick = _beat_tick
	if warband == null:
		return
	var text := JSON.stringify(warband.to_dict())
	var gold_amount := warband.gold()
	# A change that does not change the books is not worth re-sending the whole
	# campaign: every guest would decode and rebuild it (`lend` -> `from_dict`),
	# which is a jump in the frame time for nothing. A guest arriving needs the
	# copy regardless, so the seat paths force it.
	if not force and _mirror_sent and text == _mirror_text:
		# The books are the same as the copy every guest already has; only the
		# purse moved (a kill, a sale), and one number is not a whole campaign
		# reload on every guest's screen.
		if gold_amount != _mirror_gold:
			_mirror_gold = gold_amount
			receive_purse.rpc(gold_amount)
		return
	_mirror_sent = true
	_mirror_text = text
	_mirror_gold = gold_amount
	receive_warband.rpc(text, gold_amount)

## What each fielded body wears, so a copy that moved somebody's kit re-dresses
## exactly those bodies. The hotbar layout is part of the dressing: the host's
## key order is the one the guest's HUD has to draw, or the same skill fires
## from a key the other machine answers with a different one.
func _worn_signatures(target: WarbandState) -> Dictionary:
	var out := {}
	if controller == null:
		return out
	for actor in controller.bodies():
		var merc_id := controller.merc_of(actor)
		if merc_id > 0 and target.roster.has(merc_id):
			out[merc_id] = _dressing_signature(target, merc_id)
	return out

func _dressing_signature(target: WarbandState, merc_id: int) -> String:
	return "%s|%s" % [str(target.roster.equipped_of(merc_id)),
		str(target.roster.hotbar_order_of(merc_id))]

func _redress(target: WarbandState, before: Dictionary) -> void:
	if controller == null:
		return
	for key in before:
		var merc_id := int(key)
		if target.roster.has(merc_id) \
				and _dressing_signature(target, merc_id) != str(before[key]):
			controller.refresh_gear(merc_id)

## Every body, named by the simulation tick it was stepped on - the number a
## guest's action names back and the host rewinds to (`arm_lag`).
func _send_snapshots() -> void:
	var tick := int(controller.sim_tick())
	var entries: Array = []
	for merc_id in warband.roster.ids():
		var actor := controller.body_of(merc_id)
		if actor == null:
			continue
		entries.append([merc_id, actor.snapshot()])
	if entries.is_empty():
		return
	for batch in NetLimits.batches(entries, [tick]):
		_stream(func(): receive_snapshot.rpc(tick, batch), 0, true)

# --- internals: the world --------------------------------------------------

## The world's clocks. Mobs and missiles are polled, not event-driven: a mob's
## pose only means "now", and a missile that was announced on the frame it was
## fired would arrive before the host's own first physics step moved it.
func _tick_world(tick: int) -> void:
	if world == null:
		return
	if tick % MOB_SEND_TICKS == 0:
		_send_mobs(tick)
	if tick % LOOT_SEND_TICKS == 0:
		_send_loot()
	if tick % MISSILE_SEND_TICKS == 0:
		_send_missiles()

func _send_mobs(tick: int) -> void:
	var peers := _guest_ids()
	if peers.is_empty():
		return
	# One snapshot of every living guard, taken once and shared by every peer.
	# The stream used to call `snapshot()` (a ten-key dictionary, two Vector4s)
	# once per guard *per guest*, then hash it twice per guest and encode it once
	# per guest to size the batch and again in the RPC. Two peers was two copies
	# of the same authority state; eight was eight.
	# Every guest body, once: a guard outside every soul's release band is not in
	# any stream this tick, so its snapshot is not built at all.
	var points := PackedVector3Array()
	for peer_id in peers:
		points.append_array(_positions_of(_peer_bodies(peer_id)))
	var candidates := _mob_candidates(points)
	# A death is a one-shot fact. Left in the unreliable batch, one lost datagram
	# leaves the guest with a living copy of a body the host buried; the reliable
	# channel makes the corpse appear on every screen even across a hitch. Every
	# stream is per guest, because every guest is only told about its own ground.
	for peer_id in peers:
		_stream_mobs_to(peer_id, tick, candidates)

## Every living guard's state and position, once per send tick. `stamp` is the
## change detector (a state hash, computed once instead of once per peer) and
## `size` is the encoded bytes of `[name, state]`, measured once so a peer's
## batches can be cut without re-encoding.
func _mob_candidates(points: PackedVector3Array) -> Array:
	var out: Array = []
	for guard in _world_guards():
		if not is_instance_valid(guard) or not guard is Node3D or not _mob_living(guard):
			continue
		if not guard.has_method("snapshot"):
			continue
		var at: Vector3 = (guard as Node3D).global_position
		if not _near_points(at, points, MOB_RELEASE_METRES):
			continue
		var state: Variant = guard.call("snapshot")
		if typeof(state) != TYPE_DICTIONARY:
			continue
		var mob_name := str((guard as Node).name)
		out.append({
			"name": mob_name,
			"pos": at,
			"state": state,
			"stamp": state.hash(),
			"size": NetLimits.size([mob_name, state]),
		})
	return out

## The entries worth sending to this peer: one that changed since its last copy,
## or all of them on a refresh. `book` is the peer's own last-stamp table, so a
## calm body costs one integer compare instead of a recursive dictionary hash.
## Returns `{entries, sizes}`: the `[name, state]` pairs and the encoded size each
## candidate already measured.
func _changed_candidates(candidates: Array, refresh: bool, book: Dictionary) -> Dictionary:
	var changed: Array = []
	var sizes := PackedInt32Array()
	for candidate in candidates:
		var mob_name := str(candidate.name)
		var stamp := int(candidate.stamp)
		if not refresh and book.has(mob_name) and int(book[mob_name]) == stamp:
			continue
		book[mob_name] = stamp
		changed.append([mob_name, candidate.state])
		sizes.append(int(candidate.size))
	return {"entries": changed, "sizes": sizes}

## One guest's mob stream: the bodies within `MOB_REACH_METRES` of *that peer's*
## own body, everything it is already being told about out to
## `MOB_RELEASE_METRES`, the changes since its last batch, and a reliable name for
## every body that just left it.
func _stream_mobs_to(peer_id: int, tick: int, candidates: Array) -> void:
	var book: Dictionary = _mob_sent_by_peer.get(peer_id, {})
	if not book is Dictionary:
		book = {}
	_mob_sent_by_peer[peer_id] = book
	var known: Dictionary = _mob_live.get(peer_id, {})
	if not known is Dictionary:
		known = {}
	var bodies := _peer_bodies(peer_id)
	var points := _positions_of(bodies)
	var deaths := _collect_death_states(points, _dead_book(peer_id))
	for batch in NetLimits.batches(deaths, [tick]):
		_stream(func(): receive_mob_deaths.rpc_id(peer_id, tick, batch), peer_id)
	var live := {}
	var streamed: Array = []
	for candidate in candidates:
		var mob_name := str(candidate.name)
		if not _near_points(candidate.pos, points, MOB_REACH_METRES):
			# A body on the release band stays until it leaves it: no flapping at
			# the edge of a reach.
			if not known.has(mob_name) or not _near_points(candidate.pos, points,
					MOB_RELEASE_METRES):
				continue
		live[mob_name] = true
		streamed.append(candidate)
	var left := mob_leaves(known, live)
	for mob_name in left:
		# Forgotten with the announcement: a body that walks back into reach must
		# be sent again even if it has not moved a millimetre since.
		book.erase(mob_name)
	if not left.is_empty():
		_stream(func(): receive_mob_leaves.rpc_id(peer_id, tick, left), peer_id)
	_mob_live[peer_id] = live
	if streamed.is_empty():
		return
	# A crowded hall is thirty calm bodies twice over; re-sending each one's whole
	# state fifteen times a second is the traffic that turns walking through it
	# into a stutter. Only what changed goes out, with a full copy once a second so
	# a lost delta cannot leave a mob frozen for good.
	var delta := _changed_candidates(streamed, tick % MOB_REFRESH_TICKS == 0, book)
	var changed: Array = delta.entries
	if changed.is_empty():
		return
	for batch in NetLimits.batches(changed, [tick], delta.sizes):
		_stream(func(): receive_mobs.rpc_id(peer_id, tick, batch), peer_id, true)

## The names in a peer's stream that the live set no longer names: what that
## guest is told to put down. Pure, so the wire contract is driveable without a
## socket.
static func mob_leaves(known: Dictionary, live: Dictionary) -> Array:
	var out: Array = []
	for mob_name in known:
		if not live.has(mob_name):
			out.append(mob_name)
	return out

## The guests this peer names: every other peer on the field, host or not.
func _guest_ids() -> Array:
	var out: Array = []
	if multiplayer == null:
		return out
	for peer_id in multiplayer.get_peers():
		out.append(int(peer_id))
	out.sort()
	return out

## The ground one peer draws: its own body. A soul still waiting for a seat has
## none, and is told about the whole party's ground until it is fielded.
func _peer_bodies(peer_id: int) -> Array:
	var bodies: Array = []
	if controller != null:
		var actor: Variant = controller.body_for_peer(peer_id)
		if actor != null and is_instance_valid(actor) and actor is Node3D:
			bodies.append(actor)
	if bodies.is_empty() and world != null:
		var listed: Variant = world.get("bodies")
		if listed is Array:
			return listed
	return bodies

## The corpse book of one peer, made on first use.
func _dead_book(peer_id: int) -> Dictionary:
	var book: Variant = _dead_sent.get(peer_id, null)
	if book is Dictionary:
		return book
	var fresh := {}
	_dead_sent[peer_id] = fresh
	return fresh

## The entries worth sending: one that changed since the last copy, or all of
## them on a refresh. `book` is the peer's own last-copy table; `null` means the
## shared one, for a caller with no peer behind it. Public so the unit regression
## can drive the rule without a socket.
func changed_mob_entries(entries: Array, refresh: bool, book: Variant = null) -> Array:
	var memo: Dictionary = _mob_sent if book == null else book
	var changed: Array = []
	for entry in entries:
		if typeof(entry) != TYPE_ARRAY or (entry as Array).size() < 2:
			continue
		var mob_name := str(entry[0])
		var state: Variant = entry[1]
		if not refresh:
			var previous: Variant = memo.get(mob_name, null)
			if previous is Dictionary and state is Dictionary \
					and previous.hash() == state.hash():
				continue
		memo[mob_name] = state
		changed.append(entry)
	return changed

## Host -> everyone: bodies that stopped being alive. Reliable and separate from
## the pose stream, so a dropped pose can never leave a ghost standing.
@rpc("authority", "call_remote", "reliable")
func receive_mob_deaths(tick: int, states: Array) -> void:
	apply_mob_states(tick, states)

## A guard that has died is no longer "living", so the collector above stops
## naming it - but a replica still has to see it fall. Each corpse is sent once to
## each guest it stood near, with the snapshot whose `a` is false, and then that
## peer's book forgets it.
func _collect_death_states(points: PackedVector3Array, sent: Variant = null) -> Array:
	var out: Array = []
	if world == null:
		return out
	var book: Dictionary = _dead_sent if sent == null else sent
	for guard in _world_guards():
		if not is_instance_valid(guard) or not guard is Node3D:
			continue
		if not guard.has_method("snapshot") or _mob_living(guard):
			continue
		var at: Vector3 = (guard as Node3D).global_position
		if not _near_points(at, points, MOB_REACH_METRES):
			continue
		var guard_name := str((guard as Node).name)
		if book.has(guard_name):
			continue
		book[guard_name] = true
		out.append([guard_name, guard.call("snapshot")])
	return out

func _send_loot() -> void:
	for entry in collect_new_loot():
		receive_loot.rpc(str(entry[0]), entry[1])

func _send_missiles() -> void:
	for entry in collect_new_missiles():
		var origin: Vector3 = entry[0]
		var heading: Vector3 = entry[1]
		var speed := float(entry[2])
		_stream(func(): receive_arrow.rpc(origin, heading, speed), 0, true)

func _world_guards() -> Array:
	if world == null:
		return []
	var guards: Variant = world.get("guards")
	if guards is Array:
		return guards
	return []

## `tick` names the stream tick an apply is running for, so one build of the
## name table serves a whole batch: a hall holds three hundred guards and a batch
## names sixty of them, and a scan per name is sixty scans of the same list.
func _guard_named(guard_name: String, tick: int = -1):
	if guard_name.is_empty():
		return null
	if tick >= 0:
		return _guards_for(tick).get(guard_name, null)
	for guard in _world_guards():
		if not is_instance_valid(guard) or not guard is Node:
			continue
		if str((guard as Node).name) == guard_name:
			return guard
	return null

## Name -> guard for one stream tick.
func _guards_for(tick: int) -> Dictionary:
	if tick == _guards_stamp:
		return _guards_by_name
	_guards_stamp = tick
	_guards_by_name.clear()
	for guard in _world_guards():
		if is_instance_valid(guard) and guard is Node:
			_guards_by_name[str((guard as Node).name)] = guard
	return _guards_by_name

## A guard with no `alive` property is still treated as living: the wire must not
## silently hide a class this build does not recognise, and the regression's
## snapshot-less guard is skipped for the right reason (no snapshot), not this one.
func _mob_living(guard) -> bool:
	if guard == null or not is_instance_valid(guard):
		return false
	var alive: Variant = guard.get("alive")
	return alive == null or bool(alive)

func _near_any_body(point: Vector3, bodies: Array, limit_metres: float) -> bool:
	if bodies.is_empty():
		return false
	var reach := maxf(limit_metres, 0.0)
	reach *= reach
	for body in bodies:
		if not is_instance_valid(body) or not body is Node3D:
			continue
		if (body as Node3D).global_position.distance_squared_to(point) <= reach:
			return true
	return false

## The body positions a peer's reach is measured from, read once per send tick.
## A guard is 200 points against 8 bodies; asking each point for each body's
## `global_position` again was the send tick's dominant term.
static func _positions_of(bodies: Array) -> PackedVector3Array:
	var points := PackedVector3Array()
	points.resize(bodies.size())
	for index in bodies.size():
		var body = bodies[index]
		if is_instance_valid(body) and body is Node3D:
			points[index] = (body as Node3D).global_position
		else:
			points[index] = Vector3.INF
	return points

## Whether `point` is within `limit_metres` of any of the peer's bodies. Pure
## floating point over a packed array: no node, no array, no call per body.
static func _near_points(point: Vector3, points: PackedVector3Array,
		limit_metres: float) -> bool:
	var reach := maxf(limit_metres, 0.0)
	reach *= reach
	for other in points:
		if other.distance_squared_to(point) <= reach:
			return true
	return false

## Mark the guards that already exist as replicas on a guest: the host owns
## every mob's brain and every kill.
func _wire_world_guards() -> void:
	if _role != "client":
		return
	for guard in _world_guards():
		_mark_replica(guard)

## A mob the world adds after the hand-off - a ring that wakes, a wave that
## spawns - still has to be a replica on a guest.
func _on_world_node_added(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if _role != "client":
		return
	# `node_added` fires before `_ready`, so the group may not be joined yet; the
	# snapshot surface is the same contract and is present from construction.
	if node.has_method("apply_snapshot") or node.is_in_group(WILD_MOB_GROUP):
		_mark_replica(node)

func _mark_world_replicas() -> void:
	for guard in _world_guards():
		_mark_replica(guard)

func _mark_replica(guard) -> void:
	if guard == null or not is_instance_valid(guard) or not guard is Node:
		return
	# The one switch every wilderness mob already honours: its physics frame
	# returns before any AI, and `apply_snapshot` is the sole writer of pose.
	# `mark_replica` also hides the copy until the host proves it exists here,
	# which is what keeps a guest from seeing a mob the host already killed.
	if guard.has_method("mark_replica"):
		guard.call("mark_replica")
	else:
		(guard as Node).set("replica", true)

func _watch_world_tree() -> void:
	if _world_watch or not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	if not tree.node_added.is_connected(_on_world_node_added):
		tree.node_added.connect(_on_world_node_added)
	_world_watch = true

func _unwatch_world_tree() -> void:
	if not _world_watch:
		return
	_world_watch = false
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree != null and tree.node_added.is_connected(_on_world_node_added):
		tree.node_added.disconnect(_on_world_node_added)

func _detach_world() -> void:
	_unwatch_world_tree()
	world = null
	_reset_world_trackers()

func _reset_world_trackers() -> void:
	_sent_loot.clear()
	_sent_missiles.clear()
	_dead_sent.clear()
	_delivered_loot.clear()
	_delivered_arrows.clear()
	_mob_live.clear()
	_mob_sent_by_peer.clear()
	_mob_sent.clear()
	_guards_by_name.clear()
	_guards_stamp = -1

## Book a payload that has been spawned, clearing the book when it is full. A
## repeat announcement then costs one dictionary lookup.
func _remember(book: Dictionary, key: String) -> void:
	if book.size() >= DELIVERY_BOOK_CAP:
		book.clear()
	book[key] = true

func _wire_signals() -> void:
	if _signals_wired or multiplayer == null:
		return
	_signals_wired = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# A host that opens a weapon at the totem lends it at once: the rack's pool
	# is live, not a snapshot taken when the socket opened.
	var ledger = get_node_or_null("/root/Roguelite")
	if ledger != null and ledger.has_signal("meta_changed") \
			and not ledger.meta_changed.is_connected(sync_roguelite_pool):
		ledger.meta_changed.connect(sync_roguelite_pool)

func _unwire_signals() -> void:
	if not _signals_wired or multiplayer == null:
		return
	_signals_wired = false
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.disconnect(_on_connected)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)
	var ledger = get_node_or_null("/root/Roguelite")
	if ledger != null and ledger.has_signal("meta_changed") \
			and ledger.meta_changed.is_connected(sync_roguelite_pool):
		ledger.meta_changed.disconnect(sync_roguelite_pool)

func _teardown() -> void:
	# The host's armory was a loan, not a purchase: a guest that leaves the
	# session takes the lent rows back out of its rack.
	if _role == "client":
		var ledger = get_node_or_null("/root/Roguelite")
		if ledger != null and ledger.has_method("share_pool"):
			ledger.share_pool([])
	_unwire_signals()
	_detach_world()
	if controller != null and is_instance_valid(controller):
		controller.lag_tracking = false
		controller.clear_lag_history()
	if _peer != null:
		_peer.close()
		_peer = null
	if multiplayer != null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_names.clear()
	_fielded.clear()
	_waiting.clear()
	_mob_sent.clear()
	_mirror_sent = false
	_mirror_text = ""
	_mirror_gold = -1
	_mirror_tick = -10 ** 9
	_beat_tick = -1
	# The session is the only door a lent copy's gear verbs had: shut it.
	bind_gear_requests()

func _on_connected() -> void:
	_sync_local_peer()
	announce.rpc_id(1, _player_name)

func _on_peer_connected(peer_id: int) -> void:
	# Somebody can now send us an action, so the host starts keeping the frames it
	# would be rewound into. A solo party keeps none.
	if _role == "host" and controller != null:
		controller.clear_lag_history()
		controller.lag_tracking = true
	if _role == "host":
		sync_roguelite_pool()
	peer_joined.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	_fielded.erase(peer_id)
	_waiting.erase(peer_id)
	_release_body_of(peer_id, "That soul left the battle.")
	if _role == "host" and controller != null and connected_peers().size() <= 1:
		controller.lag_tracking = false
	_driven.erase(peer_id)
	_names.erase(peer_id)
	# The stream books of a soul that is gone: nothing is ever sent to it again,
	# and a peer id that joins later must not inherit what it was told.
	_mob_live.erase(peer_id)
	_mob_sent_by_peer.erase(peer_id)
	_dead_sent.erase(peer_id)
	if _role == "host":
		_seat_waiting()
		_broadcast_ownership()
	peer_left.emit(peer_id)

func _on_connection_failed() -> void:
	_end("Could not join.")

func _on_server_disconnected() -> void:
	_end("The host left.")

func _end(reason: String) -> void:
	var was := _role
	_role = "offline"
	if controller != null:
		_release_body_of(controller.local_peer_id, reason)
	_teardown()
	_adopted = {}
	if was != "offline":
		role_changed.emit(_role)
		session_ended.emit(reason)
