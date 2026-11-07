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
const DollScript = preload("res://scripts/warband/warband_paperdoll.gd")
const AltarMenuScript = preload("res://scripts/warband/altar_menu.gd")
const State = preload("res://scripts/player_state.gd")
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
	signal strike_requested(point: Vector3)
	signal finish_requested()

	@rpc("any_peer", "call_remote", "reliable")
	func submit(payload: Dictionary) -> void:
		submitted.emit(payload)

	@rpc("authority", "call_remote", "reliable")
	func probe(tag: String) -> void:
		probe_requested.emit(tag)

	@rpc("authority", "call_remote", "reliable")
	func strike(point: Vector3) -> void:
		strike_requested.emit(point)

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
	# A spare on the shelf: the guest's own press is what has to wear it. And one
	# warden's ichor beside it: the guest's press at the altar spends the pool the
	# whole party shares.
	warband.stash.add("sword_arming", 1)
	warband.stash.add("ichor_vial", 1)
	warband.save_checkpoint("trail_start", "trail", TRAIL_POINT, "COOP")
	check(warband.has_checkpoint(), "The host's save holds the trail bookmark")
	check(FileAccess.file_exists(host_save), "The host save was written")
	var host_roster: Array[int] = warband.roster.ids()
	check(host_roster.size() == SQUAD_NAMES.size(), "The save holds the two-body squad (%d)"
		% host_roster.size())

	# The whole session runs over a link that is not instantaneous. Localhost is
	# the one link on which prediction, interpolation and the hitbox rewind can
	# all be wrong and still agree: at 0.1 ms the past and the present are the
	# same frame. 60 ms each way with 20 ms of jitter is a cable or a Tailscale
	# path, and it is the only way this test measures netcode rather than luck.
	# Set before the socket opens, because the session reads it on `setup`, and
	# inherited by the guest process this test spawns.
	OS.set_environment("IRONWOOD_COOP_LAG", "0.06")
	OS.set_environment("IRONWOOD_COOP_JITTER", "0.02")
	# And it loses pose packets, the way a bad link does: the streams marked
	# `lossy` are exactly the ones the wire already sends unreliably (snapshots,
	# the mob stream, missiles, move frames), so a death, a leave or a combat verb
	# is still never thrown away. Loss is what a `stale` copy, a re-sync and a
	# replayed input frame are for; latency alone does not exercise them.
	OS.set_environment("IRONWOOD_COOP_DROP", "0.05")

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

	# The host's map is one reliable RPC in front of the guest's own controller:
	# wait until the seat has actually landed there before asking that soul to
	# press a key, or the press is made by a spectator with no body.
	report.probe.rpc_id(guest_peer, "seat")
	var guest_ready := await _wait_until(func(): return reports.has("seat") \
		and bool((reports["seat"] as Dictionary).get("own_body", false)), 10.0)
	check(guest_ready, "The guest's own world seats it in the body the host gave it")

	# --- the purse moves without the books ---------------------------------
	# A kill's gold changes nothing in the roster or the stash, so it must not cost
	# every guest a whole campaign reload: one number goes out on its own.
	warband.award_gold(37)
	await create_timer(0.4).timeout
	report.probe.rpc_id(guest_peer, "purse")
	var purse_seen := await _wait_until(func(): return reports.has("purse"), 10.0)
	check(purse_seen, "The guest answers for the host's purse")
	if purse_seen:
		check(int((reports["purse"] as Dictionary).get("gold", -1)) == warband.gold(),
			"The guest's purse is the host's (%s vs %s)" % [
				str((reports["purse"] as Dictionary).get("gold", -1)), str(warband.gold())])

	# --- a guest's press wears gear on the host's books --------------------
	# The paperdoll on a guest is the host's warband: the verb travels as a
	# request, the host runs the same verb on its own books, and the guest sees
	# the result when the copy comes back. The guest checks both directions on
	# its own copy (a lent copy only ever changes with a mirror); here the host
	# checks that the requests landed on its books and left nothing half-done.
	var geared := await _wait_until(func(): return reports.has("gear"), 20.0)
	check(geared, "The guest reports its gear press")
	if geared:
		var data: Dictionary = reports["gear"]
		var geared_merc := int(data.get("merc", 0))
		check(host_roster.has(geared_merc), "The guest dressed one of the host's bodies (%d)"
			% geared_merc)
		check(str(warband.roster.equipped_of(geared_merc).get("main", "")) != "sword_arming",
			"and the host took the spare back off (%s)"
				% str(warband.roster.equipped_of(geared_merc).get("main", "")))
		check(warband.stash.pooled_count("sword_arming") == 1,
			"with the spare back on the host's shelf (%d)"
				% warband.stash.pooled_count("sword_arming"))

	# --- a guest's press works the altar on the host's books ----------------
	# The altar is the same shared books as the paperdoll: the request names the
	# copy, the host throws the die and pays the vial out of the pool both players
	# draw on, and the weld comes back on the mirror. The guest checks its own
	# copy and the mirror; here the host checks the pool it paid from and the
	# ledger the guest is reading.
	var rited := await _wait_until(func(): return reports.has("rite"), 20.0)
	check(rited, "The guest reports its altar press")
	if rited:
		var rite: Dictionary = reports["rite"]
		check(warband.stash.pooled_count("ichor_vial") == 0,
			"the pooled vial left the host's stash (%d)"
				% warband.stash.pooled_count("ichor_vial"))
		var rite_copy := int(rite.get("copy", -1))
		check(warband.annoints.count("sword_arming", rite_copy) == int(rite.get("count", -1)),
			"and the host's ledger is the count the guest reads (%d vs %d)" % [
				warband.annoints.count("sword_arming", rite_copy),
				int(rite.get("count", -1))])

	# The rest of the test measures the wire, not the wood: a cultist that happens
	# to stand inside its reach would stagger the body between a press and its
	# blow, and the band's own sweep would claim the corpse and the drop before
	# the guest's press. Replicas still snapshot; they just do not think, and the
	# escort holds its ground.
	for guard in world.get("guards"):
		if is_instance_valid(guard):
			guard.set("replica", true)
	var squad = world.get("squad")
	if squad != null:
		squad.following = false

	# --- the wood's own mobs run on the guest's screen ----------------------
	# A warden the host moves has to move here too, from the snapshot alone: the
	# guest runs no brain and steps no body of its own, so a copy that never
	# arrives is a mob standing still while the host's walks away. The warren is
	# built on both machines with the same names, which is what lets the state
	# find it.
	var combat_actor = flow.session.controller.body_for_peer(guest_peer)
	var warden = _warren_body(world, 0)
	check(warden != null, "The host fields the warcamp's wardens")
	if warden != null and combat_actor != null and is_instance_valid(combat_actor):
		# Far enough that a warden that wakes up has nobody in its sight (its own
		# reach is 30 m) and cannot spend the test hitting the guest's body, and
		# still inside the session's 70 m replication band.
		var first_at: Vector3 = (combat_actor as Node3D).global_position + Vector3(40.0, 0.0, 0.0)
		warden.global_position = first_at
		warden.home = first_at
		# The fixture's body is the stream, not a fight: a replica on the host
		# runs no brain, so it cannot wander out from under the comparison while
		# the guest is being measured.
		warden.set("replica", true)
		warden.call("rest", true)
		# The host polls its mob stream at 15 Hz; give the batch that names this
		# body time to reach the guest before asking it where the copy stands.
		await create_timer(0.6).timeout
		var entries: Array = flow.session.collect_mob_entries(70.0)
		var named := false
		for entry in entries:
			if str(entry[0]) == str((warden as Node).name):
				named = true
		check(named, "The host's mob stream names the warden")
		# Where the body actually came to rest, not the point the test asked for:
		# a capsule dropped inside a rock is depenetrated on the next move.
		var host_first: Vector3 = warden.global_position
		reports.erase("mob")
		report.probe.rpc_id(guest_peer, "mob")
		var first_seen := await _wait_until(func(): return reports.has("mob"), 10.0)
		check(first_seen, "The guest's copy of the warden answers")
		var first_pos := Vector3.ZERO
		var first_tick := -1
		if first_seen:
			var data: Dictionary = reports["mob"]
			first_tick = int(data.get("stream_tick", -1))
			first_pos = Vector3(data.get("pos", [0.0, 0.0, 0.0])[0],
				data.get("pos", [0.0, 0.0, 0.0])[1], data.get("pos", [0.0, 0.0, 0.0])[2])
			check(bool(data.get("replica", false)),
				"The guest's warden is a replica, not a second brain")
			check(not bool(data.get("resting", true)),
				"The guest's warden leaves the rest its build put it under")
			check(first_pos.distance_to(host_first) < 1.5,
				"The guest's warden stands where the host put it (%s vs %s)"
					% [str(first_pos), str(host_first)])
		var second_at := first_at + Vector3(0.0, 0.0, 2.5)
		warden.global_position = second_at
		await create_timer(0.7).timeout
		var host_second: Vector3 = warden.global_position
		reports.erase("mob")
		report.probe.rpc_id(guest_peer, "mob")
		var moved_seen := await _wait_until(func(): return reports.has("mob"), 10.0)
		check(moved_seen, "The guest's copy answers after the warden moves")
		if moved_seen:
			var moved: Dictionary = reports["mob"]
			# The mob stream is labelled with the physics clock, not with a packet
			# counter: two probes 0.7 s apart must show ~0.7 s of ticks. Numbered one
			# per batch this read ~10; it reads ~42 now. That is the whole difference
			# between a label that maps to elapsed time and one that lies after every
			# hitch.
			var span := int(moved.get("stream_tick", -1)) - first_tick
			check(span >= 30,
				"The mob stream's tick is the physics clock (%d ticks across 0.7 s)" % span)
			var moved_pos := Vector3(moved.get("pos", [0.0, 0.0, 0.0])[0],
				moved.get("pos", [0.0, 0.0, 0.0])[1], moved.get("pos", [0.0, 0.0, 0.0])[2])
			check(moved_pos.distance_to(host_second) < 1.5,
				"The guest's warden runs on the snapshot alone (%s vs %s)"
					% [str(moved_pos), str(host_second)])
			check(moved_pos.distance_to(host_first) > 1.0,
				"The guest's warden actually moved (%s vs %s)"
					% [str(moved_pos), str(host_first)])
		# The host stops naming the body - the kill that missed a datagram, or
		# the body that walked out of the 70 m band. A body leaving a peer's
		# stream is named once, reliably, so the guest's copy leaves the screen
		# instead of standing where the host no longer has one. The wait is 1.1 s,
		# inside the 2 s stale clock on purpose: a copy still waiting on a timeout
		# would be standing here, so what is measured is the word from the host.
		(world.get("guards") as Array).erase(warden)
		await create_timer(1.1).timeout
		reports.erase("mob")
		report.probe.rpc_id(guest_peer, "mob_gone")
		var gone_seen := await _wait_until(func(): return reports.has("mob_gone"), 5.0)
		check(gone_seen, "The guest's copy answers after the host stops naming it")
		if gone_seen:
			var gone: Dictionary = reports["mob_gone"]
			check(not bool(gone.get("visible", true)),
				"The copy the host stops streaming leaves the screen")
			check(not bool(gone.get("stale", true)),
				"put down by the stream, not left to the stale clock")

	# --- the guest's verbs land on the host's field ------------------------
	# A body the host alone fields stands in front of the guest. The guest
	# presses its own attack, and the host resolves the blow, books the corpse
	# and drops the steel; then the guest's K and its corpse screen take a piece
	# each. This is the whole guest half of the campaign in one pass: an intent
	# becomes a hit, a death becomes a record, and a record becomes a take.
	check(combat_actor != null and is_instance_valid(combat_actor),
		"The guest's body stands before the fight")
	var dummy = null
	var drop = null
	var corpse_id := 0
	if combat_actor != null and is_instance_valid(combat_actor):
		var WatcherScript = load("res://scripts/warband/cage_watcher.gd")
		dummy = WatcherScript.new()
		dummy.name = "CoopDummy"
		dummy.mob_id = "hollow_warden"
		dummy.health_pool = 8.0
		var forward: Vector3 = -(combat_actor as Node3D).global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var point: Vector3 = (combat_actor as Node3D).global_position + forward * 1.5
		dummy.position = point
		world.add_child(dummy)
		dummy.global_position = point
		dummy.set("replica", true)
		# No arm: the only drop near the guest is the piece the host spawns for
		# the K check, so `_nearest_pickup` cannot pick another body's steel.
		dummy.defeated.connect(Callable(world, "_on_enemy_defeated"))
		world.guards.append(dummy)
		# A few frames so the rewind has recorded the body and the guest has a
		# playout tick to name.
		for _beat in 4:
			await physics_frame
		reports.erase("strike")
		report.strike.rpc_id(guest_peer, point + Vector3.UP * 1.2)
		var press_seen := await _wait_until(func(): return reports.has("strike"), 5.0)
		check(press_seen and bool((reports.get("strike", {}) as Dictionary).get("sent", false)),
			"The guest's own press is sent from the body it was given")
		# The tick a guest names is read back by the host against the bodies that
		# guest was looking at. Its clock has to trail the newest snapshot by the
		# delay its own eye draws a remote body at, or every correction is short:
		# a blow that looked landed is refused, a body is hit where it had already
		# stopped being. Left on the clock's default this read 1.5 ticks against
		# the body's 7.2 - a hundred milliseconds of the wrong moment.
		if press_seen:
			var seen: Dictionary = reports.get("strike", {})
			var clock_delay := float(seen.get("clock_delay", -1.0))
			var replica_delay := float(seen.get("replica_delay", -1.0))
			var newest := int(seen.get("newest", -1))
			var view := int(seen.get("view", -1))
			check(replica_delay > 0.0 and absf(clock_delay - replica_delay) < 1.0,
				"The tick a guest names is the tick it draws (%.2f vs %.2f)"
					% [clock_delay, replica_delay])
			check(newest >= 0 and view >= 0 and float(newest - view) >= 5.0,
				"and it trails the newest snapshot by that delay (%d vs %d)"
					% [newest, view])
			# The link really was on, both ways: the guest's intents sat in its
			# uplink queue and were released, or this run proves nothing about
			# latency. The host's own count is checked with the same intent.
			check(int(seen.get("uplink", 0)) > 200,
				"The guest's intents ran through the simulated link (%d released)"
					% int(seen.get("uplink", 0)))
			check(int(flow.session._link.released) > 200,
				"The host's poses ran through the simulated link too (%d released)"
					% int(flow.session._link.released))
			# Passing through a queue is not the same as being delayed by it: the
			# hold time is what the game felt.
			var wait := float(flow.session._link.mean_wait())
			check(wait >= 0.06 and wait <= 0.10,
				"The host's poses were held for the delay asked for (%.3f s)" % wait)
			check(int(flow.session._link.discarded) > 0,
				"And the link lost pose packets, as an unreliable one does (%d)"
					% int(flow.session._link.discarded))
			check(float(flow.session._link.drop) > 0.0,
				"with the losses typed: deaths and leaves are reliable and never drop")
		var struck := await _wait_until(func(): return is_instance_valid(dummy) \
			and (not bool(dummy.get("alive")) \
				or float(dummy.get("health")) < float(dummy.get("max_health"))), 6.0)
		check(struck, "The guest's swing reaches the host's field (%s hp)"
			% str(dummy.get("health") if is_instance_valid(dummy) else "gone"))
		if is_instance_valid(dummy) and bool(dummy.get("alive")):
			dummy.take_damage(999.0, 0)
		var vacuum = world.get("loot")
		var bodies := await _wait_until(func(): return vacuum != null \
			and not (vacuum.corpse_ids() as Array).is_empty(), 5.0)
		if bodies:
			corpse_id = int((vacuum.corpse_ids() as Array)[0])
		check(corpse_id > 0, "The guest's kill leaves a body to search")
		# The record goes out reliably, so the guest sees the same body.
		report.probe.rpc_id(guest_peer, "corpse")
		var seen := await _wait_until(func(): return reports.has("corpse"), 10.0)
		check(seen, "The guest's corpse screen lists the host's body")
		if seen:
			check(int((reports["corpse"] as Dictionary).get("corpses", 0)) > 0,
				"The guest imported the corpse record")
		var emptied := await _wait_until(func(): return corpse_id > 0 \
			and not vacuum.has_corpse(corpse_id), 10.0)
		check(emptied, "The guest's take empties the host's body")
		# And a drop on the host's ground is a drop the guest's K can take.
		var at: Vector3 = (combat_actor as Node3D).global_position + Vector3(0.8, 0.0, 0.0)
		drop = world.spawn_pickup("sword_short", at)
		check(drop != null, "The host drops a piece beside the guest")
		# A guest names a point and the point is only a hint: the host takes a drop
		# for a body only when the piece is in *that body's* reach. The guest's
		# replica knows where every drop lies, so without this a modified client
		# names a distant piece at its own position and empties the host's ground.
		var distant_at: Vector3 = at + Vector3(30.0, 0.0, 0.0)
		var distant = world.spawn_pickup("sword_short", distant_at)
		check(distant != null, "The host also drops a piece across the field")
		if distant != null:
			check(not bool(world.loot_for_peer(guest_peer, "drop", 0, "sword_short",
				(distant as Node3D).global_position)),
				"a drop named at its own position but out of the body's reach is refused")
			check(is_instance_valid(distant) and not bool(distant.get("collected")),
				"and that piece stays on the host's ground")
		for _beat in 3:
			await process_frame
		report.probe.rpc_id(guest_peer, "drop")
		var taken := await _wait_until(func(): return drop != null \
			and is_instance_valid(drop) and bool(drop.get("collected")), 10.0)
		check(taken, "The guest's K takes the host's drop")
		# The booking happens on the host, so the guest's own looted list can only
		# be fed from the wire: the list is how a guest reads what the warband is
		# winning, and an empty one for a whole session is the "no loot stream"
		# report.
		var piece_name := str(State.ITEMS.get("sword_short", {}).get("name", "sword_short"))
		var fed := await _wait_until(func(): return world.loot_feed != null \
			and " ".join(world.loot_feed.lines()).to_upper().contains(
				piece_name.to_upper()), 5.0)
		check(fed, "the guest's looted list carries the host's booking (%s)" % str(
			world.loot_feed.lines() if world.loot_feed != null else []))
		# A death is a one-shot fact on the reliable channel: the guest's copy of
		# a body killed on the host falls here even when every pose packet for it
		# was lost, instead of standing over the host's corpse forever.
		var dying = _warren_body(world, 1)
		if dying != null and combat_actor != null and is_instance_valid(combat_actor):
			var dead_at: Vector3 = (combat_actor as Node3D).global_position + Vector3(3.0, 0.0, 0.0)
			dying.global_position = dead_at
			dying.set("replica", true)
			dying.take_damage(999.0, 0)
			reports.erase("mob_dead")
			report.probe.rpc_id(guest_peer, "mob_dead")
			var dead_seen := await _wait_until(func(): return reports.has("mob_dead"), 10.0)
			check(dead_seen, "The guest answers for the body the host killed")
			if dead_seen:
				var dead: Dictionary = reports["mob_dead"]
				check(not bool(dead.get("alive", true)),
					"The guest's copy falls on the one-shot death")
				check(bool(dead.get("visible", false)),
					"and its corpse is on the screen")

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
	# A name sworn with a place on the field stands up on its own: a body in the
	# host's world, a replica of it in the guest's.
	var late_id: int = warband.add_mercenary(LATE_NAME)
	warband.roster.equip(late_id, "main", "sword_short")
	check(not warband.roster.is_reserve(late_id), "The third name has a place on the field")
	var fielded := await _wait_until(
		func(): return flow.session.controller.body_of(late_id) != null, 5.0)
	check(fielded, "The host's world fields the third body")
	var host_field: Array = world.get("bodies") if world.get("bodies") is Array else []
	check(fielded and host_field.has(flow.session.controller.body_of(late_id)),
		"and wires it with the rest of the band")
	check(warband.roster.has(late_id), "The warband takes a third body (%d)" % late_id)
	var reseated := await _wait_until(
		func(): return int(flow.session.ownership().get(guest_peer, 0)) == late_id, 20.0)
	check(reseated, "The waiting soul takes the next free body (%s)"
		% str(flow.session.ownership().get(guest_peer, 0)))
	check(int(flow.session.ownership().get(1, 0)) == host_merc,
		"The host was never moved out of its body")
	report.probe.rpc_id(guest_peer, "late")
	var late_seen := await _wait_until(func(): return reports.has("late"), 15.0)
	check(late_seen, "The guest reports the body it was given")
	if late_seen:
		var late: Dictionary = reports["late"]
		check(int(late.get("own_merc", -1)) == late_id,
			"The guest's soul sits in the third body (%s)" % str(late.get("own_merc")))
		check(bool(late.get("own_body", false)),
			"and the guest's world stands that body up to drive")

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
	report.strike_requested.connect(_on_strike)
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

	# --- the guest's own gear press wears the host's spare ------------------
	# Driven the way a player drives it: open the paperdoll, click the spare row,
	# then click the worn slot to take it back off. On a lent copy each press is a
	# request; the piece moves when the host's copy comes back.
	var gear_merc := _own_merc()
	var worn_before := str(warband.roster.equipped_of(gear_merc).get("main", ""))
	check(worn_before != "sword_arming" and warband.stash.pooled_count("sword_arming") == 1,
		"The guest sees the host's spare on the shelf (%d)" % warband.stash.pooled_count("sword_arming"))
	var doll = DollScript.new()
	doll.name = "GuestDoll"
	root.add_child(doll)
	doll.configure(warband)
	doll.open(gear_merc)
	await process_frame
	var spare_row: Variant = doll._stash_controls.get("sword_arming")
	check(spare_row is Button, "the guest's paperdoll lists the spare blade")
	if spare_row is Button:
		(spare_row as Button).pressed.emit()
	check(str(warband.roster.equipped_of(gear_merc).get("main", "")) == worn_before,
		"and the press does not change the lent copy by itself (%s)" % doll.status_text())
	var worn := await _wait_until(func(): return str(
		warband.roster.equipped_of(gear_merc).get("main", "")) == "sword_arming", 12.0)
	check(worn, "The host's answer wears the piece on the guest's copy (%s) after [%s]" % [
		str(warband.roster.equipped_of(gear_merc).get("main", "")), doll.status_text()])
	check(str(flow.session.controller.seat_loadout(gear_merc).get("main", "")) == "sword_arming",
		"and the guest's own body wears it (%s)" % str(
			flow.session.controller.seat_loadout(gear_merc).get("main", "")))
	await process_frame
	check(doll.slot_rows.get("main", {}).get("button", null) != null,
		"the guest's paperdoll has a worn main slot to click")
	var slot_button: Variant = doll.slot_rows.get("main", {}).get("button")
	if slot_button is Button:
		(slot_button as Button).pressed.emit()
	var bare := await _wait_until(func(): return str(
		warband.roster.equipped_of(gear_merc).get("main", "")) != "sword_arming", 12.0)
	check(bare, "and the host takes it back off the copy (%s) after [%s]" % [
		str(warband.roster.equipped_of(gear_merc).get("main", "")), doll.status_text()])
	check(warband.stash.pooled_count("sword_arming") == 1,
		"The spare is back on the guest's shelf (%d) after [%s]" % [
			warband.stash.pooled_count("sword_arming"), doll.status_text()])
	doll.close()
	_submit({"kind": "gear", "tag": "gear", "merc": gear_merc,
		"worn": str(warband.roster.equipped_of(gear_merc).get("main", ""))})

	# --- the guest's own rite at the altar ---------------------------------
	# The altar's panel is the host's books like the paperdoll: the press is a
	# request, the host's arm pays the one pooled vial and throws the die, and the
	# weld comes back on the mirrored ledger. Nothing here rolls locally.
	var altar_menu = AltarMenuScript.new()
	altar_menu.name = "GuestAltar"
	root.add_child(altar_menu)
	altar_menu.configure(warband)
	altar_menu.open()
	var rite_copy := int(warband.annoint_copy_for_item("sword_arming"))
	var vial_before := int(warband.stash.pooled_count("ichor_vial"))
	check(vial_before == 1, "The guest sees the host's pooled vial (%d)" % vial_before)
	altar_menu.press_anoint("sword_arming", rite_copy)
	check(warband.annoints.count("sword_arming", rite_copy) == 0
			and warband.stash.pooled_count("ichor_vial") == vial_before,
		"The guest's rite spends nothing on the lent copy by itself")
	var spent := await _wait_until(func(): return warband.stash.pooled_count(
		"ichor_vial") < vial_before, 12.0)
	check(spent, "The host works the rite and the pooled vial leaves (%d) after [%s]" % [
		warband.stash.pooled_count("ichor_vial"), altar_menu.status_text()])
	var rite_rows: int = altar_menu.anoint_rows().size()
	check(rite_rows > 0, "and the open altar still lists the copies (%d)" % rite_rows)
	altar_menu.close()
	_submit({"kind": "rite", "tag": "rite", "copy": rite_copy,
		"count": warband.annoints.count("sword_arming", rite_copy),
		"vials": warband.stash.pooled_count("ichor_vial")})

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
	if tag == "watch" or tag == "seat":
		# The map that took this soul's body away has just landed; the eye and the
		# body panel settle on the next physics frame, so the report is read after
		# a couple of them rather than on the frame the map arrived.
		for _beat in 4:
			await physics_frame
		await process_frame
	elif tag == "late":
		# The host's map, its warband copy and the body it asks this world for land
		# on their own clocks: the report waits for the soul to settle in it.
		await _wait_until(func(): return _own_merc() > 0 and flow.session != null \
			and flow.session.controller.body_of(_own_merc()) != null, 5.0)
	elif tag == "corpse":
		# The record is a reliable RPC behind the kill's snapshot: wait for it, then
		# take the lot through the same intent a row click sends.
		var vacuum = world.get("loot")
		await _wait_until(func(): return vacuum != null \
			and not (vacuum.corpse_ids() as Array).is_empty(), 5.0)
		var ids: Array = vacuum.corpse_ids() if vacuum != null else []
		if ids.is_empty():
			_submit({"kind": "probe", "tag": tag, "corpses": 0})
			return
		world.call("request_loot_take", int(ids[0]), "", Vector3.ZERO, true)
		_submit({"kind": "probe", "tag": tag, "corpses": ids.size(),
			"corpse": int(ids[0])})
		return
	elif tag == "mob" or tag == "mob_gone" or tag == "mob_dead":
		var warden = _warren_body(world, 1 if tag == "mob_dead" else 0)
		var payload := {"kind": "probe", "tag": tag, "replica": false, "resting": true,
			"pos": [0.0, 0.0, 0.0], "visible": false, "stale": false, "alive": true}
		# A hitch can empty the guest's receive for longer than a poll: wait for
		# the stream to be live again before reading the copy, which is the
		# property the check is about. A stream that never comes back still fails.
		if tag == "mob" and warden != null and is_instance_valid(warden):
			var before := _mob_tick()
			await _wait_until(func(): return _mob_tick() > before, 2.0)
			# A fresh sample still needs its playout to reach it: two intervals.
			for _beat in 12:
				await process_frame
		elif tag == "mob_dead":
			# The kill is booked on the host on the next mob poll; the probe names
			# the body and waits for the one-shot death to land before reading it.
			await _wait_until(func(): return warden == null or not is_instance_valid(warden) \
				or not bool(warden.get("alive")), 3.0)
		if warden != null and is_instance_valid(warden):
			var at: Vector3 = (warden as Node3D).global_position
			payload["replica"] = bool(warden.get("replica"))
			payload["resting"] = bool(warden.get("resting"))
			payload["pos"] = [at.x, at.y, at.z]
			payload["visible"] = bool(warden.get("visible"))
			payload["stale"] = bool(warden.get("stale"))
			payload["stream_tick"] = _mob_tick()
			payload["alive"] = bool(warden.get("alive"))
		_submit(payload)
		return
	elif tag == "drop":
		# The host's K test: the guest's own hand on its own world's drop, which
		# travels as an intent and is booked on the other machine. The drop is
		# announced on the host's loot poll, so wait for the copy to land here and
		# take the piece the test named, not whatever else happens to lie nearer.
		var arrived := await _wait_until(func(): return _find_drop("sword_short") != null, 5.0)
		if arrived:
			world.call("_try_loot")
		_submit({"kind": "probe", "tag": tag, "near": arrived})
		return
	_submit(_probe_payload(tag))


## The newest mob tick the guest's warden copy has been handed, -1 for none.
func _mob_tick() -> int:
	var warden = _warren_body(world, 0)
	if warden == null or not is_instance_valid(warden):
		return -1
	var timeline = warden.get("_timeline")
	return int(timeline.newest_tick()) if timeline != null else -1


## A warcamp body by its place in the field, on whichever machine this runs on.
## The camps are built from `WatcherWarren.CAMPS` on both peers and the table's
## own order is the spawn order, so index 0 is the same body on the host and on the
## guest - which is the property the mob stream is asked about. The names off the
## table would do too; the index does not have to know them.
func _warren_body(world_in, index: int):
	var warren = world_in.get("watcher_warren") if world_in != null else null
	if warren == null:
		return null
	var fielded: Array = warren.mobs()
	if index < 0 or index >= fielded.size():
		return null
	return fielded[index]


## The guest's own copy of a named drop, or null while it has not landed yet.
func _find_drop(item_id: String):
	var vacuum = world.get("loot") if world != null else null
	if vacuum == null:
		return null
	for pickup in vacuum.pickups():
		if is_instance_valid(pickup) and not bool(pickup.get("collected")) \
				and str(pickup.get("item_id")) == item_id:
			return pickup
	return null


## A swing the host asked the guest's body for: the owning peer presses its own
## attack with the aim point the host chose.
func _on_strike(point: Vector3) -> void:
	if flow == null or flow.session == null or flow.session.controller == null:
		return
	var controller = flow.session.controller
	var actor = controller.active_actor
	var sent := false
	if actor != null:
		sent = controller.act("melee", {"aim": point, "hand": "right",
			"variant": "overhead"})
	# What the host is about to rewind against, from the guest's own books: the
	# clock that answers `view_tick()` and the delay a remote body is really
	# drawn at. They have to be the same number or the blow is judged against a
	# moment nobody was looking at.
	var replica = controller.body_for_peer(1)
	var replica_delay := -1.0
	if replica != null and is_instance_valid(replica):
		var timeline = replica.get("_timeline")
		if timeline != null:
			replica_delay = float(timeline.floor_delay_ticks)
	_submit({"kind": "strike", "tag": "strike", "actor": actor != null,
		"sent": sent, "view": controller.view_tick(),
		"newest": int(controller._clock.newest_tick()),
		"clock_delay": float(controller._clock.timeline.floor_delay_ticks),
		"replica_delay": replica_delay,
		"uplink": int(controller.sync._link.released),
		"owned": int(controller.merc_for_peer(controller.local_peer_id)),
		"active": int(controller.merc_of(actor)) if actor != null else -1})

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
		"own_body": _own_merc() > 0 and controller != null and controller.body_of(_own_merc()) != null,
		"watching": watching,
		"watching_holder": holder,
		"mission_watch": lines.size() >= 2 and String(lines[1]).contains("no body is free"),
		"body_lines": lines,
		"gold": warband.gold() if warband != null else -1,
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
