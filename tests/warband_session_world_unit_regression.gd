extends SceneTree
## One process, no socket: the world half of `WarbandSession` driven directly.
##
## The world scene is faked down to the four lists the session reads (`guards`,
## `bodies`, `pickups`, `projectiles`), so the checks are about the wire contract
## alone: which mobs are encoded, that an encoded batch fits one datagram, that a
## state names a guard or is dropped, and that a repeated announcement is booked
## once. `GameFlow`'s campaign doors are checked against a temp save.
##
## The acceptance line is the last one printed:
##   WARBAND_SESSION_WORLD_UNIT_REGRESSION checks=N failures=M

const SessionScript = preload("res://scripts/warband/warband_session.gd")
const NetLimits = preload("res://scripts/net_limits.gd")
const GameFlowScript = preload("res://scripts/warband/game_flow.gd")

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

	func spawn_pickup(item_id: String, at: Vector3) -> void:
		spawned.append([item_id, at])


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

	var player: Variant = root.get_node("PlayerState")
	player.save_path = PLAYER_SAVE
	player.reset(false)
	var credits_before: int = int(player.credits)
	session.receive_reward(17)
	check(int(player.credits) == credits_before + 17,
		"a reward is paid exactly once (%d -> %d)" % [credits_before, int(player.credits)])
	session.receive_reward(0)
	check(int(player.credits) == credits_before + 17, "a zero reward books nothing")

	# --- the campaign doors ------------------------------------------------
	var flow: Variant = root.get_node("GameFlow")
	var warband: Variant = root.get_node("Warband")
	warband.save_path = WARBAND_SAVE

	warband.reset_state()
	flow.active = true
	flow.host_campaign(0, "Host")
	check(flow.world_start == "camp", "a fresh campaign opens in the cages (%s)" % flow.world_start)
	check(str(flow.warband_intent.get("scene", "")) == GameFlowScript.WORLD_SCENE,
		"the host door asks for the world scene")
	check(str(flow.warband_intent.get("mode", "")) == "host", "the host door carries the host mode")

	warband.add_mercenary("Test")
	warband.save_state()
	check(warband.roster.count() == 1, "the temp save holds a roster")
	flow.host_campaign(0, "Host")
	check(flow.world_start == "town", "a warband with no checkpoint opens at the town (%s)" % flow.world_start)
	check(str(flow.warband_intent.get("scene", "")) == GameFlowScript.WORLD_SCENE,
		"a resumed host still asks for the world scene")

	flow.join_campaign("127.0.0.1", 0, "Guest")
	check(flow.world_start == "town", "a guest opens where the save points (%s)" % flow.world_start)
	check(str(flow.warband_intent.get("mode", "")) == "join", "the join door carries the join mode")
	check(str(flow.warband_intent.get("scene", "")) == GameFlowScript.WORLD_SCENE,
		"the join door asks for the world scene")

	# --- cleanup -----------------------------------------------------------
	flow.active = false
	flow.leave_warband()
	session.leave()
	_remove(WARBAND_SAVE)
	_remove(PLAYER_SAVE)
	print("WARBAND_SESSION_WORLD_UNIT_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
