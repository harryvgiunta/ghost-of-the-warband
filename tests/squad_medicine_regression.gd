extends SceneTree
## The squad's field medicine for Ghost of the Warband: a hurt ally binds its
## wounds with a linen bandage out of the shared stash, and only when nothing
## hostile is close enough to punish it.
##
## The channel is the squad's, not a scene's: it lives in `squad_drive.gd` and is
## driven by the same track dictionary the fight ladder uses, so what is measured
## here is the rule itself - the gate, the seconds, the spend and the interrupt -
## with a body double standing in for a rigged mercenary.

const SquadScript = preload("res://scripts/warband/squad_drive.gd")
const ReviveScript = preload("res://scripts/warband/revive_channel.gd")

const TEST_SAVE := "user://squad_medicine_state.json"
const BANDAGE := "bandage_linen"

var checks := 0
var failures := 0
var _warband = null
var _squad = null
var _merc_id := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("SQUAD_MEDICINE_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var state = root.get_node("PlayerState")
	var warband = root.get_node("Warband")
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	state.save_path = TEST_SAVE
	warband.save_path = TEST_SAVE
	warband.reset_state()
	_warband = warband

	_merc_id = warband.add_mercenary("Wounded")
	_squad = SquadScript.new()
	_squad.setup(warband, null, null)
	var ids: Array[int] = [_merc_id]
	_squad.squad_ids = ids

	var body := FakeBody.new()
	body.name = "FakeMerc"
	root.add_child(body)

	# A whole body with nothing to dress it with: no bandage, no work.
	check(not _squad._wants_bandage(body, _merc_id),
		"a warband with no bandage in the stash has nothing to bind a wound with")
	check(not _squad._bandage_step(body, _merc_id, _track(), 0.016),
		"and the ally keeps doing what it was doing")

	# A healthy body keeps its dressings for after the fight.
	warband.stash.add(BANDAGE, 2)
	body.health = body.max_health
	check(not _squad._wants_bandage(body, _merc_id),
		"a body at full health does not spend a bandage")

	# Hurt, quiet, and holding a dressing: the channel opens and takes its seconds.
	body.health = body.max_health * 0.4
	check(_squad._wants_bandage(body, _merc_id), "a badly hurt body wants a dressing")
	var track := _track()
	check(_squad._bandage_step(body, _merc_id, track, 0.016),
		"the ally stops and binds the wound")
	check(bool(track.get("bandaging", false)), "the channel is open")
	check(is_equal_approx(float(track.get("heal_left", 0.0)), SquadScript.BANDAGE_SECONDS),
		"and it is the bandage's own length, got %s" % str(track.get("heal_left", 0.0)))
	check(warband.stash.pooled_count(BANDAGE) == 2,
		"nothing is spent while the dressing is still being tied")

	# Half the channel later the dressing is still in the stash, and the wound is
	# still open.
	track["heal_left"] = SquadScript.BANDAGE_SECONDS * 0.5
	check(_squad._bandage_step(body, _merc_id, track, 0.016), "the channel holds the body")
	check(warband.stash.pooled_count(BANDAGE) == 2, "a half tied bandage is not spent")

	# A hostile inside the clear range interrupts it, and the dressing survives.
	var watcher := FakeWatcher.new()
	root.add_child(watcher)
	watcher.global_position = body.global_position + Vector3(3.0, 0.0, 0.0)
	_squad.watchers = [watcher]
	check(not _squad._bandage_step(body, _merc_id, track, 0.016),
		"a hostile in reach drops the work unfinished")
	check(not bool(track.get("bandaging", false)), "the channel is abandoned")
	check(warband.stash.pooled_count(BANDAGE) == 2,
		"and an interrupted dressing is not spent")
	check(is_equal_approx(body.health, body.max_health * 0.4),
		"the wound is exactly as it was")

	# Quiet again: the channel reopens and the finished dressing closes a share of
	# the body's own pool.
	watcher.global_position = body.global_position + Vector3(400.0, 0.0, 0.0)
	check(_squad._bandage_step(body, _merc_id, track, 0.016), "the ally goes back to it")
	track["heal_left"] = 0.0
	check(not _squad._bandage_step(body, _merc_id, track, 0.016),
		"the last tick of the channel is the one that closes the wound")
	check(warband.stash.pooled_count(BANDAGE) == 1, "the dressing is spent")
	check(is_equal_approx(body.health, body.max_health * (0.4 + SquadScript.BANDAGE_HEAL_SHARE)),
		"the wound closes by the bandage's share, got %s" % str(body.health))
	check(is_equal_approx(float(warband.roster.health_of(_merc_id)), body.health),
		"and the roster records the patched body, not the wound")
	check(not bool(track.get("bandaging", false)), "the channel is closed")

	# The last dressing, spent on a body that does not need it, stays in the stash.
	body.health = body.max_health
	check(not _squad._wants_bandage(body, _merc_id), "a patched body stops asking")

	await check_rescue()

	print("SQUAD_MEDICINE_REGRESSION checks=", checks, " failures=", failures)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	quit(0 if failures == 0 else 1)

## The squad picks the soul up: a downed body, a clear field, an ally standing
## over it, five seconds and a revival. An enemy in range stops the whole idea.
func check_rescue() -> void:
	var channel = ReviveScript.new()
	root.add_child(channel)
	var soul := FakeBody.new()
	soul.name = "Soul"
	soul.downed = true
	root.add_child(soul)
	var ally := FakeBody.new()
	ally.name = "Ally"
	ally.is_bot = true
	root.add_child(ally)
	ally.global_position = soul.global_position + Vector3(1.0, 0.0, 0.0)
	channel.set_bodies([ally, soul])
	channel.reach = 2.5
	_squad.revive = channel
	_squad.player_body = soul
	var ally_id: int = _merc_id
	_squad.squad_ids = _ids([ally_id])
	var squad_controller := FakeController.new()
	squad_controller.bodies = {ally_id: ally}
	_squad.controller = squad_controller

	# An enemy standing on the body: the squad fights instead of bending down.
	var enemy := FakeWatcher.new()
	root.add_child(enemy)
	enemy.global_position = soul.global_position + Vector3(4.0, 0.0, 0.0)
	_squad.watchers = [enemy]
	check(not _squad._rescue_step(1.0 / 60.0),
		"a hostile in the yard stops the rescue before it starts")
	check(not channel.channeling(ReviveScript.ALLY_PEER),
		"and no channel is open with a body on the floor")

	# Clear field: the ally opens the save.
	enemy.global_position = soul.global_position + Vector3(400.0, 0.0, 0.0)
	check(_squad._rescue_step(1.0 / 60.0), "the nearest ally takes the rescue")
	check(channel.channeling(ReviveScript.ALLY_PEER),
		"and the squad's own hands open a channel")
	for index in 60:
		channel.tick(0.1)
		if index == 30:
			check(soul.downed, "three seconds in, the channel has not saved anybody")
	check(not soul.downed, "the soul is picked up")
	check(is_equal_approx(soul.health, soul.max_health * 0.05),
		"a rescued body comes back on a twentieth of its pool (%.1f)" % soul.health)

	# Standing: nothing to rescue, nothing left open.
	soul.downed = false
	_squad._rescue_step(1.0 / 60.0)
	check(not channel.channeling(ReviveScript.ALLY_PEER),
		"a standing body leaves no open channel")


func _ids(values: Array) -> Array[int]:
	var out: Array[int] = []
	for value in values:
		out.append(int(value))
	return out


func _track() -> Dictionary:
	return {"state": 0, "state_left": 0.0, "step_left": 0.0, "heal_left": 0.0,
		"bandaging": false, "side": 0.0, "sign": 1.0}

# --- doubles ---------------------------------------------------------------

## A rigged mercenary is a body, a combat clock and an intent channel; that is
## everything the medicine rule reads.
class FakeController:
	var bodies: Dictionary = {}

	func body_of(merc_id: int):
		return bodies.get(merc_id, null)

	func merc_of(body) -> int:
		for merc_id in bodies:
			if bodies[merc_id] == body:
				return int(merc_id)
		return -1


class FakeCombat:
	func stop_block() -> void:
		pass

	func stop() -> void:
		pass

class FakeBody extends Node3D:
	var health := 100.0
	var max_health := 100.0
	var combat := FakeCombat.new()
	var move_direction := Vector2.ZERO
	var run_requested := false
	var alive := true
	var downed := false
	var is_bot := false

	func accept_network_input(_direction: Vector2, _running: bool) -> void:
		pass

	func revive_from_downed(fraction: float = 0.05) -> void:
		downed = false
		health = max_health * fraction

class FakeWatcher extends Node3D:
	var alive := true
