extends SceneTree
## Two real processes play the campaign through `GameFlow`: the host opens the
## world with `host_campaign()`, a guest child joins it with `join_campaign()`,
## and the things the campaign promises over the wire all have to agree.
##
## Nothing is built by hand here. The host writes two identical warband saves
## (one for itself, one handed to the guest), each holding a four-sword squad on
## the trail bookmark; both machines load that save, both open the one world
## scene, and the session carries the bodies, the mobs, the loot and the kill
## reward between them. The guest reports what its own tree says, the host reads
## the copy of the world it owns, and a `Report` node at `/root/CoopReport` is
## the one RPC address both processes share.
##
## The host leg runs by default; the guest is the same script started with
## `-- --coop-client <port> <savepath>`.

const WORLD_SCENE := "res://scenes/warband_world.tscn"
const REPORT_NAME := "CoopReport"
const TRAIL_POINT := Vector3(6.0, 0.0, -90.0)
## Four bodies is the squad the saves carry; the guest must field the same four.
const SQUAD_NAMES := ["Aldous", "Brine", "Cael", "Dorn"]
## The walk the guest is asked to send.
const WALK_FRAMES := 40
## Whole-run budget. The two world builds are the expensive part; everything
## else is a handful of seconds, and the harness must finish under a minute.
const WATCHDOG_SECONDS := 50.0

var checks := 0
var failures := 0
var warband
var state
var flow
var world
var report
var child_pid := -1
var host_save := ""
var client_save := ""
var host_purse := ""
var client_purse := ""
var deadline_ms := 0
var reports: Dictionary = {}
var client_start_credits := 0
var leave_requested := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WARBAND_COOP_CAMPAIGN_FAIL  ", message)

# --- the shared RPC node ---------------------------------------------------

class Report:
	extends Node
	signal submitted(payload: Dictionary)
	signal probe_requested(tag: String, guard_name: String)
	signal walk_requested(frames: int)
	signal leave_requested()

	@rpc("any_peer", "call_remote", "reliable")
	func submit(payload: Dictionary) -> void:
		submitted.emit(payload)

	@rpc("authority", "call_remote", "reliable")
	func probe(tag: String, guard_name: String) -> void:
		probe_requested.emit(tag, guard_name)

	@rpc("authority", "call_remote", "reliable")
	func walk(frames: int) -> void:
		walk_requested.emit(frames)

	@rpc("authority", "call_remote", "reliable")
	func leave() -> void:
		leave_requested.emit()

# --- small shared helpers --------------------------------------------------

func _abs(path: String) -> String:
	return path if path.is_absolute_path() else ProjectSettings.globalize_path(path)

func _remove(path: String) -> void:
	if path.is_empty():
		return
	var full := _abs(path)
	if FileAccess.file_exists(full):
		DirAccess.remove_absolute(full)

func _new_temp(tag: String) -> String:
	return OS.get_temp_dir().path_join("warband_coop_%d_%d_%s.json" % [
		OS.get_process_id(), Time.get_ticks_usec(), tag])

func _world_is_ready() -> bool:
	var scene := current_scene
	return scene != null and str(scene.scene_file_path) == WORLD_SCENE \
		and scene.has_method("stats")

## A card pauses the tree, and a paused tree runs no physics - a test that waits
## through one would measure nothing. Play the reader: close whatever is up.
func _close_any_card() -> void:
	if world == null or not is_instance_valid(world):
		return
	var card = world.get("card")
	if card != null and is_instance_valid(card) and card.is_open():
		card.close()

func _wait_until(predicate: Callable, timeout: float) -> bool:
	var limit := int(timeout * 1000.0)
	if deadline_ms > 0:
		limit = mini(limit, deadline_ms - Time.get_ticks_msec())
	var until := Time.get_ticks_msec() + maxi(limit, 0)
	while Time.get_ticks_msec() < until:
		_close_any_card()
		if bool(predicate.call()):
			return true
		await process_frame
	_close_any_card()
	return bool(predicate.call())

func _wait_physics_until(predicate: Callable, timeout: float) -> bool:
	var limit := int(timeout * 1000.0)
	if deadline_ms > 0:
		limit = mini(limit, deadline_ms - Time.get_ticks_msec())
	var until := Time.get_ticks_msec() + maxi(limit, 0)
	while Time.get_ticks_msec() < until:
		_close_any_card()
		if bool(predicate.call()):
			return true
		await physics_frame
	_close_any_card()
	return bool(predicate.call())

# --- entry -----------------------------------------------------------------

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--coop-client"):
		await _client_run()
	else:
		await _host_run()

# --- host ------------------------------------------------------------------

func _host_run() -> void:
	deadline_ms = Time.get_ticks_msec() + int(WATCHDOG_SECONDS * 1000.0)
	warband = root.get_node_or_null("Warband")
	state = root.get_node_or_null("PlayerState")
	flow = root.get_node_or_null("GameFlow")
	check(warband != null, "The Warband autoload exists")
	check(state != null, "The PlayerState autoload exists")
	check(flow != null, "The GameFlow autoload exists")
	if warband == null or state == null or flow == null:
		await _host_done()
		return
	check(flow.has_method("host_campaign"), "GameFlow.host_campaign() exists")
	check(flow.has_method("join_campaign"), "GameFlow.join_campaign() exists")
	if not flow.has_method("host_campaign") or not flow.has_method("join_campaign"):
		await _host_done()
		return

	host_save = _new_temp("host_save")
	client_save = _new_temp("client_save")
	host_purse = host_save + ".purse"
	client_purse = client_save + ".purse"
	_remove(host_save)
	_remove(client_save)
	state.save_path = host_purse
	state.reset(false)
	warband.save_path = host_save
	warband.reset_state()
	flow.active = false

	# One trail bookmark and four swords: the world opens past the cages with a
	# squad that can fight, which is the only start where every piece below has
	# something to read.
	for merc_name in SQUAD_NAMES:
		var merc_id: int = warband.add_mercenary(str(merc_name))
		var equipped: Dictionary = warband.roster.equip(merc_id, "main", "sword_short")
		check(bool(equipped.get("ok", false)),
			"Mercenary %s takes its shortsword" % str(merc_name))
	warband.save_checkpoint("trail_start", "trail", TRAIL_POINT, "COOP")
	check(warband.has_checkpoint(), "The save holds the trail bookmark")
	check(warband.checkpoint_standing() >= 3,
		"The bookmark stands a squad up (%d)" % warband.checkpoint_standing())
	check(warband.roster.count() == SQUAD_NAMES.size(),
		"The save holds the four-sword squad (%d)" % warband.roster.count())
	check(FileAccess.file_exists(host_save), "The host save was written")

	# Both processes field the same ledger, so the guest gets a byte-identical
	# copy rather than a second seed that could drift.
	var copied := DirAccess.copy_absolute(_abs(host_save), _abs(client_save))
	check(copied == OK and FileAccess.file_exists(client_save),
		"The guest save is a copy of the host's (error %d)" % copied)
	if copied != OK or not FileAccess.file_exists(client_save):
		await _host_done()
		return

	var probe := PacketPeerUDP.new()
	check(probe.bind(0) == OK, "The fixture gets an available UDP port")
	var port := probe.get_local_port()
	probe.close()
	check(port > 0, "The fixture's port is real (%d)" % port)
	if port <= 0:
		await _host_done()
		return

	flow.active = true
	flow.host_campaign(port, "Host")
	var opened := await _wait_until(func(): return _world_is_ready() and flow.session != null and str(flow.warband_role()) == "host", 25.0)
	check(opened, "The campaign world opens as the host")
	if not opened:
		await _host_done()
		return
	world = current_scene
	_close_any_card()

	check(str(world.get("start_area")) == "checkpoint",
		"The host opens on the saved bookmark (%s)" % str(world.get("start_area")))
	var host_bodies := -1
	if world.get("bodies") is Array:
		host_bodies = (world.get("bodies") as Array).size()
	check(host_bodies == SQUAD_NAMES.size(),
		"The host fields the saved squad (%d)" % host_bodies)
	var host_wild = world.get("wilderness")
	var host_wolves := -1
	if host_wild != null and is_instance_valid(host_wild) and host_wild.has_method("wolves"):
		host_wolves = host_wild.wolves().size()
	check(host_wolves >= 6,
		"The host's wilderness band exists (%d wolves)" % host_wolves)
	check(flow.session.get("world") == world,
		"The session is attached to the campaign world")
	check(str(flow.warband_role()) == "host", "The host reports the host role")

	# The report must be at the RPC address before the guest can answer it.
	report = Report.new()
	report.name = REPORT_NAME
	report.submitted.connect(_store_report)
	root.add_child(report)
	check(root.get_node_or_null(REPORT_NAME) != null,
		"The host mounts /root/CoopReport before the guest starts")

	var child_args := PackedStringArray(["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "--script", get_script().resource_path,
		"--", "--coop-client", str(port), client_save])
	child_pid = OS.create_process(OS.get_executable_path(), child_args)
	check(child_pid > 0, "The guest process starts")
	if child_pid <= 0:
		await _host_done()
		return

	var joined := await _wait_until(
		func(): return flow.session != null and flow.session.peer_count() == 2, 25.0)
	check(joined, "A real guest process joins the campaign session")
	if not joined:
		await _host_done()
		return
	var client_peer := _client_peer()
	check(client_peer > 1, "The host sees the guest's peer id (%d)" % client_peer)
	if client_peer <= 1:
		await _host_done()
		return
	var seated := await _wait_until(func(): return flow.session != null and int(flow.session.ownership().get(client_peer, 0)) > 0, 15.0)
	check(seated, "The ownership map gives the guest a body")
	if not seated:
		await _host_done()
		return
	var guest_merc := int(flow.session.ownership().get(client_peer, -1))
	check(guest_merc > 0, "The guest's owned body is a real mercenary (%d)" % guest_merc)
	check(flow.session.controller.body_for_peer(client_peer) != null,
		"The host's controller has the guest's body")

	# --- what the guest fields --------------------------------------------
	report.probe.rpc_id(client_peer, "join", "")
	var probed := await _wait_until(func(): return reports.has("join"), 12.0)
	check(probed, "The guest answers the campaign probe")
	if not probed:
		await _host_done()
		return
	var join_report: Dictionary = reports["join"]
	if str(join_report.get("kind", "")) == "error":
		check(false, "The guest could not answer the probe: %s"
			% str(join_report.get("detail", "")))
		await _host_done()
		return
	_check_join_report(join_report)

	# --- the guest walks, the host's copy follows --------------------------
	if flow.session == null or flow.session.controller == null:
		check(false, "The host's session was torn down before the walk")
		await _host_done()
		return
	var guest_body = flow.session.controller.body_for_peer(client_peer)
	check(guest_body != null and is_instance_valid(guest_body),
		"The guest's body stands on the host's copy of the world")
	if guest_body != null and is_instance_valid(guest_body):
		var before: Vector3 = guest_body.global_position
		report.walk.rpc_id(client_peer, WALK_FRAMES)
		var moved := await _wait_physics_until(func(): return is_instance_valid(guest_body) and guest_body.global_position.distance_to(before) > 0.3, 3.0)
		var walked: float = guest_body.global_position.distance_to(before) \
			if is_instance_valid(guest_body) else -1.0
		check(moved, "The guest's walk reaches the host's copy (%s m)" % walked)

	# --- a mob dies on the host, the guest hears about it ------------------
	if not is_instance_valid(world):
		check(false, "The host's world was torn down before the kill")
		await _host_done()
		return
	var join_credits := int(join_report.get("credits", 0))
	var guard = _pick_guard()
	check(guard != null, "A living guard stands inside the replicated band")
	if guard != null:
		var guard_name := str(guard.name)
		# A lethal blow through the real damage funnel: the mob's own `defeated`
		# signal is what the session pays the guest from, so the test must not
		# call the death path directly.
		guard.set("health", 5.0)
		guard.take_damage(1000.0, 0)
		check(not bool(guard.get("alive")), "The chosen guard dies on the host")
		# Far enough from every squadmate that its own looting step cannot take
		# the piece on the same tick: what is under test is the host's loot
		# broadcast, not the vacuum's reach.
		var at: Vector3 = (guest_body.global_position
			if guest_body != null and is_instance_valid(guest_body)
			else TRAIL_POINT) + Vector3(12.0, 0.1, 12.0)
		var spawned = null
		if world.has_method("spawn_pickup"):
			spawned = world.spawn_pickup("sword_makeshift", at)
		check(spawned != null, "The host spawns a pickup the wire can carry")
		report.probe.rpc_id(client_peer, "kill", guard_name)
		var kill_seen := await _wait_until(func(): return reports.has("kill"), 12.0)
		check(kill_seen, "The guest reports after the kill")
		if kill_seen:
			_check_kill_report(reports["kill"], guard_name, join_credits)

	# --- the guest leaves, its body falls back -----------------------------
	report.leave.rpc_id(client_peer)
	var left := await _wait_until(
		func(): return flow.session != null and flow.session.peer_count() == 1, 15.0)
	check(left, "The host is alone again after the guest leaves")
	if left and flow.session != null and flow.session.controller != null:
		check(not flow.session.connected_peers().has(client_peer),
			"The departed peer is gone from the session")
		var freed := await _wait_until(func(): return flow.session == null or flow.session.controller == null or flow.session.controller.body_for_peer(client_peer) == null, 5.0)
		check(freed, "The departed guest no longer owns a body on the host")
		if flow.session != null and flow.session.controller != null:
			var fallback = flow.session.controller.body_of(guest_merc)
			check(fallback != null, "The departed body stays on the field")
			check(fallback != null and bool(fallback.get("is_bot")),
				"The departed body falls back to its own AI")
			check(not (warband.souls.occupied_by(guest_merc) > 0),
				"The router frees the departed body")
	await _host_done()

func _client_peer() -> int:
	if flow == null or flow.session == null:
		return 0
	for peer_id in flow.session.connected_peers():
		if int(peer_id) != 1:
			return int(peer_id)
	return 0

func _guest_body():
	if flow == null or flow.session == null or flow.session.controller == null:
		return null
	var peer := _client_peer()
	if peer <= 0:
		return null
	return flow.session.controller.body_for_peer(peer)

## The wolf nearest the guest's body. Wolves are the mobs the band puts on the
## first stretch of the trail, and one of them is always within the session's
## 70 m reach of a checkpoint squad. Any living, host-owned guard is a fallback.
func _pick_guard():
	if world == null or not is_instance_valid(world):
		return null
	var anchor: Vector3 = TRAIL_POINT
	var guest = _guest_body()
	if guest != null and is_instance_valid(guest):
		anchor = guest.global_position
	var best = null
	var best_distance := INF
	var wild = world.get("wilderness")
	if wild != null and is_instance_valid(wild) and wild.has_method("wolves"):
		for wolf in wild.wolves():
			if not is_instance_valid(wolf) or not bool(wolf.get("alive")):
				continue
			if bool(wolf.get("replica")):
				continue
			var distance: float = (wolf as Node3D).global_position.distance_to(anchor)
			if distance <= 70.0 and distance < best_distance:
				best = wolf
				best_distance = distance
	if best != null:
		return best
	var guards = world.get("guards")
	if guards is Array:
		for guard in guards:
			if not is_instance_valid(guard) or not bool(guard.get("alive")):
				continue
			if bool(guard.get("replica")) or not guard is Node3D:
				continue
			var distance: float = (guard as Node3D).global_position.distance_to(anchor)
			if distance <= 70.0 and distance < best_distance:
				best = guard
				best_distance = distance
	return best

func _check_join_report(data: Dictionary) -> void:
	check(str(data.get("kind", "")) == "probe",
		"The guest's join answer is a probe report (%s)" % str(data.get("kind", "")))
	check(str(data.get("role", "")) == "client",
		"The guest reports the client role (%s)" % str(data.get("role", "")))
	check(str(data.get("start_area", "")) == "checkpoint",
		"The guest opens on the saved bookmark (%s)" % str(data.get("start_area", "")))
	var bodies := int(data.get("bodies", -1))
	check(bodies >= 3 and bodies <= 4,
		"The guest fields the saved squad, 3-4 bodies (%d)" % bodies)
	var wolves := int(data.get("wolves", -1))
	check(wolves >= 6, "The guest's wilderness band holds six wolves or more (%d)" % wolves)
	var rows: Dictionary = data.get("guard_rows", {})
	check(rows.size() > 0, "The guest fields guards (%d)" % rows.size())
	var all_replicas := true
	for key in rows:
		var row: Dictionary = rows[key]
		if not bool(row.get("r", false)):
			all_replicas = false
			print("WARBAND_COOP_CAMPAIGN_FAIL  non-replica guard on the guest: ", key)
	check(all_replicas, "Every guard the guest fields is a replica")
	check(int(data.get("replica_count", -1)) == rows.size(),
		"The guest's replica count covers every guard (%d of %d)"
			% [int(data.get("replica_count", -1)), rows.size()])
	check(float(data.get("stamina_max", 0.0)) > 0.0,
		"The guest's HUD stamina has a real maximum (%s)"
			% str(data.get("stamina_max", 0.0)))
	check(int(data.get("ability_tiles", -1)) == 3,
		"The guest's HUD shows three ability tiles (%d)"
			% int(data.get("ability_tiles", -1)))
	check(not bool(data.get("card_open", true)),
		"The guest's opening tutorial card is not holding the tree")
	check(bool(data.get("sequencer_null", false)),
		"The guest has no opening tutorial sequencer")
	check(int(data.get("failures", 1)) == 0,
		"The guest's own checks all pass (%d failed)" % int(data.get("failures", 1)))

func _check_kill_report(data: Dictionary, guard_name: String, join_credits: int) -> void:
	var rows: Dictionary = data.get("guard_rows", {})
	check(rows.has(guard_name),
		"The guest knows the guard the host killed (%s)" % guard_name)
	if rows.has(guard_name):
		var row: Dictionary = rows[guard_name]
		check(float(row.get("h", 1.0)) <= 0.0,
			"The killed guard's replicated health is zero (%s: %s)"
				% [guard_name, str(row.get("h"))])
		check(not bool(row.get("a", true)),
			"The killed guard reaches the guest dead (%s)" % guard_name)
	var credits := int(data.get("credits", -1))
	check(credits > join_credits,
		"The guest's purse rose on a kill reward (%d -> %d)" % [join_credits, credits])
	check(credits > int(data.get("credits_base", 0)),
		"The guest's credited gold is above where it started (%d vs %d)"
			% [credits, int(data.get("credits_base", 0))])
	var pickups: Array = data.get("pickups", [])
	check(pickups.size() > 0,
		"At least one pickup reached the guest's world (%s)" % str(pickups))
	check(pickups.has("sword_makeshift"),
		"The pickup the host spawned is on the guest's ground (%s)" % str(pickups))
	check(int(data.get("failures", 1)) == 0,
		"The guest's own checks still pass (%d failed)" % int(data.get("failures", 1)))

func _store_report(payload: Dictionary) -> void:
	var tag := str(payload.get("tag", ""))
	if tag.is_empty():
		tag = str(payload.get("kind", ""))
	if tag.is_empty():
		tag = "report"
	reports[tag] = payload
	if str(payload.get("kind", "")) == "error":
		print("WARBAND_COOP_CLIENT_ERROR  ", str(payload.get("detail", "")),
			"  (tag=", tag, ")")

func _host_done() -> void:
	if child_pid > 0:
		# A guest that took `leave` exits on its own; one that is stuck is reaped.
		var grace := Time.get_ticks_msec() + 1500
		while OS.is_process_running(child_pid) and Time.get_ticks_msec() < grace:
			await create_timer(0.05).timeout
		if OS.is_process_running(child_pid):
			OS.kill(child_pid)
			# Windows keeps a killed process's files locked until it is reaped,
			# and the saves below must actually be gone when this exits.
			var reaped := Time.get_ticks_msec() + 2000
			while OS.is_process_running(child_pid) and Time.get_ticks_msec() < reaped:
				await create_timer(0.05).timeout
	if flow != null and flow.session != null:
		flow.session.leave()
	_remove(host_save)
	_remove(client_save)
	_remove(host_purse)
	_remove(client_purse)
	await process_frame
	print("WARBAND_COOP_CAMPAIGN_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

# --- client ----------------------------------------------------------------

func _client_run() -> void:
	deadline_ms = Time.get_ticks_msec() + int((WATCHDOG_SECONDS - 5.0) * 1000.0)
	var args := OS.get_cmdline_user_args()
	var index := args.find("--coop-client")
	check(index >= 0 and args.size() >= index + 3,
		"The guest leg was given a port and a save path")
	if index < 0 or args.size() < index + 3:
		quit(1)
		return
	var port := int(args[index + 1])
	client_save = args[index + 2]
	client_purse = client_save + ".purse"
	warband = root.get_node_or_null("Warband")
	state = root.get_node_or_null("PlayerState")
	flow = root.get_node_or_null("GameFlow")
	check(warband != null, "The guest's Warband autoload exists")
	check(state != null, "The guest's PlayerState autoload exists")
	check(flow != null, "The guest's GameFlow autoload exists")
	if warband == null or state == null or flow == null:
		quit(1)
		return
	check(flow.has_method("join_campaign"), "GameFlow.join_campaign() exists")
	if not flow.has_method("join_campaign"):
		quit(1)
		return
	check(FileAccess.file_exists(client_save),
		"The guest's save was handed to it (%s)" % client_save)

	state.save_path = client_purse
	state.reset(false)
	client_start_credits = int(state.credits)
	warband.save_path = client_save
	warband.reset_state()

	flow.active = true
	flow.join_campaign("127.0.0.1", port, "Guest")

	report = Report.new()
	report.name = REPORT_NAME
	report.probe_requested.connect(_on_probe)
	report.walk_requested.connect(_on_walk)
	report.leave_requested.connect(_on_leave)
	root.add_child(report)

	var opened := await _wait_until(func(): return _world_is_ready(), 25.0)
	check(opened, "The guest's campaign world opens")
	if not opened:
		_submit({"kind": "error", "tag": "fatal", "detail": "the world never opened"})
		await _client_done(1)
		return
	world = current_scene
	_close_any_card()

	var became_client := await _wait_until(
		func(): return str(flow.warband_role()) == "client", 5.0)
	check(became_client, "The guest reports the client role (%s)"
		% str(flow.warband_role()))
	var connected := await _wait_until(
		func(): return flow.session != null and flow.session.peer_count() == 2, 15.0)
	check(connected, "The guest connects to the campaign host")
	var seated := await _wait_until(func(): return flow.session != null and flow.session.controller != null and flow.session.controller.active_body() != null and flow.session.controller.merc_for_peer(flow.session.controller.local_peer_id) > 0, 15.0)
	check(seated, "The guest enters a body of its own")
	if not seated:
		_submit({"kind": "error", "tag": "fatal", "detail": "the guest never entered a body"})
		await _client_done(1)
		return

	var told := await _wait_until(func(): return leave_requested, 40.0)
	if not told:
		_submit({"kind": "error", "tag": "leave", "detail": "the host never said leave"})
	await _client_done(0 if told else 1)

## Answer one probe with everything the host needs to judge this tree. A kill
## probe waits for the named guard's replicated death (and the pickup that came
## with it) so the report is the settled picture, not a guess at one.
func _on_probe(tag: String, guard_name: String) -> void:
	if world == null or not is_instance_valid(world):
		_submit({"kind": "error", "tag": tag, "detail": "the guest has no world"})
		return
	if not guard_name.is_empty():
		await _wait_until(func(): return _guard_dead(guard_name) and int(state.credits) > client_start_credits, 6.0)
	if tag == "kill":
		await _wait_until(func(): return _pickup_items().size() > 0, 4.0)
	_submit(_probe_payload(tag))

func _probe_payload(tag: String) -> Dictionary:
	var stamina_max := -1.0
	var tiles := -1
	var hud = world.get("hud")
	if hud != null and is_instance_valid(hud):
		var bar = hud.stamina_bar() if hud.has_method("stamina_bar") else null
		if bar != null:
			stamina_max = float(bar.max_value)
		if hud.has_method("ability_tiles"):
			tiles = hud.ability_tiles().size()
	var rows: Dictionary = {}
	var replicas := 0
	var guards = world.get("guards")
	if guards is Array:
		for guard in guards:
			if not is_instance_valid(guard):
				continue
			var replica := bool(guard.get("replica"))
			rows[str(guard.name)] = {
				"h": float(guard.get("health")),
				"a": bool(guard.get("alive")),
				"r": replica,
			}
			if replica:
				replicas += 1
	var wolves := -1
	var wild = world.get("wilderness")
	if wild != null and is_instance_valid(wild) and wild.has_method("wolves"):
		wolves = wild.wolves().size()
	var card_open := false
	if world.get("card") != null and is_instance_valid(world.get("card")):
		var card = world.get("card")
		card_open = bool(card.is_open())
	var sequencer_null := true
	var sequencer_state := ""
	var camp = world.get("camp")
	if camp != null and is_instance_valid(camp):
		var sequencer = camp.get("sequencer")
		sequencer_null = sequencer == null or not is_instance_valid(sequencer)
		if not sequencer_null:
			sequencer_state = str(sequencer.state())
	var bodies := -1
	if world.get("bodies") is Array:
		bodies = (world.get("bodies") as Array).size()
	return {
		"kind": "probe",
		"tag": tag,
		"role": str(flow.warband_role()) if flow != null else "",
		"scene": str(world.scene_file_path),
		"start_area": str(world.get("start_area")),
		"bodies": bodies,
		"wolves": wolves,
		"guard_rows": rows,
		"guard_count": rows.size(),
		"replica_count": replicas,
		"stamina_max": stamina_max,
		"ability_tiles": tiles,
		"card_open": card_open,
		"sequencer_null": sequencer_null,
		"sequencer_state": sequencer_state,
		"credits": int(state.credits) if state != null else -1,
		"credits_base": client_start_credits,
		"pickups": _pickup_items(),
	}

func _guard_dead(guard_name: String) -> bool:
	if world == null:
		return false
	var guards = world.get("guards")
	if not guards is Array:
		return false
	for guard in guards:
		if is_instance_valid(guard) and str(guard.name) == guard_name:
			return not bool(guard.get("alive")) or float(guard.get("health")) <= 0.0
	return false

func _pickup_items() -> Array:
	var items: Array = []
	if world == null:
		return items
	var pickups = world.get("pickups")
	if pickups is Array:
		for pickup in pickups:
			if is_instance_valid(pickup):
				items.append(str(pickup.get("item_id")))
	return items

## A walk frame on the guest's own body. The world's own `_drive` would send a
## zero frame between every one of ours, so the local drive is switched off for
## the duration and the frames below are the whole stream the host sees.
func _on_walk(frames: int) -> void:
	if world == null or flow == null or flow.session == null:
		_submit({"kind": "error", "tag": "walk", "detail": "the guest has no session"})
		return
	var controller = flow.session.controller
	if controller == null:
		_submit({"kind": "error", "tag": "walk", "detail": "the session has no controller"})
		return
	# `WarbandSession` carries the one `PossessionSync` on the controller.
	var sync = controller.sync
	if sync == null or not sync.has_method("send_move"):
		_submit({"kind": "error", "tag": "walk",
			"detail": "the controller exposes no PossessionSync.send_move()"})
		return
	var body = controller.active_body()
	if body == null or not is_instance_valid(body):
		_submit({"kind": "error", "tag": "walk", "detail": "the guest has no body to walk"})
		return
	controller.input_enabled = false
	var aim: Vector3 = body.global_position + Vector3(3.0, 1.0, 0.0)
	var origin: Vector3 = body.global_position
	var sent := 0
	for index in frames:
		if not is_instance_valid(body) or not bool(body.get("alive")):
			break
		sync.send_move(Vector2(1.0, 0.0), false, aim)
		sent += 1
		await physics_frame
	controller.input_enabled = true
	var travelled: float = body.global_position.distance_to(origin) \
		if is_instance_valid(body) else -1.0
	_submit({"kind": "walk", "tag": "walk", "frames": frames, "sent": sent,
		"predicted": travelled})

func _on_leave() -> void:
	leave_requested = true
	if flow != null and flow.session != null:
		flow.session.leave()

func _submit(payload: Dictionary) -> void:
	if report == null or not is_instance_valid(report):
		return
	payload["checks"] = checks
	payload["failures"] = failures
	report.submit.rpc_id(1, payload)

func _client_done(code: int) -> void:
	if flow != null and flow.session != null:
		flow.session.leave()
	_remove(client_purse)
	await process_frame
	quit(code if failures == 0 else 1)
