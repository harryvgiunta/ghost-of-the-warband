extends SceneTree
## Phase Gate 1: the Admin Level / Play Arena, driven on real bodies.
##
## Proves the overhaul's numbers inside a real scene rather than in the library:
## eight mercenaries stand as two brawls 42 m apart, the bubble gives the far
## brawl 10% damage until a human walks over while it keeps guarding, a body that
## is only just killed goes Downed and crawls while a heavy hit kills, a human
## holds the five second revive and AI never can, the field sweeps into the
## value-sorted collective stash, the altar renders essence down, and two peers
## cannot share one body.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Damage = preload("res://scripts/warband/damage_scaler.gd")

const TEST_SAVE := "user://admin_arena_state.json"
const WARBAND_SAVE := "user://admin_arena_warband.json"

var game
var state
var warband
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("ADMIN_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func run() -> void:
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	Damage.reset()

	game = load("res://admin_arena.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.6).timeout

	check_spawn()
	# Deterministic field: the line troops keep their own AI off and the brains
	# keep their choreography off, so every hit below is one this test caused.
	game.set_sparring(false)
	game.set_choreography(false)

	await check_brand()
	await check_bubble()
	await check_passive_fight()
	check_loot()
	await check_downed()
	await check_revive()
	check_peers()
	check_altar()
	await check_screen()
	await check_battle_end()

	game.queue_free()
	await process_frame
	Damage.reset()
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("ADMIN_ARENA_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

## Raw damage needed to land `applied` points through the body's own armor.
func raw_for(actor, applied: float) -> float:
	var reduction: float = clampf(float(actor.rig.damage_reduction(false)), 0.0, 0.95)
	return applied / maxf(0.05, 1.0 - reduction)

# --- roster -----------------------------------------------------------------

func check_spawn() -> void:
	check(warband.roster.count() == 8, "the arena fields eight mercenaries (%d)" % warband.roster.count())
	check(game.bodies.size() == 8, "eight bodies spawned")
	check(game.groups.size() == 2 and game.groups[0].size() == 3 and game.groups[1].size() == 3,
		"two brawls of three")
	var a: Vector3 = game.groups[0][0].global_position
	var b: Vector3 = game.groups[1][0].global_position
	var gap := Vector2(a.x - b.x, a.z - b.z).length()
	check(gap > 44.0 and gap < 52.0, "the brawls stand %.1f m apart" % gap)
	var distinct_hands := {}
	for actor in game.bodies:
		var merc_id: int = game.controller.merc_of(actor)
		check(merc_id > 0, "a body maps back to a mercenary")
		var main_id: String = str(warband.roster.equipped_of(merc_id).get("main", ""))
		check(not main_id.is_empty(), "%s holds a weapon" % warband.roster.name_of(merc_id))
		distinct_hands[main_id] = true
		check(actor.max_health == Contracts.BASE_MAX_HEALTH, "identical base health")
	check(distinct_hands.size() >= 4, "the line carries more than one kind of weapon")
	check(game.controller.active_body(1) != null, "the local soul starts inside a body")

# --- branded skill ----------------------------------------------------------

func check_brand() -> void:
	check(game.branded != null, "the scene owns a brand runner")
	var payload: Dictionary = game.branded.brand()
	check(not payload.is_empty(), "the starting weapon carries a sigil")
	check(str(payload.get("ability", "")) == "rending_strike",
		"a branded sword grants Rending Strike (%s)" % str(payload.get("ability", "")))
	var body = game.controller.active_body(1)
	var target = game.groups[1][0]
	var home: Vector3 = target.global_position
	target.global_position = body.global_position + (-body.global_basis.z) * 1.6
	await process_frame
	var before: float = target.health
	var ready: Dictionary = game.branded.can_activate()
	check(bool(ready.get("ok", false)), "the sigil is ready (%s)" % str(ready.get("reason", "")))
	check(game.branded.activate(), "pressing R fires the sigil")
	await create_timer(0.45).timeout
	check(target.health < before, "the branded strike wounds the body in front")
	check(game.branded.cooldown_left() > 0.0, "and the sigil goes on cooldown")
	check(game.branded.can_activate()["ok"] == false, "a second press is refused")
	# Put the body back on its post so the bubble checks start from the layout.
	target.global_position = home
	await create_timer(0.5).timeout

# --- bubble -----------------------------------------------------------------

func check_bubble() -> void:
	for actor in game.groups[0] + game.groups[1]:
		check(Damage.is_passive(actor), "every brawl starts passive")
	check(is_equal_approx(Damage.scale(100.0, game.groups[1][0]), 10.0), "a passive body takes 10%")

	var far = game.groups[1][0]
	var before: float = far.health
	far.take_damage(100.0, 99)
	var invested: float = before - far.health
	check(invested > 0.0 and invested <= 10.0,
		"a 100 hit removes at most 10 through armor (%.2f)" % invested)

	# Walk the possessed body into the first brawl: only that bubble goes hot.
	var actor = game.controller.active_body(1)
	actor.global_position = game.groups[0][0].global_position + Vector3(1.0, 0, 1.0)
	await create_timer(0.8).timeout
	check(not Damage.is_passive(game.groups[0][0]), "walking over makes that brawl active")
	check(Damage.is_passive(game.groups[1][0]), "the far brawl stays passive")
	check(is_equal_approx(Damage.scale(100.0, game.groups[0][0]), 100.0), "an active body takes 100%")

	var near = game.groups[0][0]
	var before_near: float = near.health
	near.take_damage(100.0, 99)
	check(before_near - near.health > 50.0,
		"the same hit takes far more nearby (%.2f)" % (before_near - near.health))

# --- passive choreography ---------------------------------------------------

func check_passive_fight() -> void:
	# Back to the gate: both brawls are far again, and this is the look the rule
	# is for - guards, spacing, and the occasional swing at 10% damage.
	var actor = game.controller.active_body(1)
	actor.global_position = Vector3(0.0, 0.0, 24.0)
	await create_timer(0.8).timeout
	game.set_choreography(true)
	var watched: Array = game.groups[1]
	var guard_seen := false
	var swing_seen := false
	var damage_taken := 0.0
	var health_start: Dictionary = {}
	for body in watched:
		health_start[body] = float(body.health)
	for _frame in 420:
		await physics_frame
		if not is_instance_valid(game):
			break
		for body in watched:
			if not is_instance_valid(body):
				continue
			if bool(body.combat.blocking):
				guard_seen = true
			if bool(body.rig.is_melee()):
				swing_seen = true
	for body in watched:
		if is_instance_valid(body):
			damage_taken += maxf(0.0, float(health_start[body]) - float(body.health))
	game.set_choreography(false)
	check(guard_seen, "the far brawl raises real guards")
	check(swing_seen, "and still swings, so it does not read as frozen")
	# Zero is legitimate (a brawl that blocks every exchange trades nothing), but
	# the 10% cap must keep six seconds of fighting from shredding a body.
	check(damage_taken < 40.0, "10%% damage cannot shred a body in six seconds (%.1f)" % damage_taken)
	var standing := 0
	for body in watched:
		if is_instance_valid(body) and bool(body.get("alive")) and not bool(body.get("downed")):
			standing += 1
	check(standing == watched.size(), "10% damage leaves the far brawl standing")

# --- loot -------------------------------------------------------------------

func check_loot() -> void:
	var before_total: int = warband.stash.pooled_total()
	check(before_total > 0, "the stash starts with spares")
	check(game.loot.pickups().size() >= 3, "the battlefield has drops (%d)" % game.loot.pickups().size())
	var survivor = game.controller.active_body(1)
	if survivor == null:
		survivor = game.bodies[0]
	var result: Dictionary = game.loot.sweep([survivor])
	check(bool(result.get("ok", false)), "the sweep runs")
	check(int(result.get("collected", 0)) >= 3, "the sweep gathers the field (%s)" % str(result.get("collected")))
	check(warband.stash.pooled_total() >= before_total + 3, "the stash grew by the loot")
	var rows: Array[Dictionary] = warband.stash.rows(warband.roster, warband.cruor.brands)
	check(rows.size() >= 5, "the collective stash has rows")
	var sorted := true
	for index in range(1, rows.size()):
		if int(rows[index - 1]["value"]) < int(rows[index]["value"]):
			sorted = false
	check(sorted, "rows are sorted by value, highest first")
	check(game.loot.pickups().is_empty(), "the field is empty after the sweep")

# --- downed -----------------------------------------------------------------

func check_downed() -> void:
	# Stand in the second brawl so these hits are real 100%, not the far 10%.
	var actor = game.controller.active_body(1)
	if actor != null:
		actor.global_position = game.groups[1][0].global_position + Vector3(1.2, 0, 1.2)
		await create_timer(0.7).timeout
	var target = null
	var victim = null
	for body in game.groups[1]:
		if not is_instance_valid(body) or not bool(body.get("alive")):
			continue
		if bool(body.get("downed")):
			continue
		if target == null:
			target = body
		elif victim == null:
			victim = body
	check(target != null and victim != null, "two standing brawlers to hit")
	if target == null or victim == null:
		return
	target.take_damage(raw_for(target, float(target.health)) + 0.01, 99)
	check(bool(target.downed), "a just-lethal hit downs instead of killing")
	check(is_equal_approx(target.health, 0.0), "downed at zero health")
	check(int(target.health_state) == Contracts.HealthState.DOWNED, "state is DOWNED")
	var start: Vector3 = target.global_position
	await create_timer(0.8).timeout
	check(target.global_position.distance_to(start) > 0.05,
		"a downed body crawls (%.2f m)" % target.global_position.distance_to(start))

	# The campaign's own death rule: no blow ends a mercenary outright, so even a
	# blow three times the whole pool only puts the body on its chest. The follow-up
	# - a strike that lands on a downed body - is what finishes it, and the body
	# then keeps its corpse on the ground.
	victim.take_damage(raw_for(victim, float(victim.max_health)) * 3.0 + 50.0, 99)
	check(bool(victim.get("alive")) and bool(victim.get("downed")),
		"a heavy overkill downs instead of killing")
	check(int(victim.health_state) == Contracts.HealthState.DOWNED,
		"state is DOWNED after a blow that would have been lethal")
	victim.take_damage(1.0, 99)
	check(not bool(victim.get("alive")) and not bool(victim.get("downed")),
		"a blow on the downed body finishes it")
	check(int(victim.health_state) == Contracts.HealthState.DEAD, "state is DEAD")
	check(bool(victim.rig.visible), "the corpse stays on the ground")

# --- revive -----------------------------------------------------------------

func check_revive() -> void:
	var downed = null
	for body in game.bodies:
		if is_instance_valid(body) and bool(body.get("downed")) and bool(body.get("alive")):
			downed = body
			break
	check(downed != null, "a downed body exists to revive")
	if downed == null:
		return
	# The crawl is proven above; for the channel itself the body is held still so
	# the test measures the clock and not the drag.
	for crawl in game.crawls:
		if is_instance_valid(crawl) and crawl.actor == downed:
			crawl.detach()
	var actor = game.controller.active_body(1)
	actor.global_position = downed.global_position + Vector3(1.2, 0, 0)
	downed.global_position = actor.global_position + Vector3(-1.0, 0, 0)
	check(game.revive.begin(0, downed) == false, "AI never revives")
	check(game.revive.begin(1, downed), "a human at arm's length opens a channel")
	game.revive.tick(4.9)
	check(bool(downed.get("downed")), "4.9 s is not enough")
	game.revive.cancel(1)
	check(game.revive.begin(1, downed), "the channel can be re-opened")
	await create_timer(5.1).timeout
	check(not bool(downed.get("downed")), "five seconds stands the body up")
	check(bool(downed.get("alive")), "the revived body is alive")
	check(is_equal_approx(downed.health, downed.max_health * Contracts.REVIVE_HEALTH_FRACTION),
		"revive restores half health (%.1f / %.1f)" % [downed.health, downed.max_health])

# --- two peers --------------------------------------------------------------

func check_peers() -> void:
	var free_body := -1
	for actor in game.bodies:
		var merc_id: int = game.controller.merc_of(actor)
		if merc_id > 0 and bool(actor.get("alive")) and not bool(actor.get("downed")) \
				and warband.souls.occupied_by(merc_id) == 0:
			free_body = merc_id
			break
	check(free_body > 0, "a free body exists for the second peer")
	var mine: int = game.controller.merc_for_peer(1)
	var steal: Dictionary = game.controller.activate(2, mine)
	check(steal["ok"] == false, "peer two cannot take peer one's body")
	check(game.controller.merc_for_peer(1) == mine, "peer one keeps its body")
	check(game.controller.merc_for_peer(2) == -1, "peer two is still bodiless")
	if free_body > 0:
		check(game.controller.activate(2, free_body)["ok"], "peer two takes a free body")
		check(warband.souls.occupied_by(free_body) == 2, "the lock names peer two")
		check(game.controller.merc_for_peer(1) == mine, "peer one is untouched by peer two")
		game.controller.activate(2, mine)
		check(game.controller.merc_for_peer(2) == free_body, "a refused steal leaves peer two where it was")
		game.controller.release_local()

# --- altar ------------------------------------------------------------------

func check_altar() -> void:
	var tallow_before: int = warband.cruor.tier_count(Contracts.CruorTier.T1_RITUAL_TALLOW)
	game.altar.interact(1)
	check(game.altar.is_open(), "the altar answers G")
	var menu: Object = game.altar.menu()
	check(menu != null, "the altar owns a menu")
	if menu != null:
		check(menu.unbind_rows().size() >= 1, "spare magic items are offered for unbinding")
		check(menu.distill_rows().size() == 5, "all five tiers are listed for distilling")
		game.altar.close()
	check(warband.cruor.tier_count(Contracts.CruorTier.T1_RITUAL_TALLOW) == tallow_before,
		"opening the altar spends nothing")

# --- screens ----------------------------------------------------------------

func check_screen() -> void:
	# `O` is the screen key in every warband scene; `TAB` is the quick weapon swap.
	# The press path itself is driven in `warband_world_regression.check_keys`.
	game.screen.open()
	check(game.screen.is_open(), "the warband screen opens")
	var target_merc := -1
	for merc_id in warband.roster.alive_ids():
		if warband.souls.occupied_by(merc_id) == 0:
			target_merc = merc_id
			break
	if target_merc > 0:
		game.screen.possess_requested.emit(target_merc)
		await process_frame
		check(not game.screen.is_open(), "a click closes the screen")
		check(game.controller.merc_for_peer(1) == target_merc, "the click moved the soul")
		check(bool(game.controller.active_body(1).get("alive")), "the new body is alive")
	game.paperdoll.open(game.controller.merc_for_peer(1))
	check(game.paperdoll.is_open(), "the paperdoll opens on a mercenary")
	game.paperdoll.close()

# --- battle end -------------------------------------------------------------

func check_battle_end() -> void:
	for group in game.groups:
		for actor in group:
			if bool(actor.get("alive")) and not bool(actor.get("downed")):
				actor.take_damage(2000.0, 99)
	var before: int = warband.stash.pooled_total()
	await create_timer(1.4).timeout
	check(game._battle_over, "the arena notices the battle is over")
	check(warband.stash.pooled_total() >= before, "the end-of-battle sweep keeps the stash whole")
	check(game.loot.describe().contains("drops=0"),
		"the field holds no drops after the end sweep (%s)" % game.loot.describe())
