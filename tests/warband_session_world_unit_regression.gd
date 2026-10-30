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
const GameFlowScript = preload("res://scripts/warband/game_flow.gd")
const WarbandStateScript = preload("res://scripts/warband/warband_state.gd")

const WARBAND_SAVE := "user://warband_session_world_unit_warband.json"
const PLAYER_SAVE := "user://warband_session_world_unit_player.json"
const MOB_TICK := 9

var checks := 0
var failures := 0

# --- fakes -----------------------------------------------------------------

## A mob with the full surface: health, the replica switch, and the snapshot
## pair the session actually calls.
class FakeGuard:
	extends Node3D
	signal defeated(enemy: Node3D, reward: int)

	var alive := true
	var health := 50.0
	var max_health := 50.0
	var replica := false
	var applied_tick := -1

	func snapshot() -> Dictionary:
		return {
			"p": global_position, "y": 0.0, "v": Vector3.ZERO, "g": true,
			"s": "IDLE", "t": 0.0, "h": health, "a": alive, "x": Vector4.ZERO,
		}

	func apply_snapshot(state: Dictionary, tick: int = -1) -> void:
		health = float(state.get("h", health))
		applied_tick = tick


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
	check(not bool(equipped.get("ok", true)), "a guest cannot dress the host's mercenary")
	check(not bool(warband.swap_weapon_set(host_id).get("ok", true)),
		"a guest's own TAB never swaps on its lent copy (the host's world does it)")
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
