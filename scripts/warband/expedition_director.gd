class_name ExpeditionDirector
extends Node
## The pacing of an expedition: five waves on top of the cult's `EnemyWaves`.
##
## `EnemyWaves` decides *who* walks in (the counts, the kit tiers, the determinism);
## this node decides *when*, and what the field pays when it is over. Keeping the
## two apart is what lets the waves stay a plain spawner - the cage yard and the
## regression test drive `start_wave()` directly and never see a director.
##
## The wave curve is 3 / 4 / 4 / 5 / 6 bodies. Wave five is the Bilewarden's wave:
## three acolytes, two escorts in forged steel behind kite shields, and the boss
## himself at twice a guard's health, his blade anointed with a Tier 2 sigil that
## lives on the body and dies with the wave - the warband's brand ledger is the
## altar's to write, and an expedition never touches it.
## The boss and its escorts are *guests* handed to `EnemyWaves.start_wave()`, so
## they stand in the same roster as the acolytes: `living()` counts them, the wave
## is cleared only when the boss stops moving, and `total_cleared()` counts him.
##
## ## What a scene does with it
##
##   1. `setup(controller, warband, waves, loot, self)` once the waves exist;
##   2. connect `wave_started` / `wave_cleared` for the status line;
##   3. connect `expedition_cleared` and `expedition_wiped` for the end of the run;
##   4. `begin()` to open the first wave;
##   5. `step(delta, bodies)` every physics frame, before the warband's own step.
##
## `summary()` is the mission report `{waves, kills, items, gold, cruor}`. It is
## live: `waves`/`kills`/`items` keep counting after the run ends, and `gold` and
## `cruor` are what was actually paid, so a second read cannot invent a second
## payment. A wipe pays nothing and never will.

## The field opened, and the cult is on its way.
const STATE_RUNNING := "running"
## Every wave is down; the purse has been paid exactly once.
const STATE_CLEARED := "cleared"
## No warband body is left standing; nothing is paid.
const STATE_WIPED := "wiped"

signal wave_started(index: int, count: int)
signal wave_cleared(index: int)
## The fifth wave fell. Carries the same dictionary `summary()` returns.
signal expedition_cleared(summary: Dictionary)
## The warband is down. Carries the summary, whose gold and cruor are zero.
signal expedition_wiped(summary: Dictionary)

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Branded = preload("res://scripts/warband/branded_skills.gd")
const State = preload("res://scripts/player_state.gd")
const GuardScript = preload("res://scripts/warband/cultist_guard.gd")

## The wave curve, in order. `guards` is what `EnemyWaves` rolls from its own kit
## tiers for that index; `boss` adds the Bilewarden and its escort pair, so wave
## five stands six bodies tall (3 + 1 + 2).
const WAVES := [
	{"guards": 3},
	{"guards": 4},
	{"guards": 4},
	{"guards": 5},
	{"guards": 3, "boss": true},
]
## The breathing gap between waves: long enough to loot a body, short enough that
## the field never goes quiet.
const GAP_SECONDS := 2.0

## The Bilewarden: the cult's own champion. Double a guard's health is the whole
## rule - no new stat, no second health bar.
const BOSS_NAME := "Bilewarden"
const BOSS_HEALTH_SCALE := 2.0
const BOSS_MAIN := "sword_great"
const BOSS_OFF := ""
const BOSS_ARMOR := "plate"
## The escorts are forged steel behind a kite shield: the wave 3 tier, held by a
## named body so the boss is never the only thing that reads as deliberate.
const ESCORT_NAMES := ["Shield of the Bilewarden", "Hound of the Bilewarden"]
const ESCORT_MAIN := "sword_arming"
const ESCORT_OFF := "shield_kite"
const ESCORT_ARMOR := "mail"
## The tier the boss's blade was anointed at. A Tier 2 sigil on a Tier 3 altar
## economy: worth taking, not worth a full distilling chain.
const BOSS_BRAND_TIER := Contracts.CruorTier.T2_BLACK_BILE

## What a cleared expedition pays, per wave it walked through.
const GOLD_PER_WAVE := 25
const GOLD_BOSS_BONUS := 50
const CRUOR_PER_WAVE := 1          # T1 Ritual Tallow
const CRUOR_BOSS := 1              # T2 Black Bile, the Bilewarden's own blood

## Where the run stands. Read by the scene (the HUD hint) and by the tests.
var state := STATE_RUNNING

var _controller = null
var _warband = null
var _waves: EnemyWaves = null
## The wave on the field, or -1 before `begin()`.
var _index := -1
var _cleared_waves := 0
var _gap_left := 0.0
## Drops the field has actually booked into the stash this run.
var _items := 0
## What was paid, so a summary can never claim a payment that did not happen.
var _gold_paid := 0
var _cruor_paid: Dictionary = {}
var _boss: CultistGuard = null

## Point the director at a live field. `waves` is the spawner and `warband` the
## purse; `controller` answers what the warband's bodies are when a step is called
## without them. `loot` and `parent_node` are taken because the field hands them
## over - the guards are parented by the waves, and the harvest is reported back
## through `note_loot()` by the one node that sees the loot run book it.
func setup(controller, warband, waves, _loot, _parent_node: Node3D) -> void:
	_controller = controller
	_warband = warband
	_waves = waves
	state = STATE_RUNNING
	_index = -1
	_cleared_waves = 0
	_gap_left = 0.0
	_items = 0
	_gold_paid = 0
	_cruor_paid = {}
	_boss = null
	if _waves != null:
		if not _waves.wave_started.is_connected(_on_wave_started):
			_waves.wave_started.connect(_on_wave_started)
		if not _waves.wave_cleared.is_connected(_on_wave_cleared):
			_waves.wave_cleared.connect(_on_wave_cleared)

## Open the field with the first wave. Idempotent: a scene that calls it twice
## does not stack two waves in the yard.
func begin() -> void:
	if state != STATE_RUNNING or _waves == null or _index >= 0:
		return
	_field_wave(0)

## Advance the expedition by one frame. `bodies` is the warband; it is stepped
## with the cult so both factions separate, and it is what a wipe is judged on.
func step(delta: float, bodies: Array = []) -> void:
	if _waves == null:
		return
	if state == STATE_WIPED:
		# The cult still holds the field after the warband falls. Nothing else
		# ticks: the run is over and the scene is only waiting for the walk home.
		_waves.step(delta, _warband_bodies(bodies))
		return
	if state != STATE_RUNNING:
		return
	_waves.step(delta, _warband_bodies(bodies))
	if state != STATE_RUNNING:
		return
	_check_wipe(bodies)
	if state != STATE_RUNNING:
		return
	if _gap_left > 0.0:
		_gap_left -= delta
		if _gap_left <= 0.0:
			_gap_left = 0.0
			_field_wave(_index + 1)

# --- what the scene reads ---------------------------------------------------

## The wave on the field, 0-based, or -1 before `begin()`.
func wave_index() -> int:
	return _index

## How many waves this expedition has, boss wave included.
func wave_count() -> int:
	return WAVES.size()

## True once the run is over, cleared or wiped.
func finished() -> bool:
	return state == STATE_CLEARED or state == STATE_WIPED

func cleared() -> bool:
	return state == STATE_CLEARED

func wiped() -> bool:
	return state == STATE_WIPED

## Seconds until the next wave walks in, or 0 when one is already on the field.
func gap_left() -> float:
	return _gap_left

## The Bilewarden while its wave is on the field, else null.
func boss() -> CultistGuard:
	return _boss if is_instance_valid(_boss) else null

## `{waves, kills, items, gold, cruor}` - the mission report. `waves` counts the
## waves cleared, `kills` every cultist this field has taken (the boss and the
## escorts included), `items` the drops that actually reached the shared stash,
## and `gold`/`cruor` what was paid on a clear. A wipe's purse numbers are zero.
func summary() -> Dictionary:
	return {
		"waves": _cleared_waves,
		"kills": int(_waves.total_cleared()) if _waves != null else 0,
		"items": _items,
		"gold": _gold_paid,
		"cruor": _cruor_paid.duplicate(),
	}

## Book `count` pieces the field gathered into the shared stash. The scene calls
## this with whatever its vacuum and loot run reported, so the summary cannot
## disagree with the stash about what was picked up.
func note_loot(count: int) -> void:
	if count > 0:
		_items += count

# --- waves ------------------------------------------------------------------

func _field_wave(index: int) -> void:
	if _waves == null or index < 0 or index >= WAVES.size():
		return
	var plan: Dictionary = WAVES[index]
	_index = index
	_boss = null
	var guests: Array = []
	if bool(plan.get("boss", false)):
		guests = _boss_guests()
	_waves.start_wave(index, int(plan["guards"]), guests)

## The sigil the Bilewarden's blade is anointed with: whatever the altar would
## grant that blade class, at Tier 2. Returned empty when the catalog has no
## ability for the piece, which leaves the boss plain rather than wrong.
func _boss_ability() -> String:
	return Branded.for_subtype(Contracts.weapon_subtype(State.ITEMS.get(BOSS_MAIN, {})))

## The boss and its escort pair, in the shape `EnemyWaves.start_wave()` fields a
## guest with: a name, a kit, a health multiplier and - for the Bilewarden - the
## sigil his blade carries. The boss is last, so the escorts close in front of him.
##
## That brand is run-scoped: it lives on the body (`CultistGuard.brand`) and dies
## with the wave. The altar is the only thing that may write into the warband's
## own brand ledger, and it charges essence for it; a cult anointment is not
## currency and must never reach `Warband.cruor` or the save.
func _boss_guests() -> Array:
	var guests: Array = []
	for escort_name in ESCORT_NAMES:
		guests.append({"name": str(escort_name), "main": ESCORT_MAIN, "off": ESCORT_OFF,
			"armor": ESCORT_ARMOR, "health_scale": 1.0})
	var brand: Dictionary = {"tier": BOSS_BRAND_TIER, "ability": _boss_ability()}
	guests.append({"name": BOSS_NAME, "main": BOSS_MAIN, "off": BOSS_OFF,
		"armor": BOSS_ARMOR, "health_scale": BOSS_HEALTH_SCALE, "boss": true,
		"brand": brand})
	return guests

## The sigil on the Bilewarden's blade while its wave is on the field, else `{}`.
func boss_brand() -> Dictionary:
	return _boss.brand_of() if is_instance_valid(_boss) else {}

func _on_wave_started(index: int, count: int) -> void:
	_index = index
	# The waves own the crown: they remember which guest claimed it, so the scene
	# can name the boss the moment the wave walks in.
	_boss = _waves.boss() if _waves != null else null
	wave_started.emit(index, count)

func _on_wave_cleared(index: int) -> void:
	_cleared_waves = maxi(_cleared_waves, index + 1)
	wave_cleared.emit(index)
	if state != STATE_RUNNING:
		return
	if index + 1 >= WAVES.size():
		_finish(STATE_CLEARED)
		return
	_gap_left = GAP_SECONDS

# --- the end ----------------------------------------------------------------

## Whether anybody can still stand: a downed body is a body to step over, and a
## warband with nobody on their feet has lost the field.
func _check_wipe(bodies: Array) -> void:
	var field := _warband_bodies(bodies)
	if field.is_empty():
		return
	for body in field:
		if bool(body.get("alive")) and not bool(body.get("downed")):
			return
	_finish(STATE_WIPED)

func _finish(result: String) -> void:
	if state != STATE_RUNNING:
		return
	state = result
	_gap_left = 0.0
	if result == STATE_CLEARED:
		_pay()
	var report := summary()
	if result == STATE_CLEARED:
		expedition_cleared.emit(report)
	else:
		expedition_wiped.emit(report)

## Pay the expedition, once. The guard is the recorded payment, not the state, so
## even a scene that calls `_finish`-adjacent paths twice cannot flush two purses.
func _pay() -> void:
	if _warband == null or _gold_paid != 0 or not _cruor_paid.is_empty():
		return
	var waves := WAVES.size()
	var gold := GOLD_PER_WAVE * waves + GOLD_BOSS_BONUS
	var cruor := {
		Contracts.CruorTier.T1_RITUAL_TALLOW: CRUOR_PER_WAVE * waves,
		Contracts.CruorTier.T2_BLACK_BILE: CRUOR_BOSS,
	}
	_warband.award_gold(gold)
	for tier in cruor:
		_warband.cruor.add(int(tier), int(cruor[tier]))
	_gold_paid = gold
	_cruor_paid = cruor

## The warband bodies to step and to judge. The cage-style fallback keeps the
## director usable by a scene that forgets to pass them.
func _warband_bodies(bodies: Array) -> Array:
	if not bodies.is_empty():
		return bodies
	if _controller != null and is_instance_valid(_controller):
		return _controller.bodies()
	return []
