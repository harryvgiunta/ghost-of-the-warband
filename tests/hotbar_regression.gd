extends SceneTree
## Hotbar layout: the ten keys are the player's. The kit still decides which
## skills exist, but the order the player arranges in the paperdoll decides which
## key fires each one - on the HUD, in the runner (a moved skill keeps its
## cooldown) and after a save round-trip. A lent warband refuses the change, and
## the corpse screen never offers the row.

const Actor = preload("res://scripts/warband/warband_body.gd")
const State = preload("res://scripts/player_state.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const SeatLoadout = preload("res://scripts/seat_loadout.gd")
const DollScript = preload("res://scripts/warband/warband_paperdoll.gd")
const HudScript = preload("res://scripts/warband/warband_hud.gd")

const ARMOR := {"head": 0, "chest": 0, "hands": 0, "legs": 0, "feet": 0}
const TEST_SAVE := "user://hotbar_regression_state.json"

var checks := 0
var failures := 0
var warband

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("HOTBAR_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _on_watchdog() -> void:
	check(false, "the regression did not finish in time")
	print("HOTBAR_REGRESSION checks=", checks, " failures=", failures)
	quit(1)

func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

## Same ids in the same order. Arrays hold plain strings, so this is the one
## comparison every check below uses.
func _same(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for index in actual.size():
		if str(actual[index]) != str(expected[index]):
			return false
	return true

## The non-empty skill ids a grant list or a HUD state list names, in order.
func _ids(definitions: Array) -> Array:
	var out := []
	for definition in definitions:
		var id := str(definition.get("id", ""))
		if not id.is_empty():
			out.append(id)
	return out

## The skill a tile is currently drawing, "" for an empty tile.
func tile_id(tile) -> String:
	var definition = tile.get("_definition")
	return str(definition.get("id", "")) if definition is Dictionary else ""

## The key a tile is labelled with.
func tile_key(tile) -> String:
	var label = tile.get("_key")
	return str(label.text) if label != null else ""

## A real warband body with its own rig, built the way the campaign spawns one.
func fighter(parent: Node3D, index: int, at: Vector3) -> Node3D:
	var actor := Actor.new()
	actor.slot = index
	actor.authoritative = true
	parent.add_child(actor)
	actor.configure(index + 1, "Probe", at)
	actor.set_process(false)
	actor.rig.set_physics_process(false)
	actor.set_physics_process(false)
	actor.combat.set_motion(Vector3.ZERO, false, true)
	actor.combat.grounded = true
	return actor


func run() -> void:
	var watchdog := create_timer(30.0)
	watchdog.timeout.connect(_on_watchdog)
	_remove_test_save()
	warband = root.get_node("Warband")
	warband.save_path = TEST_SAVE
	warband.reset_state()
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	_check_rules()
	_check_rig(world)
	_check_warband()
	_check_wear_order()
	_check_paperdoll()
	world.queue_free()
	warband.reset_state()
	_remove_test_save()
	print("HOTBAR_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


## The order is a ranking of ids: named skills first in the named sequence,
## everything else after them in the kit's own order. Garbage in the layout is
## ignored rather than becoming a slot.
func _check_rules() -> void:
	var kit := ["barrage", "triple_volley", "energy_shield"]
	check(_same(AbilityRules.ordered_ids(kit, ["energy_shield", "barrage"]),
		["energy_shield", "barrage", "triple_volley"]),
		"the layout lifts the skills it names to the front, in its own sequence")
	check(_same(AbilityRules.ordered_ids(kit, []), kit),
		"an empty layout is the kit's own order")
	check(_same(AbilityRules.ordered_ids(kit, ["bogus", "barrage", "barrage"]),
		["barrage", "triple_volley", "energy_shield"]),
		"unknown and duplicate ids in the layout are ignored")
	check(_same(AbilityRules.ordered_ids(kit, "not a list"), kit),
		"a malformed layout leaves the kit's order alone")

	var grants := AbilityRules.grants_for("bow_short", "",
		{"main": ["barrage", "triple_volley"], "off": []}, {"neck": "neck_shield"})
	check(_same(_ids(grants), kit),
		"the kit's grants are the main hand's welds then the worn necklace")


## A rig laid out by the player: `granted` puts the named skill on the named
## key, the HUD draws that key, and a skill that moves carries its cooldown.
func _check_rig(world: Node3D) -> void:
	var kit := ["barrage", "triple_volley", "energy_shield"]
	var actor := fighter(world, 0, Vector3.ZERO)
	actor.rig.apply_loadout(State.build_loadout("bow_short", "", ARMOR,
		{"neck": "neck_shield"}))
	actor.rig.anointed = {"main": AbilityRules.skill_ids(["barrage", "triple_volley"]),
		"off": []}
	check(_same(_ids(AbilityRules.granted(actor.rig)), kit),
		"with no layout the keys follow kit order")
	check(AbilityRules.granted(actor.rig).size() == AbilityRules.SLOT_COUNT,
		"the hotbar is always ten slots wide")

	actor.rig.hotbar_order = AbilityRules.skill_ids(["energy_shield", "barrage"])
	check(_same(_ids(AbilityRules.granted(actor.rig)),
		["energy_shield", "barrage", "triple_volley"]),
		"the layout decides which key fires which skill")
	check(str(AbilityRules.definition_for(actor.rig, 0).get("id", "")) == "energy_shield",
		"key 1 is the first skill the layout names")
	check(str(AbilityRules.definition_for(actor.rig, 2).get("id", "")) == "triple_volley",
		"a skill the layout does not name keeps its place after the named ones")
	check(AbilityRules.definition_for(actor.rig, 5).is_empty(),
		"a key with no grant is empty")

	# The dressing hand-off: a seat loadout carries the layout beside the kit and
	# turns it into the rig's own key order.
	SeatLoadout.apply(actor.rig,
		State.build_loadout("bow_short", "", ARMOR, {"neck": "neck_shield"}),
		[], {}, ["energy_shield", "barrage"])
	check(_same(Array(actor.rig.hotbar_order), ["energy_shield", "barrage"]),
		"a dressing puts the body's layout on the rig")

	# A moved skill keeps its timer: the cooldown belongs to the skill, not the
	# key, so reordering the row is never a free reset.
	actor.rig.apply_loadout(State.build_loadout("bow_short", "", ARMOR,
		{"neck": "neck_shield"}))
	actor.rig.anointed = {"main": AbilityRules.skill_ids(["barrage", "triple_volley"]),
		"off": []}
	actor.rig.hotbar_order.clear()
	actor.ability.setup(actor, actor.rig, actor.combat, 5.5)
	check(_same(_ids(AbilityRules.granted(actor.rig)), kit),
		"the runner starts on kit order")
	actor.ability.cooldowns[0] = 3.0
	actor.rig.hotbar_order = AbilityRules.skill_ids(["triple_volley"])
	actor.ability._refresh_grants()
	check(is_equal_approx(actor.ability.cooldowns[1], 3.0),
		"a moved skill carries its cooldown to its new key, got %.2f"
		% actor.ability.cooldowns[1])
	check(is_equal_approx(actor.ability.cooldowns[0], 0.0),
		"the skill that took the old key starts ready")
	var states: Array = actor.ability.hud_states()
	check(str(states[0].get("id", "")) == "triple_volley",
		"the HUD state follows the layout on key 1")
	check(str(states[1].get("id", "")) == "barrage",
		"the HUD state follows the layout on key 2")

	# The HUD draws the very same row.
	var hud := HudScript.new()
	hud.name = "Hud"
	world.add_child(hud)
	hud.set_body(actor, "Probe", 1)
	var tiles: Array = hud.ability_tiles()
	check(tile_id(tiles[0]) == "triple_volley",
		"the HUD's first tile is the skill the player put on key 1, got %s"
		% tile_id(tiles[0]))
	check(tile_id(tiles[1]) == "barrage", "the HUD's second tile follows the layout")
	check(tile_key(tiles[0]) == "1" and tile_key(tiles[1]) == "2",
		"the tile numbers stay the keys, not the kit order")
	hud.queue_free()


## The warband owns the saved layout: it validates against the body's own kit,
## survives a save round-trip, and refuses a lent copy.
func _check_warband() -> void:
	warband.reset_state()
	var merc: int = warband.add_mercenary("Keys")
	warband.stash.add("bow_short", 1)
	warband.stash.add("neck_shield", 1)
	warband.stash.add("ring_dash", 1)
	check(bool(warband.equip_merc(merc, "main", "bow_short").get("ok", false)),
		"the body holds a bow")
	check(bool(warband.equip_merc(merc, "neck", "neck_shield").get("ok", false)),
		"the body wears the amulet")
	check(bool(warband.equip_merc(merc, "ring1", "ring_dash").get("ok", false)),
		"the body wears the dash ring")
	check(warband.grant_anointing("bow_short"), "the altar wakes the bow's skill")

	var kit := ["barrage", "energy_shield", "dash"]
	check(_same(warband.hotbar_kit(merc), kit),
		"the kit lists the main hand's skill then each worn granting trinket")
	check(_same(warband.hotbar_layout(merc), kit + ["", "", "", "", "", "", ""]),
		"the layout pads the kit to ten keys")

	var moved: Dictionary = warband.move_hotbar_skill(merc, 0, 2)
	check(bool(moved.get("ok", false)), "moving a skill answers ok: %s"
		% str(moved.get("message", "")))
	check(_same(warband.hotbar_layout(merc),
		["dash", "energy_shield", "barrage", "", "", "", "", "", "", ""]),
		"moving a skill onto another key swaps them, got %s"
		% str(warband.hotbar_layout(merc)))
	check(_same(Array(warband.roster.hotbar_order_of(merc)),
		["dash", "energy_shield", "barrage"]),
		"the row is saved as the body's sequence")

	var swapped: Dictionary = warband.move_hotbar_skill(merc, 0, 1)
	check(bool(swapped.get("ok", false)) and str(swapped.get("message", "")) == "Skills swapped.",
		"moving onto a full key swaps the two, got %s" % str(swapped.get("message", "")))
	check(_same(warband.hotbar_layout(merc),
		["energy_shield", "dash", "barrage", "", "", "", "", "", "", ""]),
		"the two skills trade keys")

	var refused: Dictionary = warband.move_hotbar_skill(merc, 3, 4)
	check(not bool(refused.get("ok", true)), "moving two empty keys refuses")
	var written: Dictionary = warband.set_hotbar_order(merc, ["dash", "bogus", "dash"])
	check(bool(written.get("ok", false)), "a hand-written layout is accepted")
	check(_same(Array(written.get("order", [])), ["dash", "barrage", "energy_shield"]),
		"unknown and duplicate ids are dropped and the rest follow in kit order, got %s"
		% str(written.get("order", [])))

	# The layout is part of the saved warband, not a session preference.
	var saved: Dictionary = warband.to_dict()
	warband.reset_state()
	warband.from_dict(saved)
	check(warband.roster.count() == 1, "the body is back after the round-trip")
	check(_same(Array(warband.roster.hotbar_order_of(merc)),
		["dash", "barrage", "energy_shield"]),
		"the hotbar layout survives a save round-trip")
	check(_same(warband.hotbar_layout(merc),
		["dash", "barrage", "energy_shield", "", "", "", "", "", "", ""]),
		"and still fires from the saved keys")

	var reset: Dictionary = warband.reset_hotbar(merc)
	check(bool(reset.get("ok", false)), "KIT ORDER answers ok")
	check(warband.roster.hotbar_order_of(merc).is_empty(),
		"KIT ORDER stores no layout")
	check(_same(warband.hotbar_layout(merc), kit + ["", "", "", "", "", "", ""]),
		"KIT ORDER hands the keys back to the kit")

	warband.set_hotbar_order(merc, ["energy_shield", "dash", "barrage"])
	warband.lent = true
	var lent_refusal: Dictionary = warband.move_hotbar_skill(merc, 0, 1)
	check(not bool(lent_refusal.get("ok", true))
		and str(lent_refusal.get("message", "")) == warband.LENT_MESSAGE,
		"a lent warband refuses the layout, got %s" % str(lent_refusal.get("message", "")))
	check(_same(Array(warband.roster.hotbar_order_of(merc)),
		["energy_shield", "dash", "barrage"]),
		"and the host's order is untouched")
	warband.lent = false


## The keys follow the order the body is worn: the main hand, the off hand, then
## the necklace, ring 1 and ring 2 - the same order the page lists the slots in
## and the arming dresses them, so key 1 is the row at the top of the page.
func _check_wear_order() -> void:
	warband.reset_state()
	var merc: int = warband.add_mercenary("Worn")
	for item_id in ["sword_arming", "shield_kite", "neck_shield", "ring_dash", "ring_echo"]:
		warband.stash.add(item_id, 1)
	warband.equip_merc(merc, "main", "sword_arming")
	warband.equip_merc(merc, "off", "shield_kite")
	warband.equip_merc(merc, "neck", "neck_shield")
	warband.equip_merc(merc, "ring1", "ring_dash")
	warband.equip_merc(merc, "ring2", "ring_echo")
	warband.grant_anointing("sword_arming")
	warband.grant_anointing("shield_kite")
	check(_same(warband.hotbar_layout(merc),
		["lunge_thrust", "shield_charge", "energy_shield", "dash",
			"", "", "", "", "", ""]),
		"an unwritten layout is the wear order - main hand, off hand, then the trinkets, got %s"
		% str(warband.hotbar_layout(merc)))
	check(Contracts.slot_id(Contracts.SLOT_ORDER[0]) == "main"
			and Contracts.slot_id(Contracts.SLOT_ORDER[1]) == "off",
		"and the page lists the slots in that order, steel first")


## The paperdoll row: the same ten keys, click-to-swap, a reset that hands the
## order back to the kit, and no row on a corpse.
func _check_paperdoll() -> void:
	warband.reset_state()
	var merc: int = warband.add_mercenary("Keys")
	warband.stash.add("bow_short", 1)
	warband.stash.add("neck_shield", 1)
	warband.stash.add("ring_dash", 1)
	warband.equip_merc(merc, "main", "bow_short")
	warband.equip_merc(merc, "neck", "neck_shield")
	warband.equip_merc(merc, "ring1", "ring_dash")
	warband.grant_anointing("bow_short")

	var doll = DollScript.new()
	doll.configure(warband)
	root.add_child(doll)
	doll.open(merc)
	check(doll.controlled_merc == merc,
		"opening the page on a body makes it the controlled body")
	check(doll._hotbar_label.text.contains("THE BODY YOU CONTROL"),
		"the hotbar row says whose row it is, got %s" % doll._hotbar_label.text)
	check(doll._merc_label.text.contains("YOU"),
		"and the page's identity says it is the player's body, got %s"
		% doll._merc_label.text)
	check(doll._worn_title.text.contains("KEYS"),
		"the worn column names the body, got %s" % doll._worn_title.text)
	check(doll.hotbar_tiles.size() == AbilityRules.SLOT_COUNT,
		"the paperdoll draws one key per slot, got %d" % doll.hotbar_tiles.size())
	check(doll.hotbar_buttons.size() == AbilityRules.SLOT_COUNT,
		"every key has a button to click")
	check(_same(doll.hotbar_layout(), warband.hotbar_layout(merc)),
		"the paperdoll's row is the body's own layout")
	check(tile_id(doll.hotbar_tiles[0]) == "barrage",
		"the first key draws the main hand's skill, got %s"
		% tile_id(doll.hotbar_tiles[0]))
	check(tile_key(doll.hotbar_tiles[0]) == "1", "the tile still labels key 1")
	check(doll.hotbar_tiles[0].get("_icon").texture != null,
		"a granted key draws its skill's icon")
	check(doll.hotbar_tiles[5].get("_icon").texture == null,
		"an empty key draws no icon")
	# The row is the HUD's own measure, and the block is cut to it: the header,
	# the KIT ORDER press and the tenth key end on the same edge.
	var row: HBoxContainer = doll._hotbar_box.get_node("Keys")
	var measured := row.get_combined_minimum_size()
	check(is_equal_approx(measured.x, DollScript.HOTBAR_WIDTH),
		"the keys fill the hotbar block exactly, got %.1f of %.1f"
		% [measured.x, DollScript.HOTBAR_WIDTH])
	check(is_equal_approx(doll._hotbar_box.custom_minimum_size.x, DollScript.HOTBAR_WIDTH),
		"and the block takes the keys' own width, not the column's")
	check(doll.hotbar_buttons[0].tooltip_text.contains("Barrage"),
		"hovering a key names the skill on it, got %s"
		% doll.hotbar_buttons[0].tooltip_text)
	check(not doll._reset_hotbar_button.disabled,
		"a kit with skills can hand the order back")

	# Click a skill, then the key it belongs on.
	doll.hotbar_buttons[0].pressed.emit()
	check(doll._hotbar_selected == 0, "the first click picks the key up")
	check(doll.status_text().contains("Barrage"),
		"the status line says what was picked, got %s" % doll.status_text())
	doll.hotbar_buttons[2].pressed.emit()
	check(doll._hotbar_selected == -1, "the second click puts it down")
	check(_same(doll.hotbar_layout(),
		["dash", "energy_shield", "barrage", "", "", "", "", "", "", ""]),
		"the row redraws in the new order, got %s" % str(doll.hotbar_layout()))
	check(doll.status_text().contains("swapped"), "the swap is reported, got %s"
		% doll.status_text())

	# A second press on the picked key drops the pick instead of moving it.
	var before := doll.hotbar_layout()
	doll.hotbar_buttons[0].pressed.emit()
	doll.hotbar_buttons[0].pressed.emit()
	check(doll._hotbar_selected == -1, "clicking the picked key twice drops it")
	check(_same(doll.hotbar_layout(), before), "and the row is unchanged")

	# An empty key cannot start a move.
	doll.hotbar_buttons[8].pressed.emit()
	check(doll._hotbar_selected == -1, "an empty key cannot be picked up")
	check(doll.status_text().contains("fires nothing"),
		"the empty key says why, got %s" % doll.status_text())

	# Picking a mercenary resets the pending pick.
	doll.hotbar_buttons[0].pressed.emit()
	check(doll._hotbar_selected == 0, "a key can be picked up again")
	doll.select_merc(merc)
	check(doll._hotbar_selected == -1, "switching bodies drops the pending pick")

	doll._reset_hotbar_button.pressed.emit()
	check(_same(doll.hotbar_layout(),
		["barrage", "energy_shield", "dash", "", "", "", "", "", "", ""]),
		"KIT ORDER hands the keys back to the kit, got %s"
		% str(doll.hotbar_layout()))

	# Another body's page says whose row it is, and a page on the body the soul is
	# in follows the soul when it changes bodies.
	var other: int = warband.add_mercenary("Other")
	doll.select_merc(other)
	check(doll._hotbar_label.text.contains("NOT YOUR BODY"),
		"another body's row says it is not the player's, got %s" % doll._hotbar_label.text)
	check(not doll._merc_label.text.contains("YOU"),
		"and its identity carries no mark of the player's body, got %s"
		% doll._merc_label.text)
	doll.select_merc(merc)
	doll.follow_controlled(other)
	check(doll.selected_merc == other,
		"a page on the body the soul leaves follows the soul")
	doll.follow_controlled(merc)
	check(doll.selected_merc == merc, "and follows it back")

	# The dead body's screen is a looting screen: no hotbar row.
	doll.show_corpse(99, ["dagger_iron"])
	check(not doll._hotbar_box.visible, "the corpse screen hides the hotbar row")
	doll.clear_corpse()
	check(doll._hotbar_box.visible, "the mercenary screen shows it again")
	doll.close()
	doll.queue_free()
