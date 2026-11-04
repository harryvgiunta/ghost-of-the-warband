extends Node3D
## The delve as a place in the one world: the Weeping Hollow's mouth in the town
## square, the counter where a party and its delve inventory are made up, and the
## instance the party goes down into and comes back up out of.
##
## The loop the town exists for, in four moments:
##
##   * **At the mouth** (`G` at the rope pit by the square's east lanes) the
##     panel opens: which standing bodies go down, and which spare pieces leave the
##     town stash for the delve inventory (`delve_prep_menu.gd`).
##   * **Going down** writes the descent into the warband (`Warband.begin_delve`),
##     builds a fresh cave (`delve_cave.gd`) at `ORIGIN` and lowers the party down
##     one of its six shafts - drawn afresh every descent, the way an extraction
##     floor hands each party its own corner (`delve_layout.landings_for`) - then
##     shuts the rest of the warband out of reach: the soul and the squad only ever
##     work the bodies below. Everything taken below lands in the delve inventory,
##     never the stash.
##   * **Climbing out** (`G` at any shaft's rope below) brings every body still
##     alive - standing or carried - back to the mouth and empties the inventory
##     into the town stash (`Warband.extract_delve`).
##   * **Falling** - nobody below left standing - costs the inventory and every
##     piece the party still wears (`Warband.forfeit_delve`). Whoever was only down
##     stands up at the mouth with nothing on and a revive's twentieth of a pool
##     (`REVIVE_HEALTH_FRACTION`); the dead stay dead.
##
## The cave is torn down at both ends, so every descent is a fresh instance. A
## co-op guest builds and frees its own copy from the host's books (the descent is
## warband state, and the host mirrors the warband), and leaves every decision to
## the host.

signal descended(party: Array)
signal climbed_out(result: Dictionary)
signal fell(result: Dictionary)

const CaveScript = preload("res://scripts/warband/delve_cave.gd")
const Layout = preload("res://scripts/warband/delve_layout.gd")
const PrepScript = preload("res://scripts/warband/delve_prep_menu.gd")
const MapScript = preload("res://scripts/warband/delve_map.gd")
const VillageKit = preload("res://scripts/world/village_kit.gd")
const TextureLibrary = preload("res://scripts/world/texture_library.gd")
const TerrainScript = preload("res://scripts/warband/terrain.gd")
const StashScript = preload("res://scripts/warband/town_stash_model.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")

## Where the mouth stands, in the square's own frame: the plot the expedition gate
## used to hold, which the square's fingerpost still points down.
const MOUTH_POINT := Vector3(8.0, 0.0, -6.0)
const MOUTH_REACH := 3.0
## Where every instance is built: past the wood's northern rim, far outside the
## field the heightfield covers and beyond any camera's far plane from it.
const ORIGIN := Vector3(0.0, 0.0, 1100.0)
## How long the party lies in the dark before the Hollow takes what it carried.
const WIPE_BEAT := 2.5
## The ring a party comes back up onto, on the square's side of the mouth.
const RETURN_RADIUS := 2.2
const RETURN_STEP := 3.2
const HEADER_POLL := 0.25
const GUEST_TEXT := "Co-op: the host takes the party down and brings it up."
const MOUTH_PROMPT := "G  -  THE WEEPING HOLLOW"

## The world this area stands in.
var host: Node3D = null
## The instance below while a party is down there, else null.
var cave = null
## The shaft (`delve_layout.LANDINGS` id) the party below came down, else "".
var landing := ""
## The panel the mouth opens.
var prep = null
## The floor's plan (`delve_map.gd`), opened with `M` below.
var map = null
## The rope pit in the square.
var mouth: Node3D = null

var _wipe_beat := -1.0
var _eye_below := false
var _sun: Node3D = null
var _nav_before = null
var _header_clock := 0.0
var _draw := RandomNumberGenerator.new()


func setup(world: Node3D) -> void:
	host = world
	_draw.randomize()
	_build_mouth()
	prep = PrepScript.new()
	prep.name = "DelvePrep"
	add_child(prep)
	prep.configure(host.warband)
	prep.descend_requested.connect(_on_descend_requested)
	map = MapScript.new()
	map.name = "DelveMap"
	add_child(map)
	map.configure(self)


# --- reading -----------------------------------------------------------------

## The rope pit, in the world.
func mouth_point() -> Vector3:
	var town = host.get("town") if host != null else null
	var square: Vector3 = (town as Node3D).global_position if town != null else Vector3.ZERO
	return square + MOUTH_POINT


func at_mouth(actor) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var offset: Vector3 = (actor as Node3D).global_position - mouth_point()
	return Vector2(offset.x, offset.z).length() <= MOUTH_REACH


## The floor's own clock and the eye's sky below are only the floor's once it is
## whole; `_building` is the window between the instance being created and its
## last build step.
var _building := false

func below() -> bool:
	return cave != null and cave.built


## Whether a floor is coming up right now (the party is still in the square).
func building() -> bool:
	return _building


## Whether a body stands inside the instance.
func in_cave(actor) -> bool:
	return cave != null and actor != null and is_instance_valid(actor) \
		and cave.contains((actor as Node3D).global_position)


## The party's bodies, standing only or with the downed carried along.
func party_bodies(with_downed: bool = true) -> Array:
	var out: Array = []
	if host == null or host.warband == null or host.controller == null:
		return out
	for merc_id in host.warband.delve.party:
		var body = host.controller.body_of(int(merc_id))
		if body == null or not is_instance_valid(body) or not bool(body.get("alive")):
			continue
		if not with_downed and bool(body.get("downed")):
			continue
		out.append(body)
	return out


## The bodies the mouth may send down: every one on the field, alive and standing.
func candidates() -> Array[int]:
	var out: Array[int] = []
	if host == null or host.controller == null:
		return out
	for actor in host.bodies:
		if not is_instance_valid(actor) or not bool(actor.get("alive")) or bool(actor.get("downed")):
			continue
		var merc_id: int = host.controller.merc_of(actor)
		if merc_id > 0 and host.warband.roster.is_alive(merc_id) and not out.has(merc_id):
			out.append(merc_id)
	return out


func panels_open() -> bool:
	return prep != null and prep.is_open()


func close_panels() -> void:
	if prep != null:
		prep.close()


# --- the HUD lines -----------------------------------------------------------

## The crosshair line: a rope below, the floor's objective anywhere else below
## (and, once Gorehorn is dead, the rope the shortest walk reaches), or the mouth
## in the square. Empty everywhere else.
func prompt_line(actor) -> String:
	if actor == null or not is_instance_valid(actor):
		return ""
	if below() and in_cave(actor):
		if cave.at_exit(actor):
			var pieces: int = host.warband.delve.inventory.pooled_total()
			return "G  -  CLIMB OUT  ·  %d PIECE%s TO THE TOWN STASH" % [pieces, "" if pieces == 1 else "S"]
		if cave.master_alive():
			return "SLAY GOREHORN  ·  %d BELOW" % cave.living()
		var rope: Dictionary = cave.nearest_rope((actor as Node3D).global_position)
		if rope.is_empty():
			return "CLIMB OUT  ·  A ROPE HANGS IN EVERY SHAFT"
		return "CLIMB OUT  ·  NEAREST ROPE  ·  %s  ·  %d M" % [Layout.area_name(str(rope["area"])),
			roundi(float(rope["metres"]))]
	if not host.warband.delve.active and at_mouth(actor):
		return MOUTH_PROMPT
	return ""


# --- the clock ---------------------------------------------------------------

## The world's physics clock: the host wakes dens and watches for a fall, a guest
## follows the host's books, and every machine keeps its eye's sky right.
func tick(delta: float) -> void:
	if host == null:
		return
	if _building:
		_paint_loading(delta)
		_sync_eye()
		return
	if bool(host.get("_client")):
		_mirror()
	elif cave != null:
		cave.tick(delta, party_bodies(false))
		_check_wipe(delta)
	_sync_eye()
	_header_clock += delta
	if _header_clock >= HEADER_POLL:
		_header_clock = 0.0
		_paint_header()


## The line the player reads while the floor comes up: the window keeps painting,
## so this is a load, not a freeze.
func _paint_loading(delta: float) -> void:
	_header_clock += delta
	if _header_clock < HEADER_POLL:
		return
	_header_clock = 0.0
	if cave == null:
		return
	host.hud.set_status("%s  ·  GOING DOWN  ·  %d%%" % [CaveScript.TITLE,
		roundi(cave.built_share * 100.0)], 1.0)


## `G`: the rope below, or the mouth in the square. True when the press was the
## delve's.
func interact(actor) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var hud = host.get("hud")
	if below() and cave.at_exit(actor):
		if bool(host.get("_client")):
			# The host owns the descent, but a guest on a rope still has to be able
			# to get the party out - a host whose own body is dead in the dark
			# cannot press anything. The press rides the intent channel.
			host.controller.act("climb_out")
			hud.set_status("Asked the host to climb out.", 2.5)
		else:
			climb_out()
		return true
	if not at_mouth(actor):
		return false
	if bool(host.get("_client")):
		hud.set_status(GUEST_TEXT, 3.0)
	elif host.warband.delve.active:
		hud.set_status("The party is below. It comes up by a rope, or not at all.", 3.0)
	else:
		open_prep()
	return true


func open_prep() -> void:
	if host.has_method("_hide_panels"):
		host._hide_panels()
	prep.open(candidates())
	host.hud.set_status("The Weeping Hollow: choose who goes down and what they carry.", 4.0)


func _on_descend_requested(party: Array) -> void:
	var result: Dictionary = await descend(party)
	if bool(result.get("ok", false)):
		prep.close()
	else:
		prep.set_status(str(result.get("message", "")))


# --- going down --------------------------------------------------------------

## Send these bodies below. Every one must be standing; the books are written
## first (`Warband.begin_delve`), then the instance is built and the party put on
## the landing ring of one shaft - `landing_id` when it names one, else a shaft
## drawn for this descent. Returns `{ok, party, landing, message}`.
##
## The floor is built across frames (`delve_cave.build_staged`) and the party is
## placed when it is whole: two to four seconds of rigs and rock, and the window
## keeps painting under `GOING DOWN` while it happens instead of freezing. This
## function is therefore a coroutine - a caller that wants the bodies placed must
## `await` it.
func descend(party_ids: Array, landing_id: String = "") -> Dictionary:
	if host == null or bool(host.get("_client")):
		return {"ok": false, "party": [], "message": GUEST_TEXT}
	if cave != null or host.warband.delve.active:
		return {"ok": false, "party": [], "message": "A party is already below."}
	var bodies: Array = []
	var ids: Array[int] = []
	for raw_id in party_ids:
		var merc_id := int(raw_id)
		if ids.has(merc_id):
			continue
		var body = host.controller.body_of(merc_id)
		if body == null or not is_instance_valid(body) or not bool(body.get("alive")) \
				or bool(body.get("downed")):
			return {"ok": false, "party": [],
				"message": "%s cannot go down now." % host.warband.roster.name_of(merc_id)}
		ids.append(merc_id)
		bodies.append(body)
	if bodies.is_empty():
		return {"ok": false, "party": [], "message": "Choose who goes down."}
	var booked: Dictionary = host.warband.begin_delve(ids)
	if not bool(booked.get("ok", false)):
		return booked
	if host.get("loot_hand") != null:
		host.loot_hand.cancel()
	if host.has_method("_hide_panels"):
		host._hide_panels()
	# The shaft is drawn before the floor is built: the build warms the room the
	# party lands in, so the eye's first frame below is a frame that has been
	# drawn before.
	landing = landing_id if not Layout.landing(landing_id).is_empty() \
		else Layout.landings_for(1, _draw.randi())[0]
	await _open_instance(false, str(Layout.landing(landing)["room"]))
	var posts: Array[Vector3] = cave.entry_posts(landing, bodies.size())
	for index in bodies.size():
		_move_body(bodies[index], posts[index], cave.entry_yaw(landing))
	host.warband.souls.set_reach(ids)
	var controller = host.controller
	if not ids.has(int(controller.merc_for_peer(controller.local_peer_id))):
		controller.direct(controller.local_peer_id, ids[0])
	host.hud.set_status("The party goes down into the Weeping Hollow: %s." % Layout.area_name(
		str(Layout.landing(landing)["area"])), 4.0)
	descended.emit(ids.duplicate())
	return {"ok": true, "party": ids, "landing": landing, "message": str(booked.get("message", ""))}


## The party climbs a rope: every body still alive comes up to the mouth, and the
## delve inventory goes into the town stash. Returns `Warband.extract_delve`'s
## answer.
func climb_out() -> Dictionary:
	if host == null or bool(host.get("_client")) or not below():
		return {"ok": false, "items": {}, "count": 0, "value": 0}
	var bodies := party_bodies(true)
	var result: Dictionary = host.warband.extract_delve()
	_bring_up(bodies)
	_close_instance()
	host.hud.set_status("The party climbs out of the Hollow: %d piece%s into the town stash (%d G)." % [
		int(result.get("count", 0)), "" if int(result.get("count", 0)) == 1 else "s",
		int(result.get("value", 0))], 5.0)
	climbed_out.emit(result)
	return result


func _check_wipe(delta: float) -> void:
	if not host.warband.delve.active:
		return
	if not party_bodies(false).is_empty():
		_wipe_beat = -1.0
		return
	# The beat starts once, on the frame the last body goes down.
	if _wipe_beat < 0.0:
		_wipe_beat = WIPE_BEAT
		host.hud.set_status("The party is down. The Hollow keeps what it carried.", WIPE_BEAT)
		if host.get("squad") != null:
			host.squad.following = false
	_wipe_beat -= delta
	if _wipe_beat > 0.0:
		return
	fall()


## Nobody below is standing: the Hollow keeps the inventory and everything the
## party still wears, and whoever was only down wakes in the square with nothing.
## Returns `Warband.forfeit_delve`'s answer: what was lost.
func fall() -> Dictionary:
	if host == null or not below():
		return {"ok": false, "items": {}, "count": 0, "value": 0}
	var survivors := party_bodies(true)
	var result: Dictionary = host.warband.forfeit_delve()
	for body in survivors:
		var merc_id: int = host.controller.merc_of(body)
		if bool(body.get("downed")):
			body.revive_from_downed(Contracts.REVIVE_HEALTH_FRACTION)
			host.warband.roster.revive(merc_id)
	_bring_up(survivors)
	for body in survivors:
		host.controller.refresh_gear(host.controller.merc_of(body))
	_close_instance()
	if host.get("squad") != null:
		host.squad.following = true
	host.hud.set_status("The party fell in the Hollow. Everything it carried is gone: %d piece%s, %d G." % [
		int(result.get("count", 0)), "" if int(result.get("count", 0)) == 1 else "s",
		int(result.get("value", 0))], 6.0)
	fell.emit(result)
	return result


func _bring_up(bodies: Array) -> void:
	var posts := _return_posts(bodies.size())
	var toward := -MOUTH_POINT.normalized()
	var yaw := atan2(-toward.x, -toward.z)
	for index in bodies.size():
		_move_body(bodies[index], posts[index], yaw)


## A ring on the square's side of the mouth, one post per body.
func _return_posts(count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var toward := -MOUTH_POINT.normalized()
	var centre := mouth_point() + toward * RETURN_STEP
	for index in maxi(1, count):
		var angle := TAU * float(index % 8) / 8.0
		var radius := RETURN_RADIUS + 1.2 * float(index / 8)
		out.append(TerrainScript.grounded(centre + Vector3(cos(angle) * radius, 0.0,
			sin(angle) * radius)) + Vector3(0.0, 0.12, 0.0))
	return out


func _move_body(body, at: Vector3, yaw: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	var cover = body.get("cover")
	if cover != null and bool(cover.get("active")) and body.has_method("leave_cover"):
		body.leave_cover()
	body.teleport_to(at, yaw)
	body.spawn_point = at


# --- the instance ------------------------------------------------------------

func _open_instance(as_replica: bool, warm_room: String = "") -> void:
	cave = CaveScript.new()
	cave.name = "WeepingHollow"
	cave.position = ORIGIN
	add_child(cave)
	# The floor comes up a frame's worth at a time: the loading line counts while
	# the window keeps painting. Nothing below is trusted until `cave.built`.
	_building = true
	await cave.build_staged(host, as_replica, warm_room)
	_building = false
	cave.den_woke.connect(_on_den_woke)
	cave.master_slain.connect(_on_master_slain)
	var squad = host.get("squad")
	if squad != null:
		_nav_before = squad.nav
		squad.nav = cave.nav
		squad.relocate()
		if not as_replica:
			squad.following = true


func _close_instance() -> void:
	if cave == null:
		return
	# The plan is of a floor nobody is on any more.
	if map != null:
		map.close()
	var squad = host.get("squad")
	if squad != null:
		squad.nav = _nav_before
		squad.relocate()
	_nav_before = null
	host.warband.souls.clear_reach()
	cave.teardown()
	cave = null
	landing = ""
	_wipe_beat = -1.0
	_sync_eye(true)
	_paint_header()
	# A soul whose last body below died is loose: give it the first body that is
	# free now that the town's are in reach again.
	var controller = host.controller
	if not bool(host.get("_client")) and int(controller.merc_for_peer(controller.local_peer_id)) <= 0:
		var free: Array[int] = controller.living_merc_ids()
		if not free.is_empty():
			controller.direct(controller.local_peer_id, free[0])


## A guest has no say: it builds the cave while the host's books say a party is
## below and frees it when they say it is not.
func _mirror() -> void:
	var wanted := bool(host.warband.delve.active)
	if wanted and cave == null and not _building:
		_open_instance(true)
	elif not wanted and cave != null:
		_close_instance()


## Underground the eye has no sky: the camera takes the cave's own environment and
## the moon goes out, and both come back the moment the eye is up again.
func _sync_eye(force: bool = false) -> void:
	var camera: Camera3D = host.get("camera")
	if camera == null:
		return
	var eye_below: bool = below() and cave.contains(camera.global_position)
	if eye_below == _eye_below and not force:
		return
	_eye_below = eye_below
	camera.environment = cave.environment if eye_below else null
	var sun := _world_sun()
	if sun != null:
		sun.visible = not eye_below


func _world_sun() -> Node3D:
	if _sun == null or not is_instance_valid(_sun):
		_sun = host.find_child("WorldSun", true, false) as Node3D
	return _sun


## The floor's lines over the looted list: the floor and the area the eye's body
## stands in, what the inventory holds, the rope the shortest walk reaches, and
## Gorehorn's blood. Every line stays inside the feed's column.
func _paint_header() -> void:
	var feed = host.get("loot_feed")
	if feed == null:
		return
	if not below() or not host.warband.delve.active:
		feed.set_header("")
		return
	var pool = host.warband.delve.inventory
	var pooled: Dictionary = pool.pooled_map()
	var value := 0
	for item_id in pooled:
		value += StashScript.value_of(str(item_id)) * int(pooled[item_id])
	var pieces: int = pool.pooled_total()
	var lines := PackedStringArray(["%s  ·  %s" % [CaveScript.TITLE, CaveScript.FLOOR_LABEL]])
	var body = host.controller.active_body() if host.controller != null else null
	var rope := {}
	if body != null and is_instance_valid(body) and cave != null and cave.contains(body.global_position):
		var area: String = cave.area_at(body.global_position)
		if not area.is_empty():
			lines.append(Layout.area_name(area))
		rope = cave.nearest_rope(body.global_position)
	lines.append("DELVE INVENTORY  ·  %d PIECE%s  ·  %d G" % [pieces, "" if pieces == 1 else "S", value])
	if not rope.is_empty():
		lines.append("WAY UP  ·  %s  ·  %d M" % [Layout.area_name(str(rope["area"])),
			roundi(float(rope["metres"]))])
	if cave.master_alive():
		if cave.is_awake("lair"):
			lines.append("GOREHORN  %d / %d" % [int(cave.master.health), int(cave.master.max_health)])
	else:
		lines.append("GOREHORN IS DEAD  ·  CLIMB OUT BY A ROPE")
	feed.set_header("\n".join(lines))


func _on_den_woke(_den_id: String, label: String) -> void:
	host.hud.set_status(label, 3.0)


func _on_master_slain(master_name: String) -> void:
	host.hud.set_status("%s falls. The Hollow is quiet: climb out with what you carry." % master_name, 5.0)


# --- the mouth ---------------------------------------------------------------

## The way down: a pit of dark in the flagstones, ringed by broken stone that
## rises behind it, a timber A-frame and pulley over it with the rope down into
## the black, a lantern, and its name. The ring opens toward the fire.
func _build_mouth() -> void:
	mouth = Node3D.new()
	mouth.name = "HollowMouth"
	mouth.position = mouth_point()
	var toward := -MOUTH_POINT
	mouth.rotation.y = atan2(toward.x, toward.z)
	add_child(mouth)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7351
	var stone := TextureLibrary.boulder_material(Color(0.66, 0.62, 0.58))
	var shapes: Array[ArrayMesh] = [RockKit.mesh("outcrop", 7401), RockKit.mesh("boulder", 7433),
		RockKit.mesh("outcrop", 7459)]
	var cobbles: Array[ArrayMesh] = [RockKit.mesh("cobble", 7477), RockKit.mesh("cobble", 7489)]
	var m := VillageKit.Merged.new()
	# A horseshoe of broken stone round the back and sides, a second course on it,
	# and a face of rock behind the pit so the hole reads as a way into the ground.
	for index in 9:
		var angle := lerpf(deg_to_rad(55.0), deg_to_rad(305.0), float(index) / 8.0)
		var at := Vector3(sin(angle), 0.06, cos(angle)) * 1.85
		RockKit.add_stone(m, stone, shapes[index % shapes.size()], at, rng.randf_range(0.55, 0.9),
			rng.randf_range(0.0, TAU), 0.38, rng.randf_range(-0.2, 0.2))
	for index in 4:
		var angle := lerpf(deg_to_rad(140.0), deg_to_rad(220.0), float(index) / 3.0)
		var at := Vector3(sin(angle), 0.55, cos(angle)) * 1.7
		RockKit.add_stone(m, stone, shapes[(index + 1) % shapes.size()], at, rng.randf_range(0.5, 0.75),
			rng.randf_range(0.0, TAU), 0.2, rng.randf_range(-0.3, 0.3))
	for index in 3:
		var at := Vector3(-0.95 + float(index) * 0.95, 0.06, -2.05 - float(index % 2) * 0.2)
		RockKit.add_stone(m, stone, shapes[index % shapes.size()], at, rng.randf_range(0.9, 1.1),
			rng.randf_range(0.0, TAU), 0.15, rng.randf_range(-0.15, 0.15))
	for index in 12:
		var angle := TAU * float(index) / 12.0
		RockKit.add_stone(m, stone, cobbles[index % cobbles.size()],
			Vector3(sin(angle), 0.08, cos(angle)) * 1.18, rng.randf_range(0.16, 0.24),
			rng.randf_range(0.0, TAU), 0.5)
	# The pit sits on the square's flagstones, not under them.
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.008, 0.007, 0.006)
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	VillageKit.add_cyl_disc(m, 1.05, 0.02, Vector3(0.0, 0.1, 0.0), dark, 22)
	var mats: Dictionary = CampKit.materials()
	# The A-frame and its pulley, the rope down into the pit.
	for side in [-1.0, 1.0]:
		VillageKit.add_beam(m, Vector3(side * 1.25, -0.05, -0.15), Vector3(side * 0.08, 2.75, -0.15),
			0.075, mats["drift_dark"], 6, 0.06)
	VillageKit.add_beam(m, Vector3(-0.35, 2.62, -0.15), Vector3(0.35, 2.62, -0.15), 0.05,
		mats["drift_dark"], 6)
	VillageKit.add_ring(m, Vector3(0.0, 2.5, -0.15), PI * 0.5, 0.09, 0.15, mats["drift"], 0.0, 12, 4)
	VillageKit.add_beam(m, Vector3(0.0, 2.42, -0.15), Vector3(0.0, -0.4, -0.05), 0.03, mats["drift"], 5)
	# The lantern post at the pit's lip.
	VillageKit.add_beam(m, Vector3(1.05, -0.05, 0.85), Vector3(1.08, 1.75, 0.85), 0.05, mats["drift_dark"], 6)
	VillageKit.add_ball(m, 0.09, Vector3(1.08, 1.62, 0.85), mats["fire_core"], Vector3(1.0, 1.3, 1.0), 7, 4)
	m.commit(mouth, "MouthStone")
	var lamp := FireFlicker.new()
	lamp.name = "MouthLantern"
	lamp.position = Vector3(1.08, 1.75, 0.85)
	lamp.light_color = Color(1.0, 0.62, 0.30)
	lamp.light_energy = 1.4
	lamp.omni_range = 7.0
	lamp.omni_attenuation = 1.2
	lamp.flicker = 0.18
	lamp.shadow_enabled = false
	mouth.add_child(lamp)
	var solids := StaticBody3D.new()
	solids.name = "MouthSolids"
	solids.collision_layer = 1
	solids.collision_mask = 0
	mouth.add_child(solids)
	var back := CylinderShape3D.new()
	back.radius = 0.95
	back.height = 1.8
	var holder := CollisionShape3D.new()
	holder.shape = back
	holder.position = Vector3(0.0, 0.9, -1.75)
	solids.add_child(holder)
	var word := Label3D.new()
	word.name = "MouthName"
	word.text = "THE WEEPING HOLLOW"
	word.font_size = 64
	word.pixel_size = 0.006
	word.outline_size = 12
	word.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	word.modulate = Color(0.95, 0.78, 0.48)
	word.outline_modulate = Color(0.10, 0.04, 0.02, 0.9)
	word.position = Vector3(0.0, 3.25, -0.1)
	mouth.add_child(word)
