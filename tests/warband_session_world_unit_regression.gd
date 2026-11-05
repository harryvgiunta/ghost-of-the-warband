extends SceneTree
## One process, no socket: the world half of `WarbandSession` driven directly.
##
## The world scene is faked down to the four lists the session reads (`guards`,
## `bodies`, `pickups`, `projectiles`), so the checks are about the wire contract
## alone: which mobs are encoded, that an encoded batch fits one datagram, that a
## state names a guard or is dropped, and that a repeated announcement is booked
## once. The lent warband a co-op guest plays from is checked against two temp
## saves, and `GameFlow`'s campaign doors against one.
##
## The acceptance line is the last one printed:
##   WARBAND_SESSION_WORLD_UNIT_REGRESSION checks=N failures=M

const SessionScript = preload("res://scripts/warband/warband_session.gd")
const NetLimits = preload("res://scripts/net_limits.gd")
const NetReplication = preload("res://scripts/net_replication.gd")
const GameFlowScript = preload("res://scripts/warband/game_flow.gd")
const WarbandStateScript = preload("res://scripts/warband/warband_state.gd")
const AnnointCatalog = preload("res://scripts/warband/annoint_catalog.gd")
const State = preload("res://scripts/player_state.gd")

const WARBAND_SAVE := "user://warband_session_world_unit_warband.json"
const PLAYER_SAVE := "user://warband_session_world_unit_player.json"
const MOB_TICK := 9

var checks := 0
var failures := 0

# --- fakes -----------------------------------------------------------------

## A mob with the full surface: health, the replica switch, the snapshot pair the
## session actually calls, and the stream switch every real mob family answers
## (`set_streamed`) - a body the host stops naming is put down where it stands.
class FakeGuard:
	extends Node3D
	signal defeated(enemy: Node3D, reward: int)

	var alive := true
	var health := 50.0
	var max_health := 50.0
	var replica := false
	var applied_tick := -1
	## The stream tick the host last put this copy down at, and whether it is
	## drawn right now. The real classes keep the same two facts.
	var left_at := -1
	var drawn := true

	func snapshot() -> Dictionary:
		return {
			"p": global_position, "y": 0.0, "v": Vector3.ZERO, "g": true,
			"s": "IDLE", "t": 0.0, "h": health, "a": alive, "x": Vector4.ZERO,
		}

	func set_streamed(value: bool, tick: int = -1) -> void:
		if value:
			drawn = true
			return
		left_at = maxi(left_at, tick)
		drawn = false
		visible = false

	func apply_snapshot(state: Dictionary, tick: int = -1) -> void:
		if tick >= 0 and tick <= left_at:
			return
		health = float(state.get("h", health))
		applied_tick = tick
		drawn = true
		visible = true


## A guard the session cannot encode: no snapshot, no apply. It must be skipped
## by the host and invisible to a state batch, never crash either.
class PlainGuard:
	extends Node3D
	var alive := true


class FakePickup:
	extends Node3D
	var item_id := "sword_iron"
	var collected := false


class FakeMissile:
	extends Node3D
	var velocity := Vector3(0.0, 0.0, -24.0)


class FakeWorld:
	extends Node3D
	var guards: Array = []
	var bodies: Array = []
	var pickups: Array = []
	var projectiles: Array = []
	var hud = null
	## Every `spawn_pickup` this peer was asked for, so a repeat is countable.
	var spawned: Array = []

	func spawn_pickup(item_id: String, at: Vector3, announced: bool = false) -> void:
		spawned.append([item_id, at, announced])


# --- harness ---------------------------------------------------------------

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WARBAND_SESSION_WORLD_UNIT_FAIL  ", message)

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The mob names an entry list carries, in order.
func _names_of(entries: Array) -> Array:
	var out: Array = []
	for entry in entries:
		if typeof(entry) == TYPE_ARRAY and not (entry as Array).is_empty():
			out.append(str(entry[0]))
	return out

func run() -> void:
	_remove(WARBAND_SAVE)
	_remove(PLAYER_SAVE)

	var session: Variant = SessionScript.new()
	session.name = "WorldSession"
	root.add_child(session)

	var world := FakeWorld.new()
	world.name = "FakeWorld"
	root.add_child(world)

	var body := Node3D.new()
	body.name = "Body"
	world.add_child(body)
	body.global_position = Vector3.ZERO
	world.bodies = [body]

	var guard := FakeGuard.new()
	guard.name = "CampWatcher1"
	world.add_child(guard)
	guard.global_position = Vector3(0.0, 0.0, 10.0)
	world.guards.append(guard)

	var plain := PlainGuard.new()
	plain.name = "Prop"
	world.add_child(plain)
	plain.global_position = Vector3(0.0, 0.0, 5.0)
	world.guards.append(plain)

	var pickup := FakePickup.new()
	pickup.name = "Drop"
	world.add_child(pickup)
	pickup.global_position = Vector3(3.0, 0.0, -2.0)
	world.pickups.append(pickup)

	var missile := FakeMissile.new()
	missile.name = "Shaft"
	world.add_child(missile)
	missile.global_position = Vector3(0.0, 1.2, -1.0)
	world.projectiles.append(missile)

	# Attaching with no multiplayer peer must be a plain graph operation.
	session.attach_world(world)
	check(session.role() == "offline", "a session with no socket stays offline")
	check(session.world == world, "the session remembers the world it replicates")

	# --- what the host encodes ---------------------------------------------
	var entries: Array = session.collect_mob_entries(70.0)
	check(entries.size() == 1, "only the guard with a snapshot is encoded (%d)" % entries.size())
	if entries.size() == 1:
		var entry: Array = entries[0]
		check(str(entry[0]) == "CampWatcher1", "the entry is keyed by the guard's name")
		check(typeof(entry[1]) == TYPE_DICTIONARY, "the entry carries the guard's snapshot")
		check(NetLimits.size(entry) <= NetLimits.PAYLOAD,
			"one encoded mob fits NetLimits.PAYLOAD (%d)" % NetLimits.size(entry))
	var batches: Array = NetLimits.batches(entries, [MOB_TICK])
	check(not batches.is_empty(), "the encoded mobs split into at least one batch")
	for batch in batches:
		check(NetLimits.fits([MOB_TICK, batch]),
			"a mob batch plus its tick fits one datagram (%d)" % NetLimits.message_size([MOB_TICK, batch]))
	check(session.collect_mob_entries(1.0).is_empty(),
		"a mob outside the reach is never sent")

	# --- what the guest applies --------------------------------------------
	session.apply_mob_states(MOB_TICK, [
		["CampWatcher1", {"h": 12.0}],
		["NoSuchGuard", {"h": 1.0}],
	])
	check(guard.replica, "applying a state stops the guard's local AI")
	check(is_equal_approx(guard.health, 12.0), "applying a state writes its health (%f)" % guard.health)
	check(guard.applied_tick == MOB_TICK, "the batch tick reaches the snapshot")
	check(world.guards.size() == 2, "an unknown name invents no guard")

	session.receive_mobs(MOB_TICK + 1, [["CampWatcher1", {"h": 4.0}]])
	check(is_equal_approx(guard.health, 4.0), "the mob RPC applies the same batch")
	check(guard.applied_tick == MOB_TICK + 1, "the mob RPC carries its own tick")

	# --- the host's one-shot announcements ---------------------------------
	var loot: Array = session.collect_new_loot()
	check(loot.size() == 1, "the host announces the new pickup once (%d)" % loot.size())
	if loot.size() == 1:
		check(str(loot[0][0]) == "sword_iron", "the announcement carries the catalog id")
	check(session.collect_new_loot().is_empty(), "a sent pickup id never repeats")

	var missiles: Array = session.collect_new_missiles()
	check(missiles.size() == 1, "the host announces the new missile once (%d)" % missiles.size())
	if missiles.size() == 1:
		check(is_equal_approx(float(missiles[0][2]), 24.0), "the announcement carries the speed")
	check(session.collect_new_missiles().is_empty(), "a sent missile id never repeats")

	# --- the guest's handlers ----------------------------------------------
	session.receive_loot("sword_iron", Vector3(3.0, 0.0, -2.0))
	check(world.spawned.size() == 1, "a loot announcement spawns one drop")
	check(world.spawned.size() == 1 and bool(world.spawned[0][2]),
		"the drop is spawned as the host's announcement, the one kind a guest's ground takes")
	session.receive_loot("sword_iron", Vector3(3.0, 0.0, -2.0))
	check(world.spawned.size() == 1, "a repeated loot announcement is ignored")

	var before := world.get_child_count()
	session.receive_arrow(Vector3(0.0, 1.2, -1.0), Vector3(0.0, 0.0, -1.0), 24.0)
	check(world.get_child_count() == before + 1, "an arrow announcement spawns one missile")
	var arrow: Variant = world.get_child(world.get_child_count() - 1)
	check(arrow != null and not bool(arrow.authoritative_damage),
		"the guest's arrow can never resolve damage")
	check(arrow != null and int(arrow.hit_mask) == 0, "the guest's arrow has no hit mask")
	session.receive_arrow(Vector3(0.0, 1.2, -1.0), Vector3(0.0, 0.0, -1.0), 24.0)
	check(world.get_child_count() == before + 1, "a repeated arrow announcement is ignored")

	# --- the lent warband --------------------------------------------------
	# A co-op guest plays the host's warband and must come out of the session with
	# its own campaign exactly as it went in: the file is never written or read
	# while the loan lasts, the purse shown is the host's, and every gear and purse
	# verb is the host's to make.
	var player: Variant = root.get_node("PlayerState")
	player.save_path = PLAYER_SAVE
	player.reset(false)
	var flow: Variant = root.get_node("GameFlow")
	var warband: Variant = root.get_node("Warband")
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	warband.add_mercenary("Own Man")
	warband.save_state()
	var own_text := FileAccess.get_file_as_string(WARBAND_SAVE)
	var own_credits := int(player.credits)

	# The host's warband, as its session sends it: a warband's own `to_dict()`.
	var lender: Variant = WarbandStateScript.new()
	var host_id: int = lender.add_mercenary("Host Man")
	lender.add_mercenary("Host Second")
	lender.stash.add("sword_iron", 1)
	lender.stash.add("bow_short", 1)
	lender.stash.add("ichor_vial", 1)
	var host_dict: Dictionary = lender.to_dict()
	lender.free()
	warband.lend(host_dict, 444)
	check(warband.lent, "a guest's warband is lent for the session")
	check(warband.roster.count() == 2 and warband.roster.name_of(host_id) == "Host Man",
		"the lent roster is the host's (%d, %s)" % [warband.roster.count(), warband.roster.name_of(host_id)])
	check(warband.gold() == 444, "the purse shown is the host's (%d)" % warband.gold())
	check(not warband.spend_gold(10), "a lent purse is never spent on the guest")
	var bought: Dictionary = warband.buy_gear("sword_iron")
	check(not bool(bought.get("ok", true)) and str(bought.get("message", "")) == warband.LENT_MESSAGE,
		"buying into the host's stash is the host's to do (%s)" % str(bought.get("message", "")))
	var equipped: Dictionary = warband.equip_merc(host_id, "main", "sword_iron")
	check(not bool(equipped.get("ok", true)),
		"a lent copy with no session to ask refuses to dress the host's mercenary")
	var refused_swap: Dictionary = warband.swap_weapon_set(host_id)
	check(not bool(refused_swap.get("ok", true)),
		"and refuses a swap (%s)" % str(refused_swap.get("message", "")))
	# With a session behind it, the same verb travels instead of writing: the
	# callable the session installs is the whole of the guest's side of it.
	var asked: Array[Dictionary] = []
	warband.gear_requester = func(request: Dictionary) -> bool:
		asked.append(request)
		return true
	var routed: Dictionary = warband.equip_merc(host_id, "main", "sword_iron")
	check(bool(routed.get("pending", false)),
		"a guest's equip is sent to the host (%s)" % str(routed.get("message", "")))
	check(asked.size() == 1 and str(asked[0].get("verb", "")) == "equip"
			and int((asked[0].get("args", []) as Array)[0]) == host_id,
		"the request names the verb and the body (%s)" % str(asked))
	check(str(warband.roster.equipped_of(host_id).get("main", "")) != "sword_iron",
		"and the lent copy is still not the guest's to write")
	var swapped: Dictionary = warband.swap_weapon_set(host_id)
	check(bool(swapped.get("pending", false)) and asked.size() == 2
			and str(asked[1].get("verb", "")) == "swap_set",
		"a guest's own TAB travels the same way (%s)" % str(asked))
	var laid: Dictionary = warband.set_hotbar_order(host_id, ["rending_strike"])
	check(bool(laid.get("pending", false)) and asked.size() == 3
			and str(asked[2].get("verb", "")) == "hotbar_order",
		"and the keys a guest lays out are the host's to lay (%s)" % str(asked))
	# The altar is open to a guest: the press is a request naming the copy, the
	# pooled vial is the host's to spend, and the die is the host's to throw.
	var copy := int(warband.annoint_copy_for_item("bow_short"))
	var rite: Dictionary = warband.anoint("bow_short", copy)
	check(bool(rite.get("pending", false)) and asked.size() == 4
			and str(asked[3].get("verb", "")) == "anoint"
			and int((asked[3].get("args", []) as Array)[1]) == copy,
		"a guest's rite travels to the host with the copy it laid (%s)" % str(asked))
	check(warband.annoints.count("bow_short", copy) == 0
			and warband.stash.pooled_count("ichor_vial") == 1,
		"and the lent books spend no vial until the host answers")
	# The host runs the same verb on the books it lent. One weld is already on the
	# copy so every band of the die - add, take, replace - commits on the host and
	# the test cannot hang on a roll of nothing.
	var host: Variant = WarbandStateScript.new()
	host.from_dict(host_dict)
	var pool: Array = AnnointCatalog.for_item(State.ITEMS.get("bow_short", {}))
	var seed_id := ""
	for entry in pool:
		if bool(entry.wired):
			seed_id = str(entry.id)
			break
	check(not seed_id.is_empty() and host.annoints.add("bow_short", copy, seed_id),
		"the host's copy carries a weld to begin with")
	var seeded: Array = host.annoints.ids("bow_short", copy)
	var answered: Dictionary = host.apply_gear_request(
		{"verb": "anoint", "args": ["bow_short", copy]})
	check(bool(answered.get("ok", false))
			and str(answered.get("item_id", "")) == "bow_short",
		"the host answers with the rite's own result (%s)" % str(answered.get("message", "")))
	check(host.annoints.ids("bow_short", copy) != seeded,
		"the host's die landed on the copy the guest named")
	check(host.stash.pooled_count("ichor_vial") == 0,
		"the rite spends the pooled vial on the host's books")
	var re_dressed: Array[String] = []
	warband.annointed_state.connect(func(item_id: String, _entries: Array) -> void:
		re_dressed.append(item_id))
	warband.lend(host.to_dict(), 444)
	check(re_dressed.has("bow_short"),
		"and the host's welds re-dress the guest's bodies (%s)" % str(re_dressed))
	host.free()
	warband.gear_requester = Callable()
	check(not bool(warband.equip_merc(host_id, "main", "sword_iron").get("ok", true)),
		"and the door shuts with the session")
	check(int(player.credits) == own_credits, "the guest's own purse is untouched")
	warband.save_state()
	check(FileAccess.get_file_as_string(WARBAND_SAVE) == own_text,
		"a lent warband never writes over the guest's own save")
	check(not warband.load_state(), "a lent warband never reads the guest's own save into the session")
	warband.lend(host_dict, 500)
	check(warband.gold() == 500 and warband.roster.count() == 2,
		"the host's next copy replaces the lent one whole")
	warband.end_loan()
	check(not warband.lent, "the loan ends with the session")
	check(warband.roster.count() == 1 and warband.roster.name_of(warband.roster.ids()[0]) == "Own Man",
		"the guest's own campaign comes back from its own file")
	check(warband.gold() == own_credits, "and so does its own purse (%d)" % warband.gold())

	# --- the mob stream only carries news -------------------------------
	# Thirty calm bodies in a hall are the traffic that turns a walk through it
	# into a stutter: an unchanged body costs no packet, and a refresh repeats
	# everything so a lost delta cannot freeze a mob for good.
	var first_pass: Array = session.changed_mob_entries(
		[["wolf", {"pos": [1.0, 0.0, 0.0]}], ["rat", {"pos": [2.0, 0.0, 0.0]}]], false)
	check(first_pass.size() == 2, "a first pass sends every mob (%d)" % first_pass.size())
	var repeated: Array = session.changed_mob_entries(
		[["wolf", {"pos": [1.0, 0.0, 0.0]}], ["rat", {"pos": [2.0, 0.0, 0.0]}]], false)
	check(repeated.is_empty(), "an unchanged mob costs no packet (%d)" % repeated.size())
	var moved: Array = session.changed_mob_entries(
		[["wolf", {"pos": [5.0, 0.0, 0.0]}], ["rat", {"pos": [2.0, 0.0, 0.0]}]], false)
	check(moved.size() == 1 and str(moved[0][0]) == "wolf",
		"the body that moved is the one sent (%s)" % str(moved))
	var refreshed: Array = session.changed_mob_entries(
		[["wolf", {"pos": [5.0, 0.0, 0.0]}], ["rat", {"pos": [2.0, 0.0, 0.0]}]], true)
	check(refreshed.size() == 2, "a refresh repeats every mob (%d)" % refreshed.size())

	# --- a guest is told about its own ground, not the party's -------------
	# The whole of the party's fight used to ride one broadcast: a soul two
	# hundred metres away was sent every mob near the rest of the band - mobs it
	# could not see, drawn and animated on its machine, and enough extra datagrams
	# to lose the ones it could. The reach is measured from the body being told.
	var near_body := Node3D.new()
	near_body.name = "NearBody"
	world.add_child(near_body)
	near_body.global_position = Vector3.ZERO
	var far_body := Node3D.new()
	far_body.name = "FarBody"
	world.add_child(far_body)
	far_body.global_position = Vector3(0.0, 0.0, 200.0)
	var far_guard := FakeGuard.new()
	far_guard.name = "FarWatcher"
	world.add_child(far_guard)
	far_guard.global_position = Vector3(0.0, 0.0, 195.0)
	world.guards.append(far_guard)
	var near_names := _names_of(session.collect_mob_entries(70.0, [near_body]))
	check(not near_names.has("FarWatcher"),
		"a mob near another soul's body is not in this guest's stream (%s)" % str(near_names))
	var far_names := _names_of(session.collect_mob_entries(70.0, [far_body]))
	check(far_names.has("FarWatcher"), "and it is in the stream of the guest standing there")
	check(not far_names.has("CampWatcher1"),
		"who is not told about the mob standing beside the host's body (%s)" % str(far_names))

	# The band that stops a mob flapping at the edge of a reach: in the stream it
	# waits for a movement, out of it a mob is named once.
	far_guard.global_position = Vector3(0.0, 0.0, 85.0)
	check(not _names_of(session.collect_mob_entries(70.0, [near_body])).has("FarWatcher"),
		"past the reach a mob is not sent to a guest that never had it")
	var kept_names := _names_of(
		session.collect_mob_entries(70.0, [near_body], {"FarWatcher": true}))
	check(kept_names.has("FarWatcher"),
		"and is kept while it is already in that stream, inside the release band (%s)"
			% str(kept_names))
	far_guard.global_position = Vector3(0.0, 0.0, session.MOB_RELEASE_METRES + 6.0)
	check(not _names_of(session.collect_mob_entries(70.0, [near_body],
		{"FarWatcher": true})).has("FarWatcher"),
		"past the release band even a streamed body leaves it")
	far_guard.global_position = Vector3(0.0, 0.0, 195.0)

	# What leaves a stream is named once, and the name is the whole message.
	var leaving: Array = session.mob_leaves({"FarWatcher": true, "CampWatcher1": true},
		{"CampWatcher1": true})
	check(leaving.size() == 1 and str(leaving[0]) == "FarWatcher",
		"the mob that left the stream is the one named (%s)" % str(leaving))
	check(session.mob_leaves({"CampWatcher1": true}, {"CampWatcher1": true}).is_empty(),
		"a body still in the stream is never named as gone")

	# The guest's half of that: the copy is put down here, at once - not a second
	# later through the stale clock - and a datagram still in flight from before
	# the leave cannot put it back.
	session.apply_mob_states(MOB_TICK + 5, [["CampWatcher1", {"h": 30.0}]])
	check(guard.drawn, "a mob the host names is drawn")
	session.receive_mob_leaves(MOB_TICK + 6, ["CampWatcher1"])
	check(not guard.drawn and not guard.visible, "a mob the host stops naming is put down at once")
	session.apply_mob_states(MOB_TICK + 5, [["CampWatcher1", {"h": 3.0}]])
	check(is_equal_approx(guard.health, 30.0),
		"a state from before the leave is not news (%f)" % guard.health)
	check(not guard.drawn, "and it puts nothing back on the screen")
	session.apply_mob_states(MOB_TICK + 7, [["CampWatcher1", {"h": 7.0}]])
	check(is_equal_approx(guard.health, 7.0),
		"a state from after the leave is (%f)" % guard.health)
	check(guard.drawn, "and the body is back on the screen")

	# --- the send clock is the physics clock --------------------------------
	# Every stream fires on a stride of the simulation tick, never on a rendered
	# frame: the cadence is exact on a 144 Hz client and on a 21 fps host alike,
	# and a packet's tick label is always the step that produced its pose. Each
	# stride has to divide the clock, or the rate stops being the rate it claims
	# and every second lands on a different phase.
	# The engine's own rate and the wire's rate are one number, or nothing below
	# means anything: a project at 90 physics ticks would make every stride 1.5x
	# the rate it says it is, on every machine, silently.
	var engine_hz := float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 0))
	check(is_equal_approx(engine_hz, float(session.TICK_HZ)),
		"the project's physics rate is the wire's tick rate (%s vs %s)"
			% [str(engine_hz), str(session.TICK_HZ)])
	check(is_equal_approx(float(session.MOB_SEND_TICKS) / float(session.TICK_HZ),
			float(NetReplication.MOB_INTERVAL_SECONDS)),
		"the sender's mob stride is the interval a replica renders at (%.4f s)"
			% (float(session.MOB_SEND_TICKS) / float(session.TICK_HZ)))
	var strides: Dictionary = session.CADENCE
	check(strides.size() == 6, "every stream is in the cadence table (%s)" % str(strides))
	for stream in strides:
		var stride := int(strides[stream])
		check(stride > 0 and int(session.TICK_HZ) % stride == 0,
			"the %s stride divides the clock (%d ticks of %d)"
				% [stream, stride, int(session.TICK_HZ)])
	check(int(strides["snapshot"]) == 3 and int(strides["mob"]) == 4,
		"bodies go at 20 Hz and mobs at 15 Hz (%d, %d)"
			% [strides["snapshot"], strides["mob"]])
	check(session.TICK_HZ / int(strides["snapshot"]) == 20.0
			and session.TICK_HZ / int(strides["mob"]) == 15.0
			and session.TICK_HZ / int(strides["loot"]) == 5.0,
		"and the rates the docs name are the ones the strides give")

	# --- the campaign doors ------------------------------------------------
	warband.reset_state()
	warband.save_state()
	flow.active = true
	flow.host_campaign(0, "Host")
	check(flow.world_start == "camp", "HOST GAME's new game opens in the cages (%s)" % flow.world_start)
	check(str(flow.warband_intent.get("scene", "")) == GameFlowScript.WORLD_SCENE,
		"the host door asks for the world scene")
	check(str(flow.warband_intent.get("mode", "")) == "host", "the host door carries the host mode")

	warband.add_mercenary("Test")
	warband.save_state()
	check(warband.roster.count() == 1, "the temp save holds a roster")
	flow.host_campaign(0, "Host", GameFlowScript.HOST_CHECKPOINT)
	check(flow.world_start == "town",
		"hosting from a save with no checkpoint opens at the town (%s)" % flow.world_start)
	check(warband.roster.count() == 1, "hosting from the checkpoint keeps the saved roster")
	flow.host_campaign(0, "Host", GameFlowScript.HOST_NEW)
	check(flow.world_start == "camp" and warband.roster.count() == 0,
		"hosting a new game throws the saved warband away for the cages (%d)" % warband.roster.count())

	# JOIN connects from the title and opens nothing until the host answers.
	var probe := PacketPeerUDP.new()
	probe.bind(0)
	var silent_port := probe.get_local_port()
	probe.close()
	var scene_changes: int = flow.transitions
	flow.join_campaign("127.0.0.1", silent_port, "Guest")
	check(str(flow.warband_intent.get("mode", "")) == "join", "the join door carries the join mode")
	check(str(flow.warband_role()) == "client", "JOIN GAME opens its socket on the title")
	check(flow.transitions == scene_changes, "no world opens before the host has answered")
	check(not warband.lent, "nothing is lent before the host's warband arrives")
	flow.leave_warband()
	check(str(flow.warband_role()) == "offline" and flow.warband_intent.is_empty(),
		"leaving a join that never landed drops the socket and the intent")

	# --- cleanup -----------------------------------------------------------
	flow.active = false
	flow.leave_warband()
	session.leave()
	_remove(WARBAND_SAVE)
	_remove(PLAYER_SAVE)
	print("WARBAND_SESSION_WORLD_UNIT_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
