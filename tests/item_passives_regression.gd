extends SceneTree

const Actor = preload("res://scripts/arena_actor.gd")
const Archer = preload("res://scripts/archer.gd")
const Combat = preload("res://scripts/combat.gd")
const Passives = preload("res://scripts/item_passives.gd")
const State = preload("res://scripts/player_state.gd")
const STEP := 1.0 / 240.0
## One dormant lunge: 0.5 s opened by the dagger's +200% rate.
const SHANK := 0.5 / 3.0
const ARMOR := {"head": 0, "chest": 0, "hands": 0, "legs": 0, "feet": 0}
var checks := 0
var failures := 0
var sweeps := 0
var attacker
var victim

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func step(delta: float) -> void:
	attacker.rig.advance_animation(delta)
	attacker.combat.advance(delta)
	victim.rig.advance_animation(delta)
	victim.combat.advance(delta)

func advance(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.000001:
		var delta := minf(STEP, remaining)
		step(delta)
		remaining -= delta

func on_sweep(_hand: String, _pb: Vector3, _pt: Vector3, _cb: Vector3, _ct: Vector3, _radius: float) -> void:
	sweeps += 1

func fighter(parent: Node3D, index: int, position_at: Vector3):
	var actor := Actor.new()
	actor.slot = index
	actor.authoritative = true
	parent.add_child(actor)
	actor.configure(index + 1, false, "Regression", position_at)
	actor.set_process(false)
	actor.rig.set_process(false)
	actor.rig.set_physics_process(false)
	actor.combat.set_motion(Vector3.ZERO, false, true)
	return actor

## The additive +200% is a rate, the same convention `TrinketStats` uses.
func _test_table() -> void:
	check(Passives.has_passives("dagger"), "The dagger class carries a passive row")
	check(is_equal_approx(Passives.variant_rate("dagger", "stab"), 3.0), "+200% is a 3.0x stab rate")
	check(is_equal_approx(Passives.variant_rate("dagger", "overhead"), 1.0), "The wheel-down chop keeps its own timing")
	check(is_equal_approx(Passives.variant_rate("dagger", "diagonal_left"), 1.0), "A dagger diagonal cut is not the forward lunge")
	check(is_equal_approx(Passives.variant_rate("sword", "stab"), 1.0), "A sword stab gains nothing from the dagger row")
	check(is_equal_approx(Passives.variant_rate("", "stab"), 1.0), "An empty hand has no passive")
	check(is_equal_approx(Passives.variant_rate("dagger", "nonsense"), 1.0), "An unknown variant has no passive")
	var rows: Array = Passives.effect_rows("dagger", float(Archer.dagger_profile(0).seconds))
	check(rows.size() == 2, "The row pair advertises the passive")
	if rows.size() == 2:
		check(str(rows[0].label) == "PASSIVE" and str(rows[0].value) == "Prison shank", "The passive is named")
		check(str(rows[1].label) == "FORWARD STAB" and str(rows[1].value).begins_with("+200%"),
			"The row names the wheel-up lunge and its added rate")
		check(str(rows[1].value).contains("0.17 s"), "The row resolves the shortened stab time")
	check(Passives.effect_rows("sword", 1.0).is_empty(), "A sword item shows no passive rows")
	check(Passives.effect_summary("dagger").contains("STAB +200%"), "The compact form states the rate")

## The tooltip is the requested surface: it must show on the dagger, not only
## on whatever the player happens to be holding.
func _test_tooltip() -> void:
	var state := State.new()
	state.reset(false)
	for dagger_id in ["dagger_iron", "dagger_ironwood"]:
		var rows: Array = state.item_stat_rows(dagger_id)
		var has_passive := false
		var has_stab := false
		for row in rows:
			if str(row.label) == "PASSIVE" and str(row.value) == "Prison shank":
				has_passive = true
			if str(row.label) == "FORWARD STAB" and str(row.value).contains("+200%"):
				has_stab = true
		check(has_passive, "%s lists the passive by name" % dagger_id)
		check(has_stab, "%s lists the +200%% forward stab" % dagger_id)
		check(state.item_compact_stats(dagger_id).contains("PASSIVE PRISON SHANK"),
			"%s inspector line shows the passive" % dagger_id)
		check(state.item_detail(dagger_id).contains("+200% forward stab"),
			"%s hover text shows the passive" % dagger_id)
	var sword_rows: Array = state.item_stat_rows("sword_short")
	var sword_has_stab := false
	for row in sword_rows:
		if str(row.label) == "FORWARD STAB":
			sword_has_stab = true
	check(not sword_has_stab, "The shortsword advertises no dagger passive")
	check(not state.item_compact_stats("sword_short").contains("PASSIVE"),
		"The shortsword inspector line stays passive-free")
	check(not state.item_detail("sword_short").contains("forward stab"),
		"The shortsword hover text stays passive-free")
	state.free()

func _test_rig(world: Node3D) -> void:
	var armor := ARMOR
	# The timing phases must not nibble a live body; the contact phase revives
	# the victim at its spawn point, which is one dagger reach ahead.
	victim.position = Vector3(0, 0.08, -20.0)
	attacker.rig.apply_loadout(State.build_loadout("dagger_iron", "", armor))
	check(attacker.rig.swing_weapon_class("right") == "dagger", "The equipped dagger supplies the right hand")
	check(is_equal_approx(attacker.rig.variant_attack_rate("right", "stab"), 3.0),
		"The rig reads the dagger's stab rate")
	check(is_equal_approx(attacker.rig.variant_attack_rate("right", "overhead"), 1.0),
		"The rig keeps the chop rate at 1.0")

	sweeps = 0
	check(attacker.combat.begin_melee("right", "stab"), "The wheel-up lunge starts")
	check(is_equal_approx(attacker.rig.melee_seconds("right"), SHANK),
		"A 0.5 s stab resolves to 0.167 s at +200%")
	var window: Vector2 = attacker.rig._melee_window("right")
	var clip: Dictionary = attacker.rig._profile.clips.stab
	check(is_equal_approx(window.x, float(clip.strike_start) / 3.0), "The strike window starts a third of the way in")
	check(is_equal_approx(window.y, float(clip.strike_end) / 3.0), "The strike window ends inside the short swing")
	advance(0.15)
	check(attacker.rig.phase.begins_with("MELEE"), "The short stab is still running before 0.167 s")
	advance(0.02)
	check(attacker.rig.phase == "READY", "The short stab finishes on its own duration")
	check(attacker.combat.right_melee_progress >= 0.999999, "Recovery completes with the swing")
	check(sweeps >= 1, "A 0.167 s stab still emits blade samples")

	# The wheel-down chop is the same weapon at its authored timing.
	check(attacker.combat.begin_melee("right", "overhead"), "The wheel-down chop starts")
	check(is_equal_approx(attacker.rig.melee_seconds("right"), 0.5), "The dagger chop keeps its 0.5 s")
	advance(0.5 + STEP)
	check(attacker.rig.phase == "READY", "The chop completes at 0.5 s")

	# Shanking: six full stabs inside one second of the old single stab.
	var stabs := 0
	for index in 6:
		if not attacker.combat.begin_melee("right", "stab"):
			break
		stabs += 1
		advance(SHANK + STEP)
	check(stabs == 6, "Six stabs land in the time one used to take")
	check(attacker.rig.phase == "READY", "Every stab returns to ready")

	# Same gear, a sword: the wheel-up stab is untouched.
	attacker.rig.apply_loadout(State.build_loadout("sword_short", "", armor))
	check(attacker.rig.swing_weapon_class("right") == "sword", "The shortsword supplies the right hand")
	check(is_equal_approx(attacker.rig.variant_attack_rate("right", "stab"), 1.0), "A sword keeps the base stab rate")
	check(attacker.combat.begin_melee("right", "stab"), "The sword stab starts")
	check(is_equal_approx(attacker.rig.melee_seconds("right"), 0.5), "A sword stab keeps its 0.5 s")
	advance(0.5 + STEP)

	# Trinket haste composes with the passive instead of replacing it.
	attacker.rig.apply_loadout(State.build_loadout("dagger_iron", "", armor, {"ring1": "ring_haste"}))
	check(is_equal_approx(attacker.rig.attack_rate(), 1.12), "The haste ring is worn")
	check(attacker.combat.begin_melee("right", "stab"), "The hasted dagger stab starts")
	check(is_equal_approx(attacker.rig.melee_seconds("right"), 0.5 / (1.12 * 3.0)),
		"Haste multiplies the passive rate")
	advance(0.5 / (1.12 * 3.0) + STEP)

	# A real contact still lands once inside the short window.
	attacker.rig.apply_loadout(State.build_loadout("dagger_iron", "", armor))
	victim.revive()
	victim.max_health = 200.0
	victim.health = 200.0
	victim.velocity = Vector3.ZERO
	attacker.combat.set_aim(victim.global_position + Vector3(0, 1.2, 0))
	attacker.rig.global_basis = Basis.IDENTITY
	attacker.combat.set_motion(Vector3.ZERO, false, true)
	victim.combat.stop()
	check(attacker.combat.begin_melee("right", "stab"), "A shanking stab starts against a body")
	var sweeps_before := sweeps
	advance(SHANK + STEP)
	check(sweeps > sweeps_before, "The contact stab swept its blade")
	check(is_equal_approx(victim.health, 200.0 - float(Archer.dagger_profile(0).damage)),
		"A 0.167 s stab still deals one dagger hit (health %.1f, sweeps %d)" % [
			victim.health, sweeps - sweeps_before])
	attacker.combat.stop()

## The frontier input path: wheel up on the equipped dagger.
func _test_frontier_input() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.45).timeout
	for enemy in game.enemies:
		enemy.set_physics_process(false)
	game._player_state.equipped["main"] = "dagger_iron"
	game._player_state.equipped["off"] = ""
	game.archer.apply_loadout(game._player_state.loadout())
	game.combat.set_motion(Vector3.ZERO, false, true)
	game.archer.set_locomotion(Vector3.ZERO, true)
	await physics_frame
	check(game.archer.weapon == "dagger", "The frontier equips the iron dagger")
	check(is_equal_approx(game.archer.variant_attack_rate("right", "stab"), 3.0),
		"The frontier rig reads the dagger passive")

	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_WHEEL_UP
	up.pressed = true
	game._unhandled_input(up)
	check(game.archer.phase == "MELEE_ST", "Wheel up starts the forward lunge")
	check(is_equal_approx(game.archer.melee_seconds(), SHANK), "The frontier lunge runs at the passive rate")
	check(game.combat.get_attack_interval() < 0.2, "The HUD interval reports the fast lunge")
	game.combat.stop()
	game.combat.right_melee_progress = 1.0
	game.combat.melee_progress = 1.0

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	down.pressed = true
	game._unhandled_input(down)
	check(game.archer.phase == "MELEE" and game.archer.melee_variant("right") == "overhead",
		"Wheel down still starts the chop")
	check(is_equal_approx(game.archer.melee_seconds(), 0.5), "Wheel down keeps the dagger's authored 0.5 s")
	game.combat.stop()
	game.queue_free()
	await process_frame

func run() -> void:
	_test_table()
	_test_tooltip()
	var world := Node3D.new()
	root.add_child(world)
	attacker = fighter(world, 0, Vector3.ZERO)
	victim = fighter(world, 1, Vector3(0, 0, -0.9))
	attacker.rig.melee_sweep.connect(on_sweep)
	attacker.rig.set_locomotion(Vector3.ZERO, true)
	await physics_frame
	await physics_frame
	_test_rig(world)
	world.queue_free()
	await process_frame
	await _test_frontier_input()

	print("ITEM_PASSIVES_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
