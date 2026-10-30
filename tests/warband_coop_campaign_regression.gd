extends SceneTree
## Two real processes play one campaign from one warband: the host opens its own
## world with `GameFlow.host_campaign()`, a guest child joins it with
## `join_campaign()`, and everything the shared pool promises has to hold.
##
## Nothing is built by hand. The host writes a warband save holding a two-body
## squad on the trail bookmark and opens it; the guest has a campaign of its own
## on disk (one mercenary called Own Man) and must get it back untouched when the
## session ends. The guest is sent the host's warband, fields the host's bodies,
## and is seated by the host in the first free one.
##
## Then the rule the whole mode hangs on: with one body left, the soul already
## inside it keeps it and the other soul watches it. The guest's body is finished,
## the host keeps its own, the guest's panel says who it is watching, and a body
## that comes free afterwards goes to the soul that had been waiting.
##
## The host leg runs by default; the guest is the same script started with
## `-- --coop-client <port> <savepath>`.

const WORLD_SCENE := "res://scenes/warband_world.tscn"
const REPORT_NAME := "CoopReport"
const TRAIL_POINT := Vector3(6.0, 0.0, -90.0)
## The two bodies the host's save stands on the trail.
const SQUAD_NAMES := ["Aldous", "Brine"]
## The body a third mercenary brings onto the field while the guest waits for one.
const LATE_NAME := "Bren"
## Whole-run budget: two real world builds and a handful of waits.
const WATCHDOG_SECONDS := 55.0

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
var guest_left := false
## Every failed guest check, carried home in the report so the host's log shows it.
var failed_checks: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		failed_checks.append(message)
		push_error(message)
		print("WARBAND_COOP_CAMPAIGN_FAIL  ", message)

# --- the shared RPC node ---------------------------------------------------

class Report:
	extends Node
	signal submitted(payload: Dictionary)
	signal probe_requested(tag: String)
	signal finish_requested()

	@rpc("any_peer", "call_remote", "reliable")
	func submit(payload: Dictionary) -> void:
		submitted.emit(payload)

	@rpc("authority", "call_remote", "reliable")
	func probe(tag: String) -> void:
		probe_requested.emit(tag)

	@rpc("authority", "call_remote", "reliable")
	func finish() -> void:
		finish_requested.emit()

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

## A tip left on the screen from the opening would follow a bodiless soul into
## its first fight: put it away.
func _close_any_card() -> void:
	if world == null or not is_instance_valid(world):
		return
	var tips = world.get("tips")
	if tips != null and is_instance_valid(tips):
		tips.hide()

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
	check(warband != null and state != null and flow != null,
		"The Warband, PlayerState and GameFlow autoloads exist")
	if warband == null or state == null or flow == null:
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

	for merc_name in SQUAD_NAMES:
		var merc_id: int = warband.add_mercenary(str(merc_name))
		var equipped: Dictionary = warband.roster.equip(merc_id, "main", "sword_short")
		check(bool(equipped.get("ok", false)),
			"Mercenary %s takes its shortsword" % str(merc_name))
	warband.save_checkpoint("trail_start", "trail", TRAIL_POINT, "COOP")
	check(warband.has_checkpoint(), "The host's save holds the trail bookmark")
	check(FileAccess.file_exists(host_save), "The host save was written")
	var host_roster: Array[int] = warband.roster.ids()
	check(host_roster.size() == SQUAD_NAMES.size(), "The save holds the two-body squad (%d)"
		% host_roster.size())

	var probe := PacketPeerUDP.new()
	check(probe.bind(0) == OK, "The fixture gets an available UDP port")
	var port := probe.get_local_port()
	probe.close()
	if port <= 0:
		await _host_done()
		return

	flow.active = true
	flow.host_campaign(port, "Host", flow.HOST_CHECKPOINT)
	var opened := await _wait_until(func(): return _world_is_ready() and flow.session != null \
		and str(flow.warband_role()) == "host", 25.0)
	check(opened, "HOST GAME opens the campaign world as the host")
	if not opened:
		await _host_done()
		return
	world = current_scene
	_close_any_card()
	check(str(world.get("start_area")) == "checkpoint",
		"The host opens on the saved bookmark (%s)" % str(world.get("start_area")))
	var host_bodies: Array = world.get("bodies") if world.get("bodies") is Array else []
	check(host_bodies.size() == SQUAD_NAMES.size(),
		"The host fields the saved squad (%d)" % host_bodies.size())
	check(flow.session.world == world, "The session is attached to the campaign world")
	check(flow.session.shared_warband, "The campaign session shares one warband")

	report = Report.new()
	report.name = REPORT_NAME
	report.submitted.connect(_store_report)
	root.add_child(report)

	var child_args := PackedStringArray(["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "--script", get_script().resource_path,
		"--", "--coop-client", str(port), client_save])
	child_pid = OS.create_process(OS.get_executable_path(), child_args)
	check(child_pid > 0, "The guest process starts")
	if child_pid <= 0:
		await _host_done()
		return

	var joined := await _wait_until(
		func(): return flow.session != null and flow.session.peer_count() == 2, 30.0)
	check(joined, "A real guest process joins the campaign session")
	if not joined:
		await _host_done()
		return
	var guest_peer := _client_peer()
	check(guest_peer > 1, "The host sees the guest's peer id (%d)" % guest_peer)
	if guest_peer <= 1:
		await _host_done()
		return

	# --- one pool between them ---------------------------------------------
	var seated := await _wait_until(
		func(): return int(flow.session.ownership().get(guest_peer, 0)) > 0, 30.0)
	check(seated, "HOST GAME seats the guest in a body")
	if not seated:
		await _host_done()
		return
	var guest_merc := int(flow.session.ownership().get(guest_peer, -1))
	check(host_roster.has(guest_merc),
		"The guest wears one of the host's mercenaries (%d)" % guest_merc)
	check(int(flow.session.ownership().get(1, 0)) > 0
		and int(flow.session.ownership().get(1, 0)) != guest_merc,
		"The host keeps a body of its own")
	var host_merc := int(flow.session.ownership().get(1, -1))
	check(flow.session.controller.body_for_peer(guest_peer) != null,
		"The host's field holds the guest's body")

	# --- killing the guest's body with the last one left -------------------
	# A blow on a downed campaign body finishes it. The soul inside is ejected,
	# and with the host's own body the only one left standing, the guest watches.
	var guest_actor = flow.session.controller.body_of(guest_merc)
	var host_actor = flow.session.controller.body_of(host_merc)
	check(guest_actor != null and is_instance_valid(guest_actor), "The guest's body stands")
	check(host_actor != null and is_instance_valid(host_actor), "The host's body stands")
	if guest_actor != null and is_instance_valid(guest_actor) and host_actor != null:
		guest_actor.enter_downed(host_actor.slot)
		guest_actor.take_damage(200.0, host_actor.slot)
		if not bool(guest_actor.get("alive")):
			check(true, "The guest's body is finished")
		else:
			check(false, "The guest's body is finished (%s health, downed %s)"
				% [str(guest_actor.get("health")), str(guest_actor.get("downed"))])
	var ejected := await _wait_until(
		func(): return int(flow.session.ownership().get(guest_peer, -1)) == 0, 15.0)
	check(ejected, "The finished body's soul is let go (%s)"
		% str(flow.session.ownership().get(guest_peer, -1)))
	if not ejected:
		await _host_done()
		return
	check(int(flow.session.ownership().get(1, 0)) == host_merc,
		"The soul already inside the last body keeps it")
	check(host_actor != null and is_instance_valid(host_actor) and bool(host_actor.alive),
		"The last body is still standing with its soul inside")
	check(flow.session.controller.merc_for_peer(guest_peer) <= 0,
		"The host's field no longer seats the guest")
	check(not flow.session.controller.possessing_peers().has(guest_peer),
		"The guest is a watcher on the host's field")

	report.probe.rpc_id(guest_peer, "watch")
	var watch_seen := await _wait_until(func(): return reports.has("watch"), 15.0)
	check(watch_seen, "The guest reports what it is watching")
	if watch_seen:
		var data: Dictionary = reports["watch"]
		check(int(data.get("own_merc", 1)) <= 0,
			"The guest's soul is in no body (%s)" % str(data.get("own_merc")))
		check(int(data.get("watching", -1)) == host_merc,
			"The guest watches the body somebody else is inside (%s)" % str(data.get("watching")))
		check(str(data.get("watching_holder", "")) == "Host",
			"The guest's panel names who has it (%s)" % str(data.get("watching_holder")))
		check(bool(data.get("mission_watch", false)),
			"The guest's panel says it is watching instead of showing a dead soul")
		check(str(data.get("role", "")) == "client" and bool(data.get("lent", false)),
			"The guest is still playing the host's lent warband")
		check(int(data.get("failures", 1)) == 0,
			"The guest's own checks all pass (%d failed): %s"
				% [int(data.get("failures", 1)), str(data.get("failed", []))])

	# --- a body that comes free goes to the soul that waited ---------------
	var late_id: int = warband.add_mercenary(LATE_NAME)
	warband.roster.equip(late_id, "main", "sword_short")
	var late_posts: Array[Vector3] = [TRAIL_POINT + Vector3(2.0, 0.0, 0.0)]
	var late_wanted: Array[int] = [late_id]
	var late_bodies: Array = flow.session.controller.spawn_mercenaries(late_posts, true, late_wanted)
	check(late_bodies.size() == 1, "The host fields the third body (%d)" % late_bodies.size())
	check(warband.roster.has(late_id), "The warband takes a third body (%d)" % late_id)
	var reseated := await _wait_until(
		func(): return int(flow.session.ownership().get(guest_peer, 0)) == late_id, 20.0)
	check(reseated, "The waiting soul takes the next free body (%s)"
		% str(flow.session.ownership().get(guest_peer, 0)))
	check(int(flow.session.ownership().get(1, 0)) == host_merc,
		"The host was never moved out of its body")

	# --- the guest leaves, its own campaign comes back ---------------------
	report.finish.rpc_id(guest_peer)
	var left := await _wait_until(
		func(): return flow.session != null and flow.session.peer_count() == 1, 20.0)
	check(left, "The host is alone again after the guest leaves")
	if left and flow.session != null and flow.session.controller != null:
		check(not flow.session.connected_peers().has(guest_peer),
			"The departed peer is gone from the session")
		var freed := await _wait_until(
			func(): return flow.session == null or flow.session.controller == null \
				or flow.session.controller.body_for_peer(guest_peer) == null, 5.0)
		check(freed, "The departed guest no longer owns a body on the host")
		check(warband.souls.occupied_by(late_id) == 0, "The router frees the departed body")
		check(warband.roster.has(late_id), "The host's warband keeps the body it took on")
	await _host_done()

func _client_peer() -> int:
	if flow == null or flow.session == null:
		return 0
	for peer_id in flow.session.connected_peers():
		if int(peer_id) != 1:
			return int(peer_id)
	return 0

func _store_report(payload: Dictionary) -> void:
	var tag := str(payload.get("tag", payload.get("kind", "report")))
	reports[tag] = payload
	if str(payload.get("kind", "")) == "error":
		print("WARBAND_COOP_CLIENT_ERROR  ", str(payload.get("detail", "")), "  (tag=", tag, ")")

func _host_done() -> void:
	if child_pid > 0:
		var grace := Time.get_ticks_msec() + 1500
		while OS.is_process_running(child_pid) and Time.get_ticks_msec() < grace:
			await create_timer(0.05).timeout
		if OS.is_process_running(child_pid):
			OS.kill(child_pid)
			var reaped := Time.get_ticks_msec() + 2000
			while OS.is_process_running(child_pid) and Time.get_ticks_msec() < reaped:
				await create_timer(0.05).timeout
	if flow != null and flow.session != null:
		flow.leave_warband()
	if current_scene != null:
		current_scene.queue_free()
	_remove(host_save)
	_remove(client_save)
	_remove(host_purse)
	_remove(client_purse)
	await process_frame
	print("WARBAND_COOP_CAMPAIGN_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

# --- client ----------------------------------------------------------------

func _client_run() -> void:
	deadline_ms = Time.get_ticks_msec() + int((WATCHDOG_SECONDS - 4.0) * 1000.0)
	var args := OS.get_cmdline_user_args()
	var index := args.find("--coop-client")
	check(index >= 0 and args.size() >= index + 2, "The guest leg was given a port and a save path")
	if index < 0 or args.size() < index + 2:
		quit(1)
		return
	var port := int(args[index + 1])
	client_save = args[index + 2]
	client_purse = client_save + ".purse"
	warband = root.get_node_or_null("Warband")
	state = root.get_node_or_null("PlayerState")
	flow = root.get_node_or_null("GameFlow")
	check(warband != null and state != null and flow != null,
		"The guest's autoloads exist")
	if warband == null or state == null or flow == null:
		quit(1)
		return

	# A campaign of its own, on disk: the guest must get exactly this back.
	state.save_path = client_purse
	state.reset(false)
	warband.save_path = client_save
	warband.reset_state()
	warband.add_mercenary("Own Man")
	warband.save_state()
	check(FileAccess.file_exists(client_save), "The guest's own campaign was written")
	var own_text := FileAccess.get_file_as_string(client_save)

	flow.active = true
	flow.join_campaign("127.0.0.1", port, "Guest")

	report = Report.new()
	report.name = REPORT_NAME
	report.probe_requested.connect(_on_probe)
	report.finish_requested.connect(_on_finish)
	root.add_child(report)

	var opened := await _wait_until(func(): return _world_is_ready(), 25.0)
	check(opened, "The guest's campaign world opens on the host's warband")
	if not opened:
		_submit({"kind": "error", "tag": "fatal", "detail": "the world never opened"})
		await _client_done(1)
		return
	world = current_scene
	_close_any_card()

	check(str(flow.warband_role()) == "client", "The guest reports the client role (%s)"
		% str(flow.warband_role()))
	check(str(world.get("start_area")) == "guest", "The guest opens as a guest (%s)"
		% str(world.get("start_area")))
	check(bool(warband.lent), "The guest plays the host's lent warband")
	check(warband.roster.count() == SQUAD_NAMES.size(),
		"The guest fields the host's roster (%d)" % warband.roster.count())
	check(FileAccess.get_file_as_string(client_save) == own_text,
		"The borrowed warband never touches the guest's own save")
	var bodies: Array = world.get("bodies") if world.get("bodies") is Array else []
	check(bodies.size() == SQUAD_NAMES.size(),
		"The guest fields the host's bodies (%d)" % bodies.size())
	var guest_guards: Array = world.get("guards") if world.get("guards") is Array else []
	var all_replicas := not guest_guards.is_empty()
	for guard in guest_guards:
		if not bool(guard.get("replica")):
			all_replicas = false
	check(all_replicas, "Every mob the guest fields is a replica (%d)" % guest_guards.size())

	var seated := await _wait_until(func(): return _own_merc() > 0, 25.0)
	check(seated, "The host seats the guest's soul in a body (%s)" % str(_own_merc()))
	if not seated:
		_submit({"kind": "error", "tag": "seat", "detail": "no body after the host's map: %s"
			% str(_probe_payload("seat"))})
		await _client_done(1)
		return
	check(_own_merc() != -1 and int(flow.session.ownership().get(_own_peer(), 0)) == _own_merc(),
		"The guest's map agrees with its own body")

	var told := await _wait_until(func(): return guest_left, int((WATCHDOG_SECONDS - 30.0) * 1000.0))
	if not told:
		_submit({"kind": "error", "tag": "finish", "detail": "the host never dismissed the guest"})
	await _client_done(0 if told else 1)

func _own_peer() -> int:
	var id := root.multiplayer.get_unique_id()
	return id if id > 0 else 1

func _own_merc() -> int:
	if world == null or flow == null or flow.session == null or flow.session.controller == null:
		return -1
	return int(flow.session.controller.merc_for_peer(_own_peer()))

func _watching_merc() -> int:
	var body = flow.session.controller.watching() if flow.session != null \
		and flow.session.controller != null else null
	if body == null or not is_instance_valid(body):
		return -1
	return int(flow.session.controller.merc_of(body))

func _on_probe(tag: String) -> void:
	if world == null or not is_instance_valid(world):
		_submit({"kind": "error", "tag": tag, "detail": "the guest has no world"})
		return
	if tag == "watch":
		# The map that took this soul's body away has just landed; the eye and the
		# body panel settle on the next physics frame, so the report is read after
		# a couple of them rather than on the frame the map arrived.
		for _beat in 4:
			await physics_frame
		await process_frame
	_submit(_probe_payload(tag))

func _probe_payload(tag: String) -> Dictionary:
	var controller = flow.session.controller if flow.session != null else null
	var watching := _watching_merc()
	var holder := ""
	var lines: Array[String] = []
	var hud = world.get("hud")
	if hud != null and is_instance_valid(hud):
		if hud.has_method("body_lines"):
			lines = hud.body_lines()
		if controller != null:
			holder = str(flow.session.name_of(controller.watched_peer()))
	return {
		"kind": "probe",
		"tag": tag,
		"role": str(flow.warband_role()) if flow != null else "",
		"start_area": str(world.get("start_area")),
		"lent": bool(warband.lent) if warband != null else false,
		"roster": warband.roster.count() if warband != null else -1,
		"own_merc": _own_merc(),
		"watching": watching,
		"watching_holder": holder,
		"mission_watch": lines.size() >= 2 and String(lines[1]).contains("no body is free"),
		"body_lines": lines,
		"failed": failed_checks,
	}

func _on_finish() -> void:
	guest_left = true
	if flow != null:
		flow.leave_warband()

func _submit(payload: Dictionary) -> void:
	if report == null or not is_instance_valid(report):
		return
	payload["checks"] = checks
	payload["failures"] = failures
	report.submit.rpc_id(1, payload)

func _client_done(code: int) -> void:
	# The session is over: the guest's own campaign must be the one it wrote.
	if warband != null and not flow.session:
		check(not bool(warband.lent), "The loan ends with the session")
		check(warband.roster.count() == 1 and warband.roster.name_of(warband.roster.ids()[0]) == "Own Man",
			"The guest's own campaign comes back (%d bodies)" % warband.roster.count())
	_submit({"kind": "done", "tag": "done"})
	await process_frame
	if flow != null and flow.session != null:
		flow.leave_warband()
	_remove(client_purse)
	await process_frame
	quit(code if failures == 0 else 1)
