extends SceneTree
## A party member's disposition: the tank, the melee body and the bow.
##
## The party's mode (`squad_party_mode_regression`) says which fights the band
## takes. This is the other half - how each body takes them - and it is measured
## where it lands:
##
##   1. the vocabulary (`WarbandContracts`): three ids, the default, the step a
##      press makes, each disposition's skill order and what a piece is worth to it;
##   2. the record: one field per mercenary, sanitised on the way in and out of a
##      save, and the warband verb that writes it (a lent band and a typo refused);
##   3. the automatic arming: a tank takes a shield and a one-hander over a dearer
##      greatsword, a melee body takes the greatsword, a bow takes the bow, and a
##      pickup only displaces what it is actually worth more than to that body;
##   4. the behaviour: a tank advances and waits behind its guard and never falls
##      back, a melee body falls back under 30% to bind its wound and goes at the
##      densest knot, a bow gives ground when struck or crowded and looses again
##      from range, and each of them casts the skill its order names first.
##
## The bodies here are doubles: the fight ladder writes intent, blocks and
## abilities through the same handholds a rigged mercenary offers, so what is
## measured is the disposition's rule and nothing of the scene.

const SquadScript = preload("res://scripts/warband/squad_drive.gd")
const Stamina = preload("res://scripts/stamina.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const RosterScript = preload("res://scripts/warband/warband_roster.gd")

const TEST_SAVE := "user://squad_disposition_state.json"

var checks := 0
var failures := 0
var warband
var squad
var bods: Dictionary = {}

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("SQUAD_DISPOSITION_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	warband = root.get_node("Warband")
	warband.save_path = TEST_SAVE
	warband.reset_state()

	check_contract()
	check_record()
	check_arming()
	check_withdraw()
	check_kite()
	check_dry_bow()
	check_blocking()
	check_cluster()
	check_casting()
	check_escort_rank()

	print("SQUAD_DISPOSITION_REGRESSION checks=", checks, " failures=", failures)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	quit(0 if failures == 0 else 1)


# --- 1. the vocabulary -----------------------------------------------------

func check_contract() -> void:
	check(Contracts.DISPOSITIONS == ["tank", "melee", "bow"],
		"three dispositions, front line first (%s)" % str(Contracts.DISPOSITIONS))
	check(Contracts.DEFAULT_DISPOSITION == "melee",
		"a body never told otherwise is a melee body")
	check(Contracts.disposition_id("TANK") == "tank", "a saved id reads back in any case")
	check(Contracts.disposition_id("berserk") == Contracts.DEFAULT_DISPOSITION,
		"a word this build does not know falls to the default")
	check(Contracts.disposition_exact("berserk").is_empty(),
		"and the refusing reader returns nothing for it")
	check(Contracts.disposition_exact("Bow") == "bow", "the refusing reader takes a real id")

	var stepped: Array[String] = []
	var current := Contracts.DISPOSITION_TANK
	for _step in 3:
		current = Contracts.next_disposition(current)
		stepped.append(current)
	check(stepped == ["melee", "bow", "tank"],
		"a press walks TANK, MELEE, BOW and round again (%s)" % str(stepped))

	for disposition in Contracts.DISPOSITIONS:
		check(not Contracts.disposition_label(disposition).is_empty(),
			"%s has a label" % disposition)
		check(not Contracts.disposition_text(disposition).is_empty(),
			"%s has a line the roster can print" % disposition)

	# Each disposition's first skill, and the skills it refuses outright.
	check(Contracts.disposition_ability_rank("tank", "shield_slam")
			< Contracts.disposition_ability_rank("tank", "double_slash"),
		"a tank reaches for the shield before the blade")
	check(Contracts.disposition_ability_rank("tank", "energy_shield") == 0,
		"and for the ward before either")
	check(Contracts.disposition_ability_rank("melee", "spin_slash") == 0,
		"a melee body's first skill is the ring")
	check(Contracts.disposition_ability_rank("melee", "spin_slash")
			< Contracts.disposition_ability_rank("melee", "double_slash"),
		"the AOE skill outranks the narrow arc")
	check(Contracts.disposition_ability_rank("bow", "barrage") == 0,
		"a bow's first skill is its own volley")
	check(Contracts.disposition_ability_rank("bow", "spin_slash") == Contracts.ABILITY_NEVER,
		"and a bow never spins a blade it is not holding")
	check(Contracts.disposition_ability_rank("melee", "barrage") == Contracts.ABILITY_NEVER,
		"a melee body never looses a volley")
	check(Contracts.disposition_ability_rank("melee", "not_a_skill") == Contracts.ABILITY_OTHER,
		"a skill the table has not met yet is still usable")

	# What a piece is worth to each body, at the same price.
	var greatsword := {"category": "2h"}
	var shield := {"category": "shield"}
	var bow := {"category": "bow"}
	var one_hand := {"category": "1h"}
	check(Contracts.disposition_gear_score("tank", shield, 280)
			> Contracts.disposition_gear_score("tank", greatsword, 340),
		"a tank's tower shield beats a dearer greatsword")
	check(Contracts.disposition_gear_score("tank", one_hand, 195)
			> Contracts.disposition_gear_score("tank", greatsword, 340),
		"and so does a one-hander, so the shield hand is never locked")
	check(Contracts.disposition_gear_score("melee", greatsword, 340)
			> Contracts.disposition_gear_score("melee", one_hand, 195),
		"a melee body still takes the greatsword")
	check(Contracts.disposition_gear_score("bow", bow, 120)
			> Contracts.disposition_gear_score("bow", greatsword, 340),
		"a bow takes a cheap bow over a dear greatsword")
	check(Contracts.disposition_gear_score("melee", bow, 120)
			< Contracts.disposition_gear_score("melee", greatsword, 340) - 300.0,
		"and a melee body never trades its blade for one")

	# A weight only makes a piece expensive; a refusal makes it never picked. A
	# melee body and a tank do not reach for a bow or a staff, however empty the
	# hand - the arming waits for the blade instead (a body the player dresses by
	# hand is not asked).
	var staff := {"kind": "staff", "category": "staff"}
	var bow_item := {"kind": "bow", "category": "bow"}
	check(Contracts.disposition_refuses_gear("melee", bow_item),
		"a melee body's arming never reaches for a bow")
	check(Contracts.disposition_refuses_gear("tank", bow_item),
		"nor a tank's")
	check(Contracts.disposition_refuses_gear("melee", staff),
		"and a staff is no more a blade's business")
	check(not Contracts.disposition_refuses_gear("bow", bow_item),
		"a bow body's arming reaches for its own bow")
	check(not Contracts.disposition_refuses_gear("bow", {"kind": "sword", "category": "1h"}),
		"and for a blade when the pool holds no bow")
	check(not Contracts.disposition_refuses_gear("melee", greatsword),
		"a melee body's greatsword is never refused")
	check(Contracts.gear_kind({"kind": "dagger", "category": "1h"}) == "dagger",
		"a piece is read by its kind first, so a knife is never a sword")
	check(Contracts.gear_kind({"category": "2h"}) == "2h",
		"and by its category when the catalogue names no kind")


# --- 2. the record and the verb --------------------------------------------

func check_record() -> void:
	var rookie: int = warband.add_mercenary("Rook")
	check(warband.roster.disposition_of(rookie) == Contracts.DEFAULT_DISPOSITION,
		"a fresh body is a melee body")

	var told := [0]
	var count := func() -> void: told[0] += 1
	warband.changed.connect(count)
	var result: Dictionary = warband.set_disposition(rookie, Contracts.DISPOSITION_TANK)
	check(bool(result.get("ok", false))
			and warband.roster.disposition_of(rookie) == Contracts.DISPOSITION_TANK,
		"the band takes a disposition (%s)" % str(result.get("message", "")))
	check(told[0] == 1, "and says so once (%d)" % told[0])
	warband.set_disposition(rookie, Contracts.DISPOSITION_TANK)
	check(told[0] == 1, "the disposition it already has is no change (%d)" % told[0])
	result = warband.set_disposition(rookie, "berserk")
	check(not bool(result.get("ok", true))
			and warband.roster.disposition_of(rookie) == Contracts.DISPOSITION_TANK,
		"an unknown disposition is refused and the body keeps its own")
	result = warband.set_disposition(9999, Contracts.DISPOSITION_BOW)
	check(not bool(result.get("ok", true)), "and so is a mercenary that does not exist")
	warband.changed.disconnect(count)

	result = warband.cycle_disposition(rookie)
	check(str(result.get("disposition", "")) == Contracts.DISPOSITION_MELEE,
		"a step goes TANK to MELEE")
	result = warband.cycle_disposition(rookie)
	check(str(result.get("disposition", "")) == Contracts.DISPOSITION_BOW,
		"and MELEE to BOW")
	warband.cycle_disposition(rookie)
	check(warband.roster.disposition_of(rookie) == Contracts.DISPOSITION_TANK,
		"and BOW back to TANK")

	# The field is the record's, so a save carries it and a file without it - or
	# with a word this build has never heard of - comes up as the default.
	warband.save_state()
	warband.reset_state()
	check(warband.roster.disposition_of(rookie) == Contracts.DEFAULT_DISPOSITION,
		"a reset is a fresh band of melee bodies")
	check(warband.load_state()
			and warband.roster.disposition_of(rookie) == Contracts.DISPOSITION_TANK,
		"a body's disposition survives a save")
	var old: Dictionary = warband.to_dict()
	for merc in old["roster"]["mercenaries"]:
		merc.erase(RosterScript.KEY_DISPOSITION)
	warband.from_dict(old)
	check(warband.roster.disposition_of(rookie) == Contracts.DEFAULT_DISPOSITION,
		"a file written before the field existed fields melee bodies")
	old = warband.to_dict()
	for merc in old["roster"]["mercenaries"]:
		merc[RosterScript.KEY_DISPOSITION] = "berserk"
	warband.from_dict(old)
	check(warband.roster.disposition_of(rookie) == Contracts.DEFAULT_DISPOSITION,
		"and so does one carrying a disposition this build has never heard of")

	# A lent warband's bodies are the host's to command.
	warband.set_disposition(rookie, Contracts.DISPOSITION_TANK)
	warband.lent = true
	result = warband.set_disposition(rookie, Contracts.DISPOSITION_BOW)
	check(not bool(result.get("ok", true))
			and warband.roster.disposition_of(rookie) == Contracts.DISPOSITION_TANK,
		"a lent warband's body keeps the host's disposition (%s)" % str(result.get("message", "")))
	result = warband.cycle_disposition(rookie)
	check(not bool(result.get("ok", true)), "and a step is refused with it")
	warband.lent = false


# --- 3. the automatic arming ------------------------------------------------

func check_arming() -> void:
	warband.reset_state()
	var tank: int = warband.add_mercenary("Wall")
	var melee: int = warband.add_mercenary("Press")
	var bow: int = warband.add_mercenary("Loft")
	warband.set_disposition(tank, Contracts.DISPOSITION_TANK)
	warband.set_disposition(bow, Contracts.DISPOSITION_BOW)
	for item_id in ["sword_great", "sword_arming", "shield_kite", "bow_short"]:
		warband.stash.add(item_id, 3)

	var fitted: Dictionary = warband.dress_recruit(tank)
	check(bool(fitted.get("ok", false)), "the tank is dressed (%s)" % str(fitted.get("message", "")))
	var tank_gear: Dictionary = warband.roster.equipped_of(tank)
	check(str(tank_gear.get("main", "")) == "sword_arming",
		"a tank takes the one-hander over the dearer greatsword, got %s" % str(tank_gear.get("main", "")))
	check(str(tank_gear.get("off", "")) == "shield_kite",
		"and a shield in the other hand, got %s" % str(tank_gear.get("off", "")))

	warband.dress_recruit(melee)
	var melee_gear: Dictionary = warband.roster.equipped_of(melee)
	check(str(melee_gear.get("main", "")) == "sword_great",
		"a melee body takes the greatsword, got %s" % str(melee_gear.get("main", "")))
	check(str(melee_gear.get("off", "")).is_empty(),
		"and a two-hander leaves the other hand empty")

	warband.dress_recruit(bow)
	var bow_gear: Dictionary = warband.roster.equipped_of(bow)
	check(str(bow_gear.get("main", "")) == "bow_short",
		"a bow body takes the bow, got %s" % str(bow_gear.get("main", "")))
	check(str(bow_gear.get("off", "")).is_empty(),
		"and a bow leaves the other hand empty")

	# A pickup only displaces a piece it is worth more than *to that body*.
	warband.stash.add("sword_short", 1)
	warband.equip_merc(bow, "main", "sword_short")
	var snap: Dictionary = warband.auto_equip(bow, "bow_short")
	check(bool(snap.get("ok", false)) and str(snap.get("slot", "")) == "main",
		"a bow that reaches a bowman's hands is taken up (%s)" % str(snap.get("message", "")))
	check(str(warband.roster.equipped_of(bow).get("main", "")) == "bow_short",
		"and the bow is what it holds")
	snap = warband.auto_equip(bow, "sword_great")
	check(not bool(snap.get("ok", true)),
		"a dearer blade does not take a bowman's bow")
	# The melee body has the greatsword in its hands and no use for a bow.
	warband.stash.add("bow_short", 1)
	snap = warband.auto_equip(melee, "bow_short")
	check(not bool(snap.get("ok", true)),
		"a melee body does not trade its blade for a bow")
	# The tank keeps its one-hander and takes a shield it did not have.
	warband.unequip_merc(tank, "off")
	snap = warband.auto_equip(tank, "shield_kite")
	check(bool(snap.get("ok", false)) and str(snap.get("slot", "")) == "off",
		"a tank takes a shield into an empty off hand (%s)" % str(snap.get("message", "")))

	# A bow is not a blade's spare. The band's pool can run out of blades while a
	# bow is still lying in it, and the arming used to close the empty hand on the
	# bow: a melee body then walked the field with a weapon its trade never draws.
	# Two melee bodies, one blade and one bow between them.
	warband.reset_state()
	var point: int = warband.add_mercenary("Point")
	var rear: int = warband.add_mercenary("Rear")
	warband.stash.add("sword_short", 1)
	warband.stash.add("bow_short", 1)
	warband.dress_recruit(point)
	warband.dress_recruit(rear)
	check(str(warband.roster.equipped_of(point).get("main", "")) == "sword_short",
		"the blade in the pool goes to a melee body (%s)"
			% str(warband.roster.equipped_of(point).get("main", "")))
	check(str(warband.roster.equipped_of(rear).get("main", "")).is_empty(),
		"and a melee body left without one keeps its hands empty for the next blade, got %s"
			% str(warband.roster.equipped_of(rear).get("main", "")))
	check(warband.stash.pooled_count("bow_short") == 1,
		"the bow waits in the pool for a body that draws it")
	snap = warband.auto_equip(rear, "bow_short")
	check(not bool(snap.get("ok", true)),
		"a bow does not snap into an empty-handed melee body's main hand")
	check(str(warband.roster.equipped_of(rear).get("main", "")).is_empty(),
		"and the hand stays empty")
	var tank_refusal: Dictionary = warband.auto_equip(rear, "staff_fire")
	check(not bool(tank_refusal.get("ok", true)),
		"nor a staff, which a blade cannot swing either")
	# The same bow is the bow body's own: the refusal is the trade's, not the pool's.
	warband.set_disposition(rear, Contracts.DISPOSITION_BOW)
	warband.dress_recruit(rear)
	check(str(warband.roster.equipped_of(rear).get("main", "")) == "bow_short",
		"and a bow body takes the bow the melee body refused (%s)"
			% str(warband.roster.equipped_of(rear).get("main", "")))
	# The player's own hand is not the arming's: the paperdoll may still dress a
	# melee body with a bow, and `auto_equip`'s refusal is what the band's side of
	# the choice obeys.
	check(not Contracts.disposition_refuses_gear(Contracts.DISPOSITION_BOW,
		PlayerState.ITEMS["sword_short"]),
		"a bow body still reaches for a blade when the pool has no bow")


# --- 4. the behaviour ------------------------------------------------------

## A body the ladder can write to: position, health, a rig's hands and phase, the
## combat clock, an intent channel and a skill runner.
class FakeBody extends Node3D:
	var last_intent := Vector2.ZERO
	var running := false
	var move_direction := Vector2.ZERO
	var alive := true
	var downed := false
	var health := 100.0
	var max_health := 100.0
	var stamina := 100.0
	var ward_seconds := 0.0
	var rig := FakeRig.new()
	var combat := FakeCombat.new()
	var ability = null

	func accept_network_input(direction: Vector2, run: bool) -> void:
		last_intent = direction
		running = run

	func try_ability(slot: int) -> Dictionary:
		return ability.activate(slot) if ability != null else {"ok": false}

	func get_aim_position() -> Vector3:
		return global_position + Vector3(0.0, 1.4, 0.0)


class FakeRig extends RefCounted:
	var weapon := "sword"
	var phase := "READY"
	var draw_amount := 0.0
	var bow_index := 0
	var staff_active := false
	var off_weapon_active := false

	func can_begin_melee(_hand: String) -> bool:
		return false


class FakeCombat extends RefCounted:
	var damage_enabled := true
	var blocking := false
	var attack_progress := 1.0
	var clash_cooldown := 0.0
	var aim_point := Vector3.ZERO
	var dry := false
	var draws := 0

	func stop_block() -> void:
		blocking = false

	func start_block(_forward: Vector3) -> bool:
		blocking = true
		return true

	func face_block(_forward: Vector3) -> void:
		pass

	func stop() -> void:
		blocking = false

	func set_aim(point: Vector3) -> void:
		aim_point = point

	func quiver_empty() -> bool:
		return dry

	func can_draw() -> bool:
		return not dry

	func begin_draw() -> bool:
		draws += 1
		return true

	func release_draw() -> void:
		pass


## A hostile: a position, the flag the target search reads and an aim point.
class FakeWatcher extends Node3D:
	var alive := true
	var last_hitter = null

	func get_aim_position() -> Vector3:
		return global_position + Vector3(0.0, 1.4, 0.0)


class FakeRunner extends RefCounted:
	var defs: Dictionary = {}
	var fired: Array[int] = []
	var active := false

	func definition(slot: int) -> Dictionary:
		return defs.get(slot, {})

	func blocker(_slot: int) -> String:
		return ""

	func activate(slot: int) -> Dictionary:
		fired.append(slot)
		return {"ok": true, "definition": definition(slot)}


class FakeWarband extends RefCounted:
	var roster := FakeRoster.new()

## The one field the squad reads off the books: how each body fights.
class FakeRoster extends RefCounted:
	var styles: Dictionary = {}
	var gear: Dictionary = {}

	func disposition_of(merc_id: int) -> String:
		return Contracts.disposition_id(styles.get(merc_id, ""))

	func equipped_of(_merc_id: int) -> Dictionary:
		return gear


class FakeController extends RefCounted:
	var bodies: Dictionary = {}

	func body_of(merc_id: int):
		return bodies.get(merc_id, null)

	func focus_body():
		return null

	func merc_of(body) -> int:
		for merc_id in bodies:
			if bodies[merc_id] == body:
				return int(merc_id)
		return 0

	func refresh_gear(_merc_id: int) -> void:
		pass


func _squad_for(merc_id: int, style: String):
	var fake := FakeWarband.new()
	fake.roster.styles[merc_id] = style
	var drive = SquadScript.new()
	drive.setup(fake, null, null)
	return drive


func _body_at(at: Vector3) -> FakeBody:
	var body := FakeBody.new()
	root.add_child(body)
	body.global_position = at
	return body


func _watcher_at(at: Vector3) -> FakeWatcher:
	var watcher := FakeWatcher.new()
	root.add_child(watcher)
	watcher.global_position = at
	return watcher


## The clocks and rolls the fight ladder reads, as `_track_for` would have left
## them for a body in the open with nothing to do.
func _track(merc_id: int) -> Dictionary:
	return {"merc_id": merc_id, "delta": 1.0 / 20.0, "side": 0.0, "sign": 1.0,
		"state": 0, "state_left": 0.0, "step_left": 0.0, "cast_lock": 0.0,
		"withdraw_left": 0.0, "withdrawing": false, "withdraw_failed": false,
		"hurt_left": 0.0, "orbit": 1.0, "retreat": 0.0}


## Below its share a melee body walks out of the fight; a tank never does.
func check_withdraw() -> void:
	var host = _watcher_at(Vector3(4.0, 0.0, 0.0))
	for style in [Contracts.DISPOSITION_MELEE, Contracts.DISPOSITION_BOW, Contracts.DISPOSITION_TANK]:
		var body := _body_at(Vector3.ZERO)
		var drive = _squad_for(1, style)
		drive.watchers = [host]
		var track := _track(1)
		var profile: Dictionary = SquadScript.profile_of(style)
		body.health = body.max_health * 0.29
		var gave := drive._withdraw_step(body, track, profile)
		if style == Contracts.DISPOSITION_TANK:
			check(not gave,
				"a tank at 29%% does not give ground (never falls back)")
			check(float(track.get("withdraw_left", 0.0)) <= 0.0,
				"and keeps no retreat clock at all")
		else:
			check(gave, "a %s body at 29%% falls back" % style)
			check(Vector2(body.last_intent).length() > 0.0, "and it is walking (%s)"
				% str(body.last_intent))
			var away := Vector2(-1.0, 0.0)
			var heading := Vector2(body.last_intent).normalized()
			check(heading.dot(away) > 0.9,
				"away from the hostile, not into it (%s)" % str(heading))
			check(body.running, "at a jog, not a walk")
		body.health = body.max_health * 0.45
		check(not drive._withdraw_step(body, track, profile),
			"a %s body at 45%% keeps fighting" % style)
		body.health = body.max_health * 0.2
		host.global_position = Vector3(400.0, 0.0, 0.0)
		check(not drive._withdraw_step(body, track, profile),
			"and a %s body with the field clear has nothing to fall back from" % style)
		host.global_position = Vector3(4.0, 0.0, 0.0)

	# A withdrawal that cannot break contact gives up instead of leading the band
	# across the wood, and the latch clears when the wound is closed.
	var body := _body_at(Vector3.ZERO)
	var drive = _squad_for(2, Contracts.DISPOSITION_MELEE)
	drive.watchers = [host]
	var track := _track(2)
	var profile: Dictionary = SquadScript.profile_of(Contracts.DISPOSITION_MELEE)
	body.health = body.max_health * 0.2
	check(drive._withdraw_step(body, track, profile), "a hurt body starts backing off")
	track["withdraw_left"] = 0.0
	check(not drive._withdraw_step(body, track, profile),
		"a withdrawal that ran out of clock stops")
	check(bool(track.get("withdraw_failed", false)), "and remembers it could not get clear")
	body.health = body.max_health
	drive._withdraw_step(body, track, profile)
	check(not bool(track.get("withdraw_failed", true)),
		"a closed wound clears the latch, so the next one tries again")


## The back line gives ground when a blade is in its face or a wound is fresh, and
## looses again from range.
func check_kite() -> void:
	var host = _watcher_at(Vector3(3.0, 0.0, 0.0))
	var body := _body_at(Vector3.ZERO)
	body.rig.weapon = "bow"
	var drive = _squad_for(3, Contracts.DISPOSITION_BOW)
	var profile: Dictionary = SquadScript.profile_of(Contracts.DISPOSITION_BOW)
	var track := _track(3)
	check(drive._kite_step(body, track, profile, Vector3.RIGHT, 3.0),
		"a bow with a hostile inside its hold gives ground")
	check(Vector2(body.last_intent).normalized().dot(Vector2(-1.0, 0.0)) > 0.9,
		"walking away from it (%s)" % str(body.last_intent))
	check(body.running, "at a jog")
	check(int(track.get("state", -1)) != SquadScript.FIGHT_GUARD,
		"and it is not planting for a guard it cannot raise")

	# At range with no fresh wound it plants and looses: nothing to reposition.
	check(not drive._kite_step(body, track, profile, Vector3.RIGHT, 12.0),
		"a bow at range with a steady hand does not move")

	# A wound is the "on hit" half: the same backstep, whatever the range.
	track["hurt_left"] = SquadScript.KITE_HIT_MEMORY
	check(drive._kite_step(body, track, profile, Vector3.RIGHT, 7.0),
		"a struck bow re-positions")
	check(not drive._kite_step(body, track, profile, Vector3.RIGHT, 12.0),
		"a struck bow at its own range plants and looses instead")
	check(not drive._kite_step(body, track, profile, Vector3.RIGHT, 30.0),
		"but never walks out of the range it shoots from")

	# A corner is not a range: an archer that cannot gain ground stops backing and
	# shoots instead of walking into the wall for the rest of the fight.
	track["hurt_left"] = SquadScript.KITE_HIT_MEMORY
	track["kite_best"] = 0.0
	track["kite_stuck"] = 0.0
	var backed := 0
	for index in 30:
		track["delta"] = 1.0 / 20.0
		if drive._kite_step(body, track, profile, Vector3.RIGHT, 3.0):
			backed += 1
	check(backed > 0 and backed < 30,
		"a cornered bow gives ground for a moment and then looses (%d of 30 frames)" % backed)
	check(not drive._kite_step(body, track, profile, Vector3.RIGHT, 3.0),
		"and once it has given up the corner it stands and fires")
	check(drive._kite_step(body, track, profile, Vector3.RIGHT, 4.0),
		"with ground to give again, the retreat comes back")

	# A drawn string is never abandoned for the feet.
	body.rig.phase = "DRAWING"
	check(not drive._kite_step(body, track, profile, Vector3.RIGHT, 3.0),
		"a drawn string looses before the feet move")
	body.rig.phase = "READY"

	# A blade does not kite at all.
	var melee := _body_at(Vector3.ZERO)
	var press = _squad_for(4, Contracts.DISPOSITION_MELEE)
	check(not press._kite_step(melee, _track(4),
		SquadScript.profile_of(Contracts.DISPOSITION_MELEE), Vector3.RIGHT, 4.0),
		"a melee body never kites")


## A bow with an empty quiver is not a weapon. It cannot be drawn and it cannot be
## swung, so the body counts itself unarmed (the intent ladder's errand is steel),
## gives ground out of a blade's measure and plants at its own - and never circles
## a hostile it can never hurt, which is what a bow body with a spent quiver used
## to do at contact.
func check_dry_bow() -> void:
	var host = _watcher_at(Vector3(2.0, 0.0, 0.0))
	var body := _body_at(Vector3.ZERO)
	body.rig.weapon = "bow"
	body.combat.dry = true
	var drive = _squad_for(8, Contracts.DISPOSITION_MELEE)
	drive.watchers = [host]
	drive.warband.roster.gear = {"main": "bow_short", "off": ""}
	check(not drive._armed(body, 8),
		"a bow with an empty quiver does not count as armed")
	check(drive._dry_bow(body), "and the ladder knows why")

	var track := _track(8)
	drive._fight_watcher(body, host, track)
	check(int(track.get("state", -1)) != SquadScript.FIGHT_CIRCLE,
		"a dry bow never circles a hostile it cannot hurt")
	check(Vector2(body.last_intent).normalized().dot(Vector2(-1.0, 0.0)) > 0.9,
		"it gives ground out of a blade's measure (%s)" % str(body.last_intent))
	check(body.running, "at a jog")

	# At its own range the feet stop: the ground it wanted is behind it now.
	host.global_position = Vector3(12.0, 0.0, 0.0)
	drive._fight_watcher(body, host, _track(8))
	check(Vector2(body.last_intent).length() < 0.01,
		"and plants once it has the bow's range (%s)" % str(body.last_intent))

	# The same frame taken through the close-fight path: no call circles on a dry
	# string, whichever door the ladder came through.
	var close := _track(8)
	drive._fight_bow(body, close, Vector3.RIGHT, 2.0)
	check(int(close.get("state", -1)) != SquadScript.FIGHT_CIRCLE,
		"and the close-fight path never circles it either")
	check(body.combat.draws == 0, "while a dry string is never drawn")

	# A shaft in the quiver puts the bow back to work: the same body counts as
	# armed and the close fight draws instead of backing off.
	body.combat.dry = false
	check(drive._armed(body, 8), "a loaded bow counts as armed again")
	var shoot := _track(8)
	drive._fight_bow(body, shoot, Vector3.RIGHT, 2.0)
	check(body.combat.draws == 1, "and the bow draws again")


## A tank advances behind its guard and waits behind it between exchanges; a
## melee body walks with the blade down and stands open.
func check_blocking() -> void:
	var host = _watcher_at(Vector3(5.0, 0.0, 0.0))
	var tank_body := _body_at(Vector3.ZERO)
	tank_body.rig.weapon = "sword"
	var tank = _squad_for(5, Contracts.DISPOSITION_TANK)
	tank.watchers = [host]
	var tank_track := _track(5)
	tank._fight_watcher(tank_body, host, tank_track)
	check(tank_body.combat.blocking, "a tank closes behind a raised guard")
	check(Vector2(tank_body.last_intent).x > 0.5,
		"and it is still closing (%s)" % str(tank_body.last_intent))

	var press_body := _body_at(Vector3(0.0, 0.0, 2.0))
	press_body.rig.weapon = "sword"
	var press = _squad_for(6, Contracts.DISPOSITION_MELEE)
	press.watchers = [host]
	press._fight_watcher(press_body, host, _track(6))
	check(not press_body.combat.blocking, "a melee body closes with the blade down")

	# At contact the difference is the same: the tank waits behind the guard, the
	# melee body stands in the beat between exchanges.
	host.global_position = Vector3(1.3, 0.0, 0.0)
	tank._fight_watcher(tank_body, host, tank_track)
	check(tank_body.combat.blocking, "a tank holds its guard at contact")
	press._fight_watcher(press_body, host, _track(6))
	check(not press_body.combat.blocking, "a melee body stands open at contact")

	# A spent tank is the one thing a shield cannot buy: the body's own tick drops
	# the arm at zero (`_resolve_motion`), so the squad asks the same pool floor a
	# player's press does instead of raising a guard it cannot hold.
	var spent_body := _body_at(Vector3.ZERO)
	spent_body.rig.weapon = "sword"
	spent_body.stamina = Stamina.GUARD_MIN - 1.0
	var spent = _squad_for(7, Contracts.DISPOSITION_TANK)
	spent.watchers = [host]
	spent._fight_watcher(spent_body, host, _track(7))
	check(not spent_body.combat.blocking,
		"a tank under the guard floor does not raise an arm")
	spent_body.stamina = Stamina.MAX
	spent._fight_watcher(spent_body, host, _track(7))
	check(spent_body.combat.blocking,
		"and the same tank raises one again once the pool knits back")

	# The rolled window is the disposition's too.
	var tank_profile: Dictionary = SquadScript.profile_of(Contracts.DISPOSITION_TANK)
	var melee_profile: Dictionary = SquadScript.profile_of(Contracts.DISPOSITION_MELEE)
	check(float(tank_profile["guard_chance_min"]) >= 0.9,
		"a tank is up nearly every exchange (%s)" % str(tank_profile["guard_chance_min"]))
	check(float(melee_profile["guard_chance_min"]) < 0.5,
		"a melee body spends its turns attacking (%s)" % str(melee_profile["guard_chance_min"]))
	check(float(tank_profile["guard_max"]) > float(melee_profile["guard_max"]),
		"and holds the window longer")
	check(is_equal_approx(float(tank_profile["withdraw"]), 0.0),
		"a tank's falling-back share is zero: it never gives ground")
	check(is_equal_approx(float(melee_profile["withdraw"]), SquadScript.WITHDRAW_SHARE)
			and is_equal_approx(SquadScript.WITHDRAW_SHARE, 0.30),
		"a melee body falls back below 30%% of its pool (%s)"
		% str(SquadScript.WITHDRAW_SHARE))
	check(is_equal_approx(float(SquadScript.profile_of(Contracts.DISPOSITION_BOW)["withdraw"]),
			SquadScript.WITHDRAW_SHARE),
		"and so does a bow")


## A melee body goes at the knot a ring lands on, not at the nearest blade.
func check_cluster() -> void:
	var lone = _watcher_at(Vector3(5.0, 0.0, 0.0))
	var pair_a = _watcher_at(Vector3(0.0, 0.0, 7.0))
	var pair_b = _watcher_at(Vector3(0.0, 0.0, 8.6))
	var body := _body_at(Vector3.ZERO)
	var drive = _squad_for(7, Contracts.DISPOSITION_MELEE)
	drive.watchers = [lone, pair_a, pair_b]
	check(drive._nearest_watcher(body, false) == lone,
		"without the AOE preference the nearest body is the target")
	check(drive._nearest_watcher(body, true) == pair_a,
		"with it, the knot outranks the nearer loner")
	check(drive._nearest_watcher(body) == lone,
		"and the plain search is unchanged for every other body")


## Each disposition reaches for its own skill first, and only where it fits.
func check_casting() -> void:
	var host = _watcher_at(Vector3(1.6, 0.0, 0.0))
	var second = _watcher_at(Vector3(2.4, 0.0, 0.9))
	var body := _body_at(Vector3.ZERO)
	var runner := FakeRunner.new()
	body.ability = runner

	var track := _track(8)
	var drive = _squad_for(8, Contracts.DISPOSITION_MELEE)
	drive.watchers = [host, second]

	# A melee body's table: the ring first. One target is not a ring's moment.
	runner.defs = {
		0: {"id": "spin_slash", "duration": 0.3,
			"effect": {"kind": "melee_ring", "radius": 2.9}},
		1: {"id": "double_slash", "duration": 0.3,
			"effect": {"kind": "melee_arc", "radius": 1.9, "arc_degrees": 150.0}},
	}
	check(drive._cast_step(body, track, SquadScript.profile_of(Contracts.DISPOSITION_MELEE),
		host, Vector3.RIGHT, 1.6), "a melee body casts when the moment fits")
	check(runner.fired == [0], "and it is the ring on a knot (%s)" % str(runner.fired))
	check(float(track.get("cast_lock", 0.0)) > 0.0, "the cadence is set")
	check(not drive._cast_step(body, track, SquadScript.profile_of(Contracts.DISPOSITION_MELEE),
		host, Vector3.RIGHT, 1.6), "and the next frame it does not cast again")

	# Only one hostile: the ring is not worth it, the arc is.
	drive.watchers = [host]
	track["cast_lock"] = 0.0
	runner.fired.clear()
	check(drive._cast_step(body, track, SquadScript.profile_of(Contracts.DISPOSITION_MELEE),
		host, Vector3.RIGHT, 1.6), "with one target the arc is the cast")
	check(runner.fired == [1], "and it is the wide cut (%s)" % str(runner.fired))

	# A skill the disposition refuses is never cast, however idle the body is.
	runner.defs = {0: {"id": "backstab", "duration": 0.3,
		"effect": {"kind": "backstab", "range": 8.0}}}
	track["cast_lock"] = 0.0
	runner.fired.clear()
	check(not drive._cast_step(body, track, SquadScript.profile_of(Contracts.DISPOSITION_MELEE),
		host, Vector3.RIGHT, 1.6), "a melee body never casts a blink it cannot aim")
	check(runner.fired.is_empty(), "and nothing fired")

	# A tank takes the ward first and the shield slam once it is up.
	var tank_body := _body_at(Vector3(0.0, 0.0, 1.0))
	var tank_runner := FakeRunner.new()
	tank_body.ability = tank_runner
	tank_runner.defs = {
		1: {"id": "shield_slam", "duration": 1.1,
			"effect": {"kind": "melee_ring", "radius": 2.9}},
		2: {"id": "energy_shield", "duration": 0.9,
			"effect": {"kind": "ward", "absorb": 0.5, "seconds": 60.0}},
	}
	var tank = _squad_for(9, Contracts.DISPOSITION_TANK)
	tank.watchers = [host, second]
	var tank_track := _track(9)
	check(tank._cast_step(tank_body, tank_track,
		SquadScript.profile_of(Contracts.DISPOSITION_TANK), host, Vector3.RIGHT, 1.6),
		"a tank casts its ward")
	check(tank_runner.fired == [2], "the ward comes before the shield (%s)" % str(tank_runner.fired))
	tank_body.ward_seconds = 30.0
	tank_track["cast_lock"] = 0.0
	tank_runner.fired.clear()
	check(tank._cast_step(tank_body, tank_track,
		SquadScript.profile_of(Contracts.DISPOSITION_TANK), host, Vector3.RIGHT, 1.6),
		"with the ward up the shield is next")
	check(tank_runner.fired == [1], "and it is the slam (%s)" % str(tank_runner.fired))
	# A raised guard is the front line's to spend on its own shield skill - and
	# comes back the frame after - while the other dispositions keep their window.
	tank_body.combat.blocking = true
	tank_track["cast_lock"] = 0.0
	tank_runner.fired.clear()
	check(tank._cast_step(tank_body, tank_track,
		SquadScript.profile_of(Contracts.DISPOSITION_TANK), host, Vector3.RIGHT, 1.6),
		"a tank spends its guard on the shield")
	check(tank_runner.fired == [1], "and the slam is what it spends it on (%s)"
		% str(tank_runner.fired))
	check(not tank_body.combat.blocking, "the guard comes down for the cast")
	runner.defs = {0: {"id": "spin_slash", "duration": 0.3,
		"effect": {"kind": "melee_ring", "radius": 2.9}}}
	drive.watchers = [host, second]
	body.combat.blocking = true
	track["cast_lock"] = 0.0
	runner.fired.clear()
	check(not drive._cast_step(body, track,
		SquadScript.profile_of(Contracts.DISPOSITION_MELEE), host, Vector3.RIGHT, 1.6),
		"a melee body behind its guard does not cast")
	check(runner.fired.is_empty(), "and nothing fired through the guard")
	body.combat.blocking = false

	# A bow looses the volley it holds and never spins a blade it does not carry.
	var bow_body := _body_at(Vector3(0.0, 0.0, 6.0))
	bow_body.rig.weapon = "bow"
	var bow_runner := FakeRunner.new()
	bow_body.ability = bow_runner
	bow_runner.defs = {
		0: {"id": "barrage", "duration": 1.15,
			"effect": {"kind": "barrage", "shots": 6}},
		1: {"id": "spin_slash", "duration": 0.3,
			"effect": {"kind": "melee_ring", "radius": 2.9}},
	}
	var bow = _squad_for(10, Contracts.DISPOSITION_BOW)
	bow.watchers = [host, second]
	var bow_track := _track(10)
	check(bow._cast_step(bow_body, bow_track, SquadScript.profile_of(Contracts.DISPOSITION_BOW),
		host, Vector3.RIGHT, 12.0), "a bow looses from range")
	check(bow_runner.fired == [0], "and it is the volley (%s)" % str(bow_runner.fired))
	bow_runner.defs = {1: {"id": "spin_slash", "duration": 0.3,
		"effect": {"kind": "melee_ring", "radius": 2.9}}}
	bow_track["cast_lock"] = 0.0
	bow_runner.fired.clear()
	check(not bow._cast_step(bow_body, bow_track,
		SquadScript.profile_of(Contracts.DISPOSITION_BOW), host, Vector3.RIGHT, 1.6),
		"a bow with only a spin in its hands does not cast it")
	check(bow_runner.fired.is_empty(), "and nothing fired")


## The band walks as a formation: tanks ahead, the melee wall a rank behind them,
## the bows behind that - and the same order whatever the soul itself is wearing,
## because the ranks are measured from the soul's body and not from how it fights.
## A soul inside a bow is the case that matters: a tank that only knows to stand
## ahead of a blade would drift behind the archer it is supposed to be covering for.
func check_escort_rank() -> void:
	var soul := _body_at(Vector3.ZERO)
	# One body per rank, all in a line so the ranks are the only thing that moves.
	var tank := _body_at(Vector3(0.0, 0.0, 3.0))
	var melee := _body_at(Vector3(0.0, 0.0, 1.0))
	var bow := _body_at(Vector3(0.0, 0.0, -1.0))
	var controller := FakeController.new()
	controller.bodies[11] = soul
	controller.bodies[12] = tank
	controller.bodies[13] = melee
	controller.bodies[14] = bow
	var fake := FakeWarband.new()
	fake.roster.styles[12] = Contracts.DISPOSITION_TANK
	fake.roster.styles[13] = Contracts.DISPOSITION_MELEE
	fake.roster.styles[14] = Contracts.DISPOSITION_BOW
	var drive = SquadScript.new()
	drive.setup(fake, controller, null)
	drive.player_body = soul
	var ids: Array[int] = [11, 12, 13, 14]
	drive.squad_ids = ids
	# The soul faces -Z (an untouched basis), so depth is measured down -z.
	var tank_at: Vector3 = drive._escort_post(tank, _track(12))
	var melee_at: Vector3 = drive._escort_post(melee, _track(13))
	var bow_at: Vector3 = drive._escort_post(bow, _track(14))
	var tank_depth := -tank_at.z
	var melee_depth := -melee_at.z
	var bow_depth := -bow_at.z
	check(tank_depth > 0.0,
		"the tank stands ahead of the soul (%.2f m)" % tank_depth)
	check(melee_depth < tank_depth and bow_depth < melee_depth,
		"tanks, then melee, then bows (%.2f / %.2f / %.2f m)"
		% [tank_depth, melee_depth, bow_depth])
	check(is_equal_approx(tank_depth, SquadScript.FORMATION_FRONT),
		"the front rank stands one `FORMATION_FRONT` ahead (%.2f m)" % tank_depth)
	check(is_equal_approx(absf(tank_at.x), SquadScript.FORMATION_LANE * 0.5)
		and is_equal_approx(melee_at.x, -SquadScript.FORMATION_LANE * 0.5)
		and is_equal_approx(absf(bow_at.x), SquadScript.FORMATION_LANE * 0.5),
		"a rank of one stands a half lane off the soul's line, never in its face"
			+ " (%.2f / %.2f / %.2f m)" % [tank_at.x, melee_at.x, bow_at.x])
	# A rank of two stands abreast of that line, one lane either side of it.
	var second := _body_at(Vector3(2.0, 0.0, 0.0))
	controller.bodies[15] = second
	fake.roster.styles[15] = Contracts.DISPOSITION_TANK
	ids.append(15)
	var side_at: Vector3 = drive._escort_post(second, _track(15))
	var paired_at: Vector3 = drive._escort_post(tank, _track(12))
	check(is_equal_approx(absf(side_at.x - paired_at.x), SquadScript.FORMATION_LANE)
		and is_equal_approx(side_at.z, paired_at.z),
		"a rank of two stands abreast (%.2f m apart)"
		% absf(side_at.x - paired_at.x))
	# The ranks never read the soul's own disposition: a soul inside a bow is
	# covered by the same tanks, in the same places, as a soul inside a blade.
	fake.roster.styles[11] = Contracts.DISPOSITION_BOW
	var after_bow_soul := [drive._escort_post(tank, _track(12)),
		drive._escort_post(melee, _track(13)),
		drive._escort_post(bow, _track(14))]
	check(after_bow_soul[0].is_equal_approx(paired_at)
		and -after_bow_soul[0].z > 0.0,
		"a soul inside a bow keeps its tanks ahead of it (%.2f m)"
		% -after_bow_soul[0].z)
	check(after_bow_soul[1].is_equal_approx(melee_at)
		and after_bow_soul[2].is_equal_approx(bow_at),
		"and the melee and bow ranks exactly where they stood for a blade soul")
