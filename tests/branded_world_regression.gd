extends SceneTree
## GHOST OF THE WARBAND - the branded sigil tile, driven on the real arena.
##
## The tile is a readout, so the only honest way to test it is to make the thing
## it reads happen: a real expedition (`admin_arena.tscn` with a deployment line),
## a real cultist guard, and the scene's own `R` binding. Every check below asks
## the tile what it prints after the runner and the body have actually moved, and
## the sigil is proven by the health the guard lost and by the runner's own
## record of what played - not by a number a helper returned.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Damage = preload("res://scripts/warband/damage_scaler.gd")
const Branded = preload("res://scripts/warband/branded_skills.gd")
const State = preload("res://scripts/player_state.gd")

const TEST_SAVE := "user://branded_world_state.json"
const WARBAND_SAVE := "user://branded_world_warband.json"
## One branded sword, one branded bow and one plain dagger: three different
## answers for the tile (a sword sigil, another sigil, nothing at all).
const BRANDED_MAIN := "sword_short"
const BOW_MAIN := "bow_short"
const PLAIN_MAIN := "dagger_iron"
const BRANDED_TIER := Contracts.CruorTier.T3_COAGULATED_CRUOR
const BOW_TIER := Contracts.CruorTier.T1_RITUAL_TALLOW
const BLOW_DELAY := 0.35

var game
var warband
var state
var tile
var checks := 0
var failures := 0
var _branded_id := -1
var _bow_id := -1
var _plain_id := -1

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("BRANDED_WORLD_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## One line mercenary with a main hand, the off hand the contract allows with it
## and one armor set, exactly as the cage and the town gate build a body.
func _recruit(name: String, main_id: String, off_id: String, armor: String) -> int:
	var merc_id: int = warband.add_mercenary(name)
	warband.roster.equip(merc_id, "main", main_id)
	if not off_id.is_empty() and not Contracts.two_handed_item(State.ITEMS.get(main_id, {})):
		warband.roster.equip(merc_id, "off", off_id)
	for slot in ["head", "chest", "hands", "legs", "feet"]:
		var armor_id := "armor_%s_%s" % [armor, slot]
		if State.ITEMS.has(armor_id):
			warband.roster.equip(merc_id, slot, armor_id)
	return merc_id

## The soul walks into a body the way the warband screen's click does.
func _take(merc_id: int) -> void:
	game.controller.direct(1, merc_id)

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

	_branded_id = _recruit("Aldous", BRANDED_MAIN, "shield_buckler", "leather")
	_bow_id = _recruit("Cael", BOW_MAIN, "", "cloth")
	_plain_id = _recruit("Brine", PLAIN_MAIN, "shield_kite", "mail")
	# Buy the two brands through the altar's own verb, so the runner is handed the
	# payload the altar writes and nothing is faked in the roster. The altar's
	# price is 2 T3 and 5 T1 per brand.
	warband.cruor.add(BRANDED_TIER, 4)
	warband.cruor.add(BOW_TIER, 10)
	var sword_brand: Dictionary = warband.cruor.brand(BRANDED_MAIN, BRANDED_TIER)
	var bow_brand: Dictionary = warband.cruor.brand(BOW_MAIN, BOW_TIER)
	check(bool(sword_brand.get("ok", false)) and bool(bow_brand.get("ok", false)),
		"the altar brands the sword and the bow")
	var fielded: Array = warband.deploy_battle([_branded_id, _bow_id, _plain_id])
	check(fielded.size() == 3, "three mercenaries are deployed")

	game = load("res://admin_arena.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.6).timeout

	tile = game.get_node_or_null("BrandedHud")
	check(tile != null, "the arena parents a branded sigil tile")
	if tile == null:
		_finish()
		return
	check(game.expedition, "a deployment line makes this a real expedition")
	check(game.branded != null, "the scene owns a brand runner")
	# The tile is a pure readout of the runner, so at boot it must agree with it:
	# the soul starts in the last body of the line, which here is plain steel.
	var boot_showing: bool = tile.is_showing()
	var boot_branded: bool = not game.branded.brand().is_empty()
	check(boot_showing == boot_branded,
		"the tile shows exactly when the body it follows carries a brand")
	check_layout()

	# --- plain steel: nothing to show ---------------------------------------
	_take(_plain_id)
	await process_frame
	check(game.controller.merc_for_peer(1) == _plain_id, "the soul is inside the plain-steel body")
	check(game.branded.brand().is_empty(), "a plain dagger carries no payload")
	check(not tile.is_showing(), "an unbranded main hand hides the tile entirely")
	check(not bool(game.branded.can_activate().get("ok", true)), "and the verb is refused")
	check(tile.title_text().is_empty() or not tile.is_showing(), "nothing is printed for it")

	# --- a branded sword: identity, tier line, cost, READY ------------------
	_take(_branded_id)
	await process_frame
	check(game.controller.merc_for_peer(1) == _branded_id, "the soul is inside the branded body")
	check(tile.is_showing(), "a branded main hand shows the tile")
	var sword_line := Branded.tier_line("rending_strike", BRANDED_TIER)
	check(tile.title_text() == sword_line,
		"the tile prints the tier line for its tier (%s)" % tile.title_text())
	check(tile.title_text().contains(Branded.ability_name("rending_strike")),
		"and the line names the ability")
	check(tile.cost_text() == "Cost 204 stamina",
		"the tile shows the tier's stamina cost (%s)" % tile.cost_text())
	check(tile.status_text() == "READY",
		"the sigil has not been used, so the tile reads READY (%s)" % tile.status_text())
	check(is_equal_approx(tile.cooldown_progress(), 1.0), "and the cooldown bar is full")

	# --- the real R press, on a real cultist --------------------------------
	await check_sigil_fires()

	# --- switching hands re-binds the tile ----------------------------------
	_take(_plain_id)
	await process_frame
	check(not tile.is_showing(), "switching to an unbranded body hides the tile again")

	_take(_bow_id)
	await process_frame
	check(tile.is_showing(), "a branded bow brings the tile back")
	var bow_line := Branded.tier_line("arrow_barrage", BOW_TIER)
	check(tile.title_text() == bow_line,
		"the tile follows the new ability (%s)" % tile.title_text())
	check(tile.title_text().contains(Branded.ability_name("arrow_barrage")),
		"the new line names the barrage")
	check(tile.status_text() == "READY",
		"a rebind is a new sigil, so it starts ready (%s)" % tile.status_text())
	check(tile.cost_text() == "Cost 180 stamina",
		"and shows the bow's own cost (%s)" % tile.cost_text())

	_finish()

## The tile prints its sigil; it must never print over the battle readout. The
## HUD owns the top-left panel column, the top-right purse and the centre lines,
## so the tile's rectangle is checked against those four.
func check_layout() -> void:
	var view := root.get_visible_rect().size
	check(view.x > 0.0 and view.y > 0.0, "headless still has a canvas to lay out (%.0fx%.0f)" % [view.x, view.y])
	var tile_rect: Rect2 = tile.get_node("Root/BrandTile").get_global_rect()
	check(tile_rect.size.x > 100.0 and tile_rect.size.y > 60.0,
		"the tile has a real rectangle (%.0fx%.0f)" % [tile_rect.size.x, tile_rect.size.y])
	check(tile_rect.position.y > view.y * 0.5,
		"the tile sits in the lower half of the screen (y=%.0f of %.0f)" % [tile_rect.position.y, view.y])
	check(tile_rect.end.x <= view.x and tile_rect.end.y <= view.y,
		"and inside the canvas")
	var hud: Node = game.get_node_or_null("HudLayer/WarbandHud")
	check(hud != null, "the battle readout is still the scene's own HUD")
	if hud == null:
		return
	for row in ["Root/BodyPanel", "Root/SquadPanel", "Root/Hint", "Root/Status", "Root/Purse"]:
		var other := hud.get_node_or_null(row) as Control
		if other == null:
			continue
		var other_rect := other.get_global_rect()
		if other_rect.size.x <= 0.0 or other_rect.size.y <= 0.0:
			continue
		check(not tile_rect.intersects(other_rect),
			"the tile never covers the HUD's %s" % row.get_slice("/", 1))

## Fire the sigil through the scene's own `R` binding at a cultist standing in
## front of the body, and read the tile and the runner afterwards.
func check_sigil_fires() -> void:
	var body = game.controller.active_body(1)
	check(body != null, "the soul is in a live body")
	if body == null:
		return
	var guards: Array = game.waves.guards() if game.waves != null else []
	check(not guards.is_empty(), "the expedition put cultist guards on the field")
	if guards.is_empty():
		return
	var guard = guards[0]
	# In front of the body, inside Rending Strike's reach (2.6 m, 120 degrees).
	guard.global_position = body.global_position + (-body.global_basis.z) * 1.6
	await physics_frame
	await physics_frame
	var before: float = float(guard.get("health"))
	var armed: Dictionary = game.branded.can_activate()
	check(bool(armed.get("ok", false)), "the sigil is ready to fire (%s)" % str(armed.get("reason", "")))
	var stamina_before: float = float(body.get("stamina"))

	await _press_r()
	await create_timer(BLOW_DELAY).timeout

	var effect: Dictionary = game.branded.last_effect()
	check(bool(effect.get("ok", false)), "R fired the sigil")
	check(str(effect.get("ability", "")) == "rending_strike",
		"the branded ability is what played, not the melee fallback (%s)" % str(effect.get("ability", "")))
	check(float(effect.get("damage", 0.0)) > 0.0, "the sigil rolled damage (%.1f)" % float(effect.get("damage", 0.0)))
	check(int(effect.get("victims", 0)) >= 1, "and struck a body (%d)" % int(effect.get("victims", 0)))
	check(float(body.get("stamina")) < stamina_before, "the stamina cost was paid")
	check(float(guard.get("health")) < before,
		"the cultist guard lost health to it (%.1f -> %.1f)" % [before, float(guard.get("health"))])

	check(game.branded.cooldown_left() > 0.0,
		"the sigil is on cooldown (%.2f s)" % game.branded.cooldown_left())
	check(not bool(game.branded.can_activate().get("ok", true)),
		"a second press is refused while it runs")
	check(tile.status_text() != "READY",
		"the tile leaves READY (%s)" % tile.status_text())
	check(_status_seconds() > 0.0,
		"and reads a positive countdown (%s)" % tile.status_text())
	check(tile.cooldown_progress() < 1.0,
		"the cooldown bar is draining (%.2f)" % tile.cooldown_progress())

## `R` as the player sends it: a real key event through the input pipeline, so
## this proves the arena's binding and not just the private method behind it.
func _press_r() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_R
	event.physical_keycode = KEY_R
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	await process_frame

## The seconds the tile is counting down, or 0 when it reads anything else.
func _status_seconds() -> float:
	var text: String = tile.status_text()
	if not text.ends_with(" s"):
		return 0.0
	return float(text.trim_suffix(" s"))

func _finish() -> void:
	if game != null:
		game.queue_free()
		await process_frame
	Damage.reset()
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("BRANDED_WORLD_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
