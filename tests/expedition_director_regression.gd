extends SceneTree
## wt-12: the expedition director - five paced waves, the Bilewarden's wave, the
## purse, and the wipe.
##
## Everything here runs against the real `admin_arena.tscn` on real bodies. The
## cult is the arena's own `EnemyWaves`, the kills go through `ArenaActor.take_damage`,
## the loot is the arena's `WarbandLoot` and the coins are `PlayerState.credits`
## through `Warband.gold()`. The director is only asked what it thinks happened,
## and every answer is compared with what the field actually did.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Damage = preload("res://scripts/warband/damage_scaler.gd")
const State = preload("res://scripts/player_state.gd")
const DirectorScript = preload("res://scripts/warband/expedition_director.gd")
const GuardScript = preload("res://scripts/warband/cultist_guard.gd")
const BrandedScript = preload("res://scripts/warband/branded_skills.gd")

const TEST_SAVE := "user://expedition_director_state.json"
const WARBAND_SAVE := "user://expedition_director_warband.json"
## Six mercenaries, three of them deployed: enough to hold the muster line without
## filling the bubble with bodies the test never looks at.
const LINEUP := [
	{"name": "Aldous", "main": "sword_short", "off": "shield_buckler", "armor": "leather"},
	{"name": "Brine", "main": "dagger_iron", "off": "shield_kite", "armor": "mail"},
	{"name": "Cael", "main": "bow_short", "off": "", "armor": "cloth"},
	{"name": "Dorn", "main": "sword_great", "off": "", "armor": "plate"},
	{"name": "Edda", "main": "sword_arming", "off": "shield_tower", "armor": "mail"},
	{"name": "Fenwick", "main": "sword_short", "off": "dagger_iron", "armor": "leather"},
]
## The wave curve the director is contracted to walk, boss wave included.
const CURVE := [3, 4, 4, 5, 6]
## 3 + 4 + 4 + 5 + 6 cultists stand on the field, so 22 kills is a clear.
const TOTAL_KILLS := 22
## 25 gold a wave plus 50 for the Bilewarden, one tallow a wave and one bile at
## the boss. Written out rather than read from the director: this is the contract.
const GOLD_REWARD := 175
const TALLOW_REWARD := 5
const BILE_REWARD := 1

var game
var warband
var state
var checks := 0
var failures := 0

## What the field held the instant before the fifth wave fell, so the reward and
## the loot count are measured against the world and not against the director.
var _gold_before := 0
var _tallow_before := 0
var _bile_before := 0
var _stash_before := 0
## Drops still lying on the field just before the fifth wave fell.
var _drops_before := 0
## The warband's own brand ledger and essence wallet as the expedition found them:
## nothing about the boss may move either one.
var _brands_before: Dictionary = {}
var _counts_before: Dictionary = {}

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("EXPEDITION_DIRECTOR_FAIL  ", message)

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
	_seed()

	var ids: Array[int] = warband.merc_ids()
	check(warband.deploy_battle(ids.slice(0, 3)).size() == 3, "three mercenaries are deployed")
	check(warband.cruor.total() == 0, "the test warband starts with an empty essence wallet")
	_brands_before = warband.cruor.brands.duplicate(true)
	_counts_before = warband.cruor.counts.duplicate(true)

	await _open_field()
	var director = game.director
	check(director != null, "the field is paced by a director")
	if director == null:
		await _finish()
		return
	check(game.expedition, "a deployment line makes this a real battle")
	check(game.waves != null, "the cult spawner is still the field's enemy source")
	check(game.groups.is_empty(), "the sandbox brawls are not built")

	await _walk_waves(director)
	await _check_rewards(director)
	await _check_no_double_pay(director)

	game.queue_free()
	await process_frame
	Damage.reset()
	await _check_ledger_persistence()
	await _check_wipe()

	await _finish()

func _finish() -> void:
	if game != null:
		game.queue_free()
		await process_frame
	Damage.reset()
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("EXPEDITION_DIRECTOR_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

# --- scene ------------------------------------------------------------------

func _seed() -> void:
	for entry in LINEUP:
		var merc_id: int = warband.add_mercenary(str(entry["name"]))
		var main_id := str(entry["main"])
		warband.roster.equip(merc_id, "main", main_id)
		var off_id := str(entry["off"])
		if not off_id.is_empty() and not Contracts.two_handed_item(State.ITEMS.get(main_id, {})):
			warband.roster.equip(merc_id, "off", off_id)
		for slot in ["head", "chest", "hands", "legs", "feet"]:
			var armor_id := "armor_%s_%s" % [str(entry["armor"]), slot]
			if State.ITEMS.has(armor_id):
				warband.roster.equip(merc_id, slot, armor_id)

func _open_field() -> void:
	game = load("res://admin_arena.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.6).timeout

# --- the five waves ---------------------------------------------------------

func _walk_waves(director) -> void:
	check(director.wave_count() == 5, "the expedition is five waves (%d)" % director.wave_count())
	check(director.wave_index() == 0, "the first wave is on the field already")
	check(director.state == DirectorScript.STATE_RUNNING, "the run is live (%s)" % director.state)
	check(not director.finished(), "a live run is not finished")
	var kills := 0
	for index in CURVE.size():
		if index > 0:
			check(await _wait_wave(index), "wave %d walks in on its own" % (index + 1))
		check(int(game.waves.wave()) == index, "EnemyWaves is on wave index %d" % index)
		check(director.wave_index() == index, "the director names wave %d" % (index + 1))
		var expected: int = CURVE[index]
		check(game.waves.living() == expected,
			"wave %d fields %d cultists (%d)" % [index + 1, expected, game.waves.living()])
		check(game.waves.wave_size() == expected,
			"the wave's own roster is %d bodies (%d)" % [expected, game.waves.wave_size()])
		# The status line still names the wave out of the real wave count.
		if index > 0:
			var status := _status_text()
			check(status.begins_with("Wave %d of 5" % (index + 1)),
				"the HUD names wave %d of 5 (%s)" % [index + 1, status])
		_harmless()
		var final := index == CURVE.size() - 1
		if final:
			_check_boss(director)
			_gold_before = warband.gold()
			_tallow_before = warband.cruor.tier_count(Contracts.CruorTier.T1_RITUAL_TALLOW)
			_bile_before = warband.cruor.tier_count(Contracts.CruorTier.T2_BLACK_BILE)
			_stash_before = warband.stash.pooled_total()
			_drops_before = game.loot.pickups().size()
		check(await _clear_wave(), "wave %d is cleared" % (index + 1))
		kills += expected
		check(game.waves.total_cleared() == kills,
			"the cult tally is %d after wave %d (%d)" % [kills, index + 1, game.waves.total_cleared()])
		check(int(director.summary()["kills"]) == kills,
			"the director's kill count is %d (%d)" % [kills, int(director.summary()["kills"])])
		if not final:
			check(warband.cruor.brands == _brands_before,
				"wave %d writes nothing into the brand ledger" % (index + 1))
			check(warband.cruor.total() == 0, "no essence is paid before the clear")
			check(not director.finished(), "wave %d does not end the run" % (index + 1))
			check(not game._battle_over, "wave %d does not end the field" % (index + 1))
			check(director.gap_left() > 0.0,
				"wave %d leaves a breathing gap (%.2f s)" % [index + 1, director.gap_left()])
			check(director.gap_left() <= DirectorScript.GAP_SECONDS,
				"the gap is the contracted %.0f s" % DirectorScript.GAP_SECONDS)
	check(kills == TOTAL_KILLS, "the curve is 22 cultists (%d)" % kills)
	check(director.state == DirectorScript.STATE_CLEARED,
		"clearing the fifth wave clears the expedition (%s)" % director.state)
	check(director.cleared() and director.finished(), "the run reports cleared and finished")
	check(not director.wiped(), "a cleared run is not a wipe")
	check(director.gap_left() == 0.0, "a finished run holds no gap")
	check(game._battle_over, "the arena closes the field")
	check(game._loot_running, "the survivors are sent to loot the field")

func _check_boss(director) -> void:
	var boss = director.boss()
	check(boss != null, "the fifth wave fields the Bilewarden")
	if boss == null:
		return
	var escorts := 0
	var ordinary = null
	for guard in game.waves.guards():
		if not is_instance_valid(guard):
			continue
		if str(guard.display_name) in DirectorScript.ESCORT_NAMES:
			escorts += 1
		elif guard != boss and ordinary == null:
			ordinary = guard
	check(escorts == 2, "two escort guards flank the Bilewarden (%d)" % escorts)
	check(ordinary != null, "regular acolytes fill the rest of the wave")
	check(str(boss.display_name) == DirectorScript.BOSS_NAME,
		"the boss carries the cult's own name (%s)" % str(boss.display_name))
	if ordinary != null:
		check(is_equal_approx(float(boss.max_health), 2.0 * float(ordinary.max_health)),
			"the Bilewarden has double a guard's health (%.0f vs %.0f)" % [
				float(boss.max_health), float(ordinary.max_health)])
	check(is_equal_approx(float(boss.max_health), 2.0 * Contracts.BASE_MAX_HEALTH),
		"the Bilewarden stands at 200 health (%.0f)" % float(boss.max_health))
	check(is_equal_approx(float(boss.health), float(boss.max_health)),
		"and walks in at full health (%.0f)" % float(boss.health))
	check(bool(boss.get("alive")) and not bool(boss.get("downed")), "the Bilewarden is on his feet")
	var blade := str(boss.kit.get("main", ""))
	check(blade == DirectorScript.BOSS_MAIN,
		"the boss holds %s (%s)" % [DirectorScript.BOSS_MAIN, blade])
	check(boss.cult_material != null and boss.cult_material.albedo_color.is_equal_approx(GuardScript.TINT),
		"the boss is painted like the cult he leads")
	# The anointment is run-scoped: it lives on the body, names itself on the
	# field, and never reaches the warband's ledger (which only the altar writes).
	var brand: Dictionary = boss.brand_of()
	check(not brand.is_empty(), "the boss carries a brand")
	check(str(brand.get("item", "")) == blade,
		"the brand sits on the blade he actually holds (%s vs %s)" % [str(brand.get("item", "")), blade])
	check(int(brand.get("tier", -1)) == Contracts.CruorTier.T2_BLACK_BILE,
		"the brand is Black Bile (%d)" % int(brand.get("tier", -1)))
	var ability := BrandedScript.for_subtype(Contracts.WeaponSubType.TWO_HAND)
	check(str(brand.get("ability", "")) == ability,
		"the two-hander's sigil names the ability (%s)" % str(brand.get("ability", "")))
	check(str(brand.get("name", "")) == BrandedScript.ability_name(ability),
		"and its display name (%s)" % str(brand.get("name", "")))
	check(director.boss_brand() == brand, "the director reports the same brand the body carries")
	var sigil = boss.find_child("BrandedSigil", true, false)
	check(sigil != null and sigil is Label3D, "the anointing is drawn on the field")
	if sigil is Label3D:
		var sigil_text := str((sigil as Label3D).text)
		check(sigil_text.contains(BrandedScript.ability_name(ability)),
			"the label names the sigil (%s)" % sigil_text)
		check(sigil_text == boss.brand_line(), "the label is the body's brand line")
		check((sigil as Label3D).visible, "the label is visible")
	check(warband.cruor.brand_of(blade).is_empty(),
		"reaching wave five writes nothing into the warband's brand ledger")
	check(warband.cruor.brands.is_empty(), "the ledger is still empty on wave five")

# --- the purse --------------------------------------------------------------

func _check_rewards(director) -> void:
	var summary: Dictionary = director.summary()
	check(warband.gold() == _gold_before + GOLD_REWARD,
		"the clear pays %d gold (%d -> %d)" % [GOLD_REWARD, _gold_before, warband.gold()])
	check(warband.cruor.tier_count(Contracts.CruorTier.T1_RITUAL_TALLOW) == _tallow_before + TALLOW_REWARD,
		"the clear pays %d tallow (%d -> %d)" % [TALLOW_REWARD, _tallow_before,
			warband.cruor.tier_count(Contracts.CruorTier.T1_RITUAL_TALLOW)])
	check(warband.cruor.tier_count(Contracts.CruorTier.T2_BLACK_BILE) == _bile_before + BILE_REWARD,
		"the clear pays %d black bile (%d -> %d)" % [BILE_REWARD, _bile_before,
			warband.cruor.tier_count(Contracts.CruorTier.T2_BLACK_BILE)])
	check(warband.cruor.total() == TALLOW_REWARD + BILE_REWARD,
		"the essence wallet holds exactly the reward (%d)" % warband.cruor.total())
	check(warband.cruor.brands == _brands_before,
		"the clear writes no brand into the warband's ledger (%s)" % str(warband.cruor.brands))
	check(int(summary["gold"]) == GOLD_REWARD,
		"the summary reports %d gold (%d)" % [GOLD_REWARD, int(summary["gold"])])
	check(int(summary["waves"]) == 5, "the summary counts five waves (%d)" % int(summary["waves"]))
	check(int(summary["kills"]) == TOTAL_KILLS,
		"the summary counts every cultist (%d)" % int(summary["kills"]))
	var cruor: Dictionary = summary["cruor"]
	check(int(cruor.get(Contracts.CruorTier.T1_RITUAL_TALLOW, 0)) == TALLOW_REWARD,
		"the summary names the tallow (%d)" % int(cruor.get(Contracts.CruorTier.T1_RITUAL_TALLOW, 0)))
	check(int(cruor.get(Contracts.CruorTier.T2_BLACK_BILE, 0)) == BILE_REWARD,
		"the summary names the bile (%d)" % int(cruor.get(Contracts.CruorTier.T2_BLACK_BILE, 0)))
	# The loot run books the field before the summary's item count is judged. The
	# count comes from the field itself - drops that were lying there, plus the
	# one each of the six bodies dropped, minus what nobody walked to - so it does
	# not depend on the director's own arithmetic.
	var jogged := await _wait_until(func(): return not game._loot_running, 25.0)
	check(jogged, "the loot run finishes")
	await create_timer(0.3).timeout
	var gathered: int = _drops_before + CURVE[CURVE.size() - 1] - game.loot.pickups().size()
	check(gathered >= TOTAL_KILLS, "the field was worth looting (%d pieces)" % gathered)
	check(warband.stash.pooled_total() > _stash_before,
		"the pieces land in the shared stash (%d -> %d)" % [_stash_before, warband.stash.pooled_total()])
	check(int(director.summary()["items"]) == gathered,
		"the summary counts the %d gathered pieces (%d)" % [gathered,
			int(director.summary()["items"])])

## Advance past the end twice: the purse and the report must not move.
func _check_no_double_pay(director) -> void:
	var gold: int = warband.gold()
	var tallow: int = warband.cruor.tier_count(Contracts.CruorTier.T1_RITUAL_TALLOW)
	var bile: int = warband.cruor.tier_count(Contracts.CruorTier.T2_BLACK_BILE)
	var items: int = int(director.summary()["items"])
	director.step(1.0, game.bodies)
	director.step(1.0, game.bodies)
	game._end_battle("And again.")
	await process_frame
	check(warband.gold() == gold, "a second advance pays no gold (%d -> %d)" % [gold, warband.gold()])
	check(warband.cruor.tier_count(Contracts.CruorTier.T1_RITUAL_TALLOW) == tallow,
		"a second advance pays no tallow")
	check(warband.cruor.tier_count(Contracts.CruorTier.T2_BLACK_BILE) == bile,
		"a second advance pays no bile")
	check(int(director.summary()["gold"]) == GOLD_REWARD,
		"the report still names the one payment (%d)" % int(director.summary()["gold"]))
	check(int(director.summary()["items"]) == items, "the item count is unchanged")
	check(director.state == DirectorScript.STATE_CLEARED, "the run stays cleared (%s)" % director.state)

## Nothing about the Bilewarden is the warband's to keep: after a whole
## expedition the brand ledger must be exactly what it was before the first wave,
## in memory and on disk.
func _check_ledger_persistence() -> void:
	check(warband.cruor.brands == _brands_before,
		"the run leaves the brand ledger untouched (%s)" % str(warband.cruor.brands))
	warband.save_state()
	var raw := FileAccess.get_file_as_string(warband.save_path)
	var parsed: Variant = JSON.parse_string(raw)
	check(parsed is Dictionary, "the warband saves as JSON")
	if parsed is Dictionary:
		var saved_cruor: Variant = (parsed as Dictionary).get("cruor", {})
		var saved_brands: Variant = {}
		if saved_cruor is Dictionary:
			saved_brands = (saved_cruor as Dictionary).get("brands", {})
		check(saved_brands is Dictionary and (saved_brands as Dictionary).is_empty(),
			"the save on disk carries an empty brand map (%s)" % str(saved_brands))
	check(warband.load_state(), "the warband save reloads")
	check(warband.cruor.brands == _brands_before,
		"and the reloaded ledger is still empty (%s)" % str(warband.cruor.brands))
	check(warband.cruor.tier_count(Contracts.CruorTier.T1_RITUAL_TALLOW) == _counts_before.get(
		Contracts.CruorTier.T1_RITUAL_TALLOW, 0) + TALLOW_REWARD,
		"the reloaded wallet keeps the tallow it was paid")
	check(warband.cruor.tier_count(Contracts.CruorTier.T2_BLACK_BILE) == _counts_before.get(
		Contracts.CruorTier.T2_BLACK_BILE, 0) + BILE_REWARD,
		"the reloaded wallet keeps the bile it was paid")

# --- the wipe ---------------------------------------------------------------

func _check_wipe() -> void:
	await _open_field()
	var director = game.director
	check(director != null, "the second field opens with a director")
	if director == null:
		return
	check(director.wave_index() == 0, "and on the first wave")
	check(director.state == DirectorScript.STATE_RUNNING, "and still running")
	var gold_before: int = warband.gold()
	var cruor_before: int = warband.cruor.total()
	var stash_before: int = warband.stash.pooled_total()
	var drops_before: int = game.loot.pickups().size()
	check(drops_before > 0, "the field still holds its drops (%d)" % drops_before)

	# Down the whole line through the body's own damage funnel: a just-lethal blow
	# downs instead of killing, which is exactly the state a wipe is judged on.
	for body in game.bodies:
		if not is_instance_valid(body):
			continue
		var attempts := 0
		while bool(body.get("alive")) and not bool(body.get("downed")) and attempts < 120:
			body.take_damage(_lethal_raw(body), 99)
			await physics_frame
			attempts += 1
	var fallen := true
	for body in game.bodies:
		if bool(body.get("alive")) and not bool(body.get("downed")):
			fallen = false
	check(fallen, "every warband body is on the ground")
	var ended := await _wait_until(func(): return game.director.state == DirectorScript.STATE_WIPED, 5.0)
	check(ended, "the run ends when nobody is standing (%s)" % game.director.state)
	check(game.director.wiped() and game.director.finished(), "the run reports wiped and finished")
	check(not game.director.cleared(), "a wipe is not a clear")
	check(game._battle_over, "the arena closes the field")
	check(not game._loot_running, "a wipe sends nobody looting")
	check(warband.gold() == gold_before, "a wipe pays no gold (%d -> %d)" % [gold_before, warband.gold()])
	check(warband.cruor.total() == cruor_before, "a wipe pays no cruor")
	check(warband.stash.pooled_total() == stash_before, "a wipe gathers nothing")
	check(game.loot.pickups().size() == drops_before, "the drops stay where they fell")
	var summary: Dictionary = game.director.summary()
	check(int(summary["gold"]) == 0, "the wiped report claims no gold")
	check((summary["cruor"] as Dictionary).is_empty(), "the wiped report claims no cruor")
	check(int(summary["items"]) == 0, "the wiped report claims no loot")
	check(int(summary["waves"]) == 0, "the wiped report cleared no wave")
	check(int(summary["kills"]) == 0, "the wiped report took no cultist (%d)" % int(summary["kills"]))
	game.director.step(1.0, game.bodies)
	await process_frame
	check(warband.gold() == gold_before, "stepping a wiped field still pays nothing")
	check(game.director.state == DirectorScript.STATE_WIPED, "and the run stays wiped")

# --- helpers ----------------------------------------------------------------

## The status line the HUD is showing, or "" when none is up.
func _status_text() -> String:
	if game == null or game.hud == null:
		return ""
	var label = game.hud.get("_status_label")
	if label == null or not (label is Label):
		return ""
	return str((label as Label).text)

func _harmless() -> void:
	# The pacing, not the fighting, is what this test measures: the cult keeps its
	# legs and loses its teeth, so a wave cannot down the line before it is read.
	for guard in game.waves.guards():
		if is_instance_valid(guard):
			guard.combat.damage_enabled = false

## Raw damage that downs a body through its armor and its bubble share in one
## blow, without crossing the 10% overkill line into a kill.
func _lethal_raw(body) -> float:
	var reduction: float = clampf(float(body.rig.damage_reduction(false)), 0.0, 0.95)
	var sim: float = maxf(0.05, float(Damage.scale(1.0, body)))
	return (float(body.health) + 0.01) / (maxf(0.05, 1.0 - reduction) * sim)

func _clear_wave() -> bool:
	if game == null or game.waves == null:
		return false
	var deadline := Time.get_ticks_msec() + 6000
	while game.waves.living() > 0 and Time.get_ticks_msec() < deadline:
		for guard in game.waves.guards():
			if is_instance_valid(guard) and bool(guard.get("alive")):
				guard.take_damage(5000.0, 1)
		await process_frame
	return game.waves.living() == 0

func _wait_wave(index: int) -> bool:
	return await _wait_until(func(): return int(game.waves.wave()) == index, 10.0)

func _wait_until(predicate: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await create_timer(0.1).timeout
	return bool(predicate.call())
