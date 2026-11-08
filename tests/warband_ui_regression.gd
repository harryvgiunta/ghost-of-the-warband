extends SceneTree
## Warband UI regression: the tactical screen tells the truth about a warband
## with a living, a downed and a dead body; click-to-control emits once and only
## for a body the player may actually enter; `Warband.changed` repaints without a
## reopen; the paperdoll dresses and undresses a mercenary out of the collective
## stash without losing a single gold of value; and the recruiter charges the
## vendor's price and refuses honestly at the hire cap.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const ScreenScript = preload("res://scripts/warband/warband_screen.gd")
const DollScript = preload("res://scripts/warband/warband_paperdoll.gd")
const Cruor = preload("res://scripts/warband/cruor_manager.gd")
const LedgerFrameScript = preload("res://scripts/ui/ledger_frame.gd")
const State = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const TrinketStats = preload("res://scripts/trinket_stats.gd")

const TEST_SAVE := "user://warband_ui_state.json"

var checks := 0
var failures := 0
var state
var warband

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WARBAND_UI_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

func _set_gold(amount: int) -> void:
	state.add_credits(amount - int(state.credits))

func run() -> void:
	_remove_test_save()
	state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = TEST_SAVE
	warband.reset_state()
	_set_gold(1000)
	_check_rows_and_control()
	_check_refresh()
	_check_paperdoll()
	_check_bench()
	await _check_strip()
	_check_item_hover()
	_check_reequip_buttons()
	_check_recruiter()
	_check_old_save_purge()
	warband.reset_state()
	state.reset(false)
	_remove_test_save()
	print("WARBAND_UI_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

# --- the screen ------------------------------------------------------------

func _check_rows_and_control() -> void:
	warband.reset_state()
	_set_gold(1000)
	var alive: int = warband.add_mercenary("Aldous")
	var downed: int = warband.add_mercenary("Brine")
	var fallen: int = warband.add_mercenary("Cael")
	warband.stash.add("dagger_iron", 1)
	check(bool(warband.equip_merc(fallen, "main", "dagger_iron").get("ok", false)),
		"the doomed body wears a dagger")
	var pieces_before: int = warband.stash.pooled_count("dagger_iron")
	warband.roster.apply_damage(downed, 100.0)
	warband.roster.apply_damage(fallen, 120.0)
	check(warband.roster.state_of(alive) == Contracts.HealthState.ALIVE, "the first mercenary stands")
	check(warband.roster.state_of(downed) == Contracts.HealthState.DOWNED, "100 damage only downs")
	check(not warband.roster.has(fallen), "120 damage kills and takes the record with it")
	check(warband.roster.count() == 2, "the dead leave the roster at once (%d left)"
		% warband.roster.count())
	check(warband.stash.pooled_count("dagger_iron") == pieces_before + 1,
		"what the dead were wearing goes back into the shared stash")

	var souls = warband.souls
	var screen = ScreenScript.new()
	screen.configure(warband, souls)
	root.add_child(screen)
	screen.open()
	check(screen.is_open(), "open() opens the screen")
	check(screen.rows.size() == 2, "one row per mercenary still on the books, got %d"
		% screen.rows.size())
	check(not screen.rows.has(fallen), "the fallen have no row")
	check(screen.rows[alive]["name"].text == "Aldous", "the row names the mercenary")
	check(screen.rows[downed]["name"].text == "Brine", "rows stay in roster order")

	check(screen.rows[alive]["state"].text == "ALIVE", "the living row reads ALIVE")
	check(screen.rows[downed]["state"].text == "DOWNED", "the downed row reads DOWNED")
	check(screen.rows[downed]["state"].get_theme_color("font_color")
		!= screen.rows[alive]["state"].get_theme_color("font_color"),
		"a downed row is coloured apart from a living one")
	check(screen.rows[alive]["bar"].value == 100.0, "the live health bar reads the roster")
	check(screen.rows[alive]["health"].text == "100 / 100", "the health line reads the roster")
	check(screen.rows[downed]["bar"].value == 0.0, "a downed body reads zero health")
	check(screen.rows[alive]["gear"].text.contains("empty"),
		"the gear summary names the empty hands: %s" % screen.rows[alive]["gear"].text)

	check(not screen.rows[alive]["control"].disabled, "a living body can be controlled")
	check(screen.rows[downed]["control"].disabled, "a downed body cannot be jumped into")

	check(screen.gold_label.text == "1000 G", "the header shows the purse, got %s" % screen.gold_label.text)
	check(screen.value_label.text.contains(str(warband.total_value())),
		"the header shows the warband's worth, got %s" % screen.value_label.text)

	var seen: Array[int] = []
	screen.possess_requested.connect(func(merc_id: int) -> void: seen.append(merc_id))
	screen.rows[alive]["control"].pressed.emit()
	check(seen.size() == 1 and seen[0] == alive,
		"clicking the living row emits exactly one possess_requested, got %s" % str(seen))
	screen.rows[downed]["control"].pressed.emit()
	check(seen.size() == 1, "disabled rows never emit, got %s" % str(seen))

	# Another peer inside the living body: the button advertises the lock.
	var body := Node3D.new()
	souls.register_body(alive, body, "Aldous")
	# Re-binding the same warband and router must not duplicate rows or wires:
	# the possession checks below run on the freshly attached listener.
	screen.configure(warband, souls)
	check(screen.rows.size() == 2, "re-configuring keeps one row per mercenary")
	check(bool(souls.request_transfer(7, alive).get("ok", false)), "peer 7 takes the living body")
	check(screen.rows[alive]["control"].disabled, "a body held by another peer is disabled")
	check(screen.rows[alive]["control"].text == "IN USE", "the held body says so")
	screen.rows[alive]["control"].pressed.emit()
	check(seen.size() == 1, "an occupied body cannot be requested")
	souls.release_peer(7, "test")
	check(not screen.rows[alive]["control"].disabled, "the released body is controlable again")
	souls.unregister_body(alive)
	body.free()
	screen.close()
	check(not screen.is_open(), "close() closes the screen")

func _check_refresh() -> void:
	var alive := int(warband.roster.ids()[0])
	var screen = ScreenScript.new()
	screen.configure(warband)
	root.add_child(screen)
	screen.open()
	warband.roster.set_health(alive, 55.0)
	warband.changed.emit()
	check(screen.is_open(), "a changed warband does not close the screen")
	check(screen.rows[alive]["health"].text == "55 / 100",
		"Warband.changed repaints the health line, got %s" % screen.rows[alive]["health"].text)
	check(screen.rows[alive]["bar"].value == 55.0, "Warband.changed repaints the bar")
	check(screen.rows[alive]["gear"].text.contains("empty"), "the row is still the same row")
	warband.stash.add("sword_short", 1)
	warband.equip_merc(alive, "main", "sword_short")
	check(screen.rows[alive]["gear"].text.contains("Shortsword"),
		"an equip made elsewhere shows in the gear summary, got %s"
		% screen.rows[alive]["gear"].text)
	screen.close()

# --- an old file's dead ----------------------------------------------------

## A save written before the dead left the books still carries their records.
## Opening it must free the hire cap on the spot and hand the stash back what
## the corpse was wearing - not inherit a graveyard and its kit.
func _check_old_save_purge() -> void:
	warband.reset_state()
	_set_gold(0)
	var survivor: int = warband.add_mercenary("Ash")
	var fallen: int = warband.add_mercenary("Bram")
	warband.roster.equip(fallen, "main", "sword_short")
	var data: Dictionary = warband.to_dict()
	var records: Array = data["roster"]["mercenaries"]
	for record in records:
		if int((record as Dictionary)["id"]) == fallen:
			record["state"] = Contracts.HealthState.DEAD
			record["health"] = 0.0
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	check(warband.load_state(), "an old save with a dead record still loads")
	check(not warband.roster.has(fallen), "the dead record is gone from the roster")
	check(warband.roster.has(survivor), "the living record stays")
	check(warband.roster.count() == 1, "the party is the living alone (%d)"
		% warband.roster.count())
	check(warband.stash.pooled_count("sword_short") == 1,
		"and what the dead body wore is back in the shared stash")

# --- the paperdoll ---------------------------------------------------------

func _stash_row(doll, item_id: String) -> Dictionary:
	for row in doll.stash_rows:
		if str(row["item_id"]) == item_id:
			return row
	return {}

func _check_paperdoll() -> void:
	warband.reset_state()
	_set_gold(1000)
	var first: int = warband.add_mercenary("Aldous")
	var other: int = warband.add_mercenary("Brine")
	warband.stash.add("sword_short", 2)
	warband.stash.add("shield_buckler", 1)
	warband.stash.add("sword_great", 1)
	var baseline: int = warband.total_value()

	var doll = DollScript.new()
	doll.configure(warband)
	root.add_child(doll)
	doll.open(first)
	var notices := [0]
	doll.changed.connect(func() -> void: notices[0] += 1)
	check(doll.is_open(), "open() opens the paperdoll")
	check(doll.selected_merc == first, "the paperdoll opens on the asked-for mercenary")
	check(doll.slot_rows.size() == Contracts.SLOT_ORDER.size(), "all ten worn slots are drawn")
	check(Contracts.slot_id(Contracts.SLOT_ORDER[0]) == "main"
			and Contracts.slot_id(Contracts.SLOT_ORDER[1]) == "off",
		"the rows put the steel first, in the order the body is armed")
	check(doll.controlled_merc == first, "the page opens on the body the soul is in")
	check(doll.picker_buttons[first].text.contains("YOU"),
		"the body under the soul carries its own mark, got %s"
		% doll.picker_buttons[first].text)
	check(doll.picker_buttons.size() == 2, "the picker strip has one button per mercenary")
	check(doll.stash_rows.size() == 3, "the stash lists every unequipped piece, got %d"
		% doll.stash_rows.size())
	check(str(warband.roster.equipped_of(first)["main"]).is_empty(), "the mercenary starts bare")
	check(doll.slot_rows["main"]["button"].text.contains("empty"), "an empty slot says empty")

	# A free copy goes into the clicked slot.
	doll.slot_rows["main"]["button"].pressed.emit()
	check(doll.selected_slot == Contracts.SlotType.MAIN_HAND, "clicking a slot selects it")
	check(str(warband.roster.equipped_of(first)["main"]).is_empty(),
		"clicking an empty slot only selects it")
	var row := _stash_row(doll, "sword_short")
	check(not row.is_empty(), "the shortsword is on the stash list")
	row["button"].pressed.emit()
	check(str(warband.roster.equipped_of(first)["main"]) == "sword_short",
		"clicking a free copy wears it in the selected slot")
	check(warband.stash.pooled_count("sword_short") == 1, "the pool count drops by one")
	check(int(_stash_row(doll, "sword_short")["pooled"]) == 1, "the row shows the new pool count")
	check(doll.slot_rows["main"]["button"].text.contains("Shortsword"),
		"the worn slot label updates, got %s" % doll.slot_rows["main"]["button"].text)
	check(notices[0] > 0, "the paperdoll announces the change")

	# Clicking the worn slot takes it back into the pool.
	doll.slot_rows["main"]["button"].pressed.emit()
	check(str(warband.roster.equipped_of(first)["main"]).is_empty(),
		"clicking a worn slot returns the piece")
	check(warband.stash.pooled_count("sword_short") == 2, "the returned copy is back in the pool")
	check(doll.slot_rows["main"]["button"].text.contains("empty"), "the slot reads empty again")

	# A two-hander displaced by a shield comes back to the pool, nothing is lost.
	doll.slot_rows["main"]["button"].pressed.emit()
	_stash_row(doll, "sword_great")["button"].pressed.emit()
	check(str(warband.roster.equipped_of(first)["main"]) == "sword_great",
		"the greatsword is worn in the main hand")
	doll.slot_rows["off"]["button"].pressed.emit()
	_stash_row(doll, "shield_buckler")["button"].pressed.emit()
	check(str(warband.roster.equipped_of(first)["off"]) == "shield_buckler",
		"the shield goes into the off hand")
	check(str(warband.roster.equipped_of(first)["main"]).is_empty(),
		"the shield displaces the two-hander")
	check(warband.stash.pooled_count("sword_great") == 1, "the greatsword returns to the pool")
	check(warband.total_value() == baseline, "no gold is lost moving gear, %d vs %d"
		% [warband.total_value(), baseline])

	# The list is value-ordered and holds unequipped pieces only: the shield the
	# first mercenary wears is on his off-hand slot, not in the stash.
	var values: Array[int] = []
	for shown in doll.stash_rows:
		values.append(int(shown["value"]))
	var ordered := true
	for index in range(1, values.size()):
		if values[index] > values[index - 1]:
			ordered = false
	check(ordered, "the stash list is value-ordered, got %s" % str(values))
	var reference: Array[Dictionary] = []
	for owned in warband.stash.rows(warband.roster, warband.cruor.brands):
		if int(owned["pooled"]) > 0:
			reference.append(owned)
	check(doll.stash_rows.size() == reference.size(),
		"the panel shows every stash row with a free copy, got %d of %d"
		% [doll.stash_rows.size(), reference.size()])
	for index in reference.size():
		check(str(doll.stash_rows[index]["item_id"]) == str(reference[index]["item_id"]),
			"row %d matches the stash's own order" % index)
	check(_stash_row(doll, "shield_buckler").is_empty(), "the worn shield is not on the list")

	doll.picker_buttons[other].pressed.emit()
	check(doll.selected_merc == other, "the picker strip switches mercenary")
	check(_stash_row(doll, "shield_buckler").is_empty(),
		"another body's worn piece is not offered either")
	check(doll.slot_rows["off"]["button"].text.contains("empty"),
		"the newly picked mercenary shows their own bare slots")
	# Handing a piece over is two clicks through the pool: off the wearer's slot,
	# then from the stash onto the new body.
	doll.picker_buttons[first].pressed.emit()
	doll.slot_rows["off"]["button"].pressed.emit()
	check(not _stash_row(doll, "shield_buckler").is_empty(),
		"a piece taken off comes back onto the list")
	doll.picker_buttons[other].pressed.emit()
	_stash_row(doll, "shield_buckler")["button"].pressed.emit()
	check(str(warband.roster.equipped_of(other).get("off", "")) == "shield_buckler",
		"the freed shield dresses the other mercenary")
	check(_stash_row(doll, "shield_buckler").is_empty(),
		"and its last free copy leaves the list")

	# A brand on a worn piece is printed under its slot.
	doll.picker_buttons[first].pressed.emit()
	doll.slot_rows["main"]["button"].pressed.emit()
	_stash_row(doll, "sword_short")["button"].pressed.emit()
	check(str(warband.roster.equipped_of(first)["main"]) == "sword_short",
		"the shortsword is worn again in the main hand")
	warband.cruor.add(Contracts.CruorTier.T1_RITUAL_TALLOW, 5)
	var branded: Dictionary = warband.cruor.brand("sword_short", Contracts.CruorTier.T1_RITUAL_TALLOW)
	check(bool(branded.get("ok", false)),
		"the shortsword can be branded: %s" % str(branded.get("message", "")))
	var brand_line := str(warband.cruor.brand_line("sword_short"))
	check(not brand_line.is_empty(), "the brand has a line")
	doll.picker_buttons[first].pressed.emit()
	check(doll.slot_rows["main"]["button"].text.contains(brand_line),
		"the worn slot prints the brand line, got %s" % doll.slot_rows["main"]["button"].text)
	# The panel's SWAP SET runs the same two-set swap `TAB` does: the line under the
	# ranger names the set in the hands, and a press puts the other pair on the body.
	check(doll._set_label.text.contains("SET 1 OF 2"),
		"the stage names the set the hands carry, got %s" % doll._set_label.text)
	check(doll._set_button.text.contains("SET 2"), "the button offers the other set")
	doll._set_button.pressed.emit()
	check(warband.roster.active_weapon_set(first) == 1,
		"the panel's swap takes the body to Set 2")
	check(str(warband.roster.equipped_of(first)["main"]).is_empty(),
		"Set 2 was empty, so the hands are")
	check(doll._set_label.text.contains("SET 2 OF 2"),
		"and the stage says so, got %s" % doll._set_label.text)
	check(doll.slot_rows["main"]["button"].text.contains("empty"),
		"the worn main slot reads empty in Set 2")
	doll._set_button.pressed.emit()
	check(warband.roster.active_weapon_set(first) == 0, "a second press comes back to Set 1")
	check(str(warband.roster.equipped_of(first)["main"]) == "sword_short",
		"and Set 1's shortsword is in the hands again")

	# The player's override: a right-click holds a piece back from the band's
	# automatic arming, and a left click still wears it by hand. A held row says
	# so, and the same right-click releases it again.
	doll.picker_buttons[other].pressed.emit()
	var free_sword := _stash_row(doll, "sword_short")
	check(not free_sword.is_empty(), "the free shortsword is on the stash list")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	free_sword["button"].gui_input.emit(right_click)
	check(warband.is_auto_equip_restricted("sword_short"),
		"a right-click holds the piece back from auto-equip")
	check(_stash_row(doll, "sword_short")["button"].text.contains("HELD"),
		"the held row says HELD")
	check(doll.status_text().contains("restricted"), "and the screen says what happened")
	_stash_row(doll, "sword_short")["button"].pressed.emit()
	check(str(warband.roster.equipped_of(other).get("main", "")) == "sword_short",
		"a held piece can still be worn by the player's hand")
	check(warband.roster.is_manual(other, "main"),
		"and the slot a hand filled is marked as the player's")
	# The body's own RE-EQUIP is the press that hands that choice back: it clears
	# the pins and lets the band pick for the body again.
	doll._reequip_button.pressed.emit()
	check(not warband.roster.is_manual(other, "main"),
		"RE-EQUIP clears the hand-set slot, got %s" % str(warband.roster.manual_slots(other)))
	doll.close()
	check(not doll.is_open(), "close() closes the paperdoll")

# --- the bench -------------------------------------------------------------

## The gear page's own anoint bench: the altar's rack without the altar. What this
## owns is that the door is the page's, that a weld lands on **the copy in the
## hand** and on no other copy of the same kind, that the price is the altar's
## price (so the bench is a shortcut and never a subsidy), and that a refusal is
## said out loud instead of swallowed. No `SacrificialAltar` exists in this tree:
## if the bench needed one, nothing here would land.
func _check_bench() -> void:
	warband.reset_state()
	_set_gold(500)
	var body: int = warband.add_mercenary("Wren")
	# Two shortswords: one goes in the hand, one stays in the pool. The mark must
	# follow the serial the hand claimed, which is the difference between "the
	# warband owns a worked shortsword" and "the shortsword this body carries".
	warband.stash.add("sword_short", 2)
	warband.stash.add(Cruor.BASIC_REAGENT, 4)
	warband.cruor.add(Contracts.CruorTier.T1_RITUAL_TALLOW, 12)
	warband.cruor.add(Contracts.CruorTier.T2_BLACK_BILE, 6)
	var doll = DollScript.new()
	doll.configure(warband)
	root.add_child(doll)
	doll.open(body)
	check(not doll.bench_is_open(), "the bench starts shut")

	doll.slot_rows["main"]["button"].pressed.emit()
	var sword_row := _stash_row(doll, "sword_short")
	check(not sword_row.is_empty(), "the shortsword waits in the stash")
	sword_row["button"].pressed.emit()
	check(str(warband.roster.equipped_of(body)["main"]) == "sword_short",
		"the body wears a shortsword")
	var worn_copy: int = doll.bench_ordinal()
	check(warband.stash.pooled_count("sword_short") == 1,
		"one shortsword left the pool to be worn, %d stay"
			% warband.stash.pooled_count("sword_short"))

	check(doll.open_bench("main"), "the bench opens on the main hand")
	check(doll.bench_is_open() and doll.bench_slot() == "main",
		"and reads back which hand it is working")
	check(doll.bench_item() == "sword_short", "the piece laid in it is the worn one")
	check(doll.bench_ordinal() == worn_copy,
		"and the serial is the copy the hand claimed (%d vs %d)"
			% [doll.bench_ordinal(), worn_copy])
	var rows: Array = doll.bench_rows()
	check(rows.size() > 2, "the bench shows the rack the steel can take (%d rows)"
		% rows.size())
	var priced := true
	for option in rows:
		if int((option as Dictionary).get("cost_count", 0)) <= 0 \
				or str((option as Dictionary).get("cost_name", "")).is_empty():
			priced = false
	check(priced, "every row on it names a price")

	var cheapest: Dictionary = {}
	for option in rows:
		var row: Dictionary = option
		if not str(row.get("reason", "")).is_empty():
			continue
		if cheapest.is_empty() \
				or int(row["cost_count"]) < int(cheapest["cost_count"]):
			cheapest = row
	check(not cheapest.is_empty(), "some weld in the rack is affordable")
	var pick := str(cheapest.get("entry_id", ""))
	var tier := int(cheapest.get("cost_tier", 0))
	var count := int(cheapest.get("cost_count", 0))
	var tier_before: int = warband.cruor.tier_count(tier)
	var ichor_before: int = warband.stash.pooled_count(Cruor.BASIC_REAGENT)

	var laid: Dictionary = doll.press_weld(pick)
	check(bool(laid.get("ok", false)), "the page lays the weld: %s"
		% str(laid.get("message", "")))
	check(warband.annoints.has("sword_short", worn_copy, pick),
		"the mark is welded to the copy the hand is holding")
	check(warband.annoints.count("sword_short", worn_copy) == 1,
		"one annointment on it")
	var spare_marks := 0
	for serial in warband.stash.serials_of("sword_short"):
		spare_marks += int(warband.annoints.count("sword_short", int(serial)))
	check(spare_marks == 0, "the spare shortsword stays plain (%d marks)" % spare_marks)
	check(warband.cruor.tier_count(tier) == tier_before - count,
		"the price came out of the cruor (%d -> %d)"
			% [tier_before, warband.cruor.tier_count(tier)])
	check(warband.stash.pooled_count(Cruor.BASIC_REAGENT) == ichor_before - 1,
		"and one vial of ichor with it")
	check(doll.bench_status_text().contains("Shortsword"),
		"the bench says what it did: %s" % doll.bench_status_text())
	check(doll.slot_rows["main"]["button"].text.contains("Welded"),
		"the worn slot reads as worked, got %s"
			% doll.slot_rows["main"]["button"].text.replace("\n", " | "))

	# The same row again: the piece already carries it, the press is refused, and
	# a refusal costs nothing.
	var again: Dictionary = doll.press_weld(pick)
	check(not bool(again.get("ok", false)), "the same weld is refused twice")
	check(warband.cruor.tier_count(tier) == tier_before - count,
		"and the refusal spends no cruor")
	var repainted := false
	for option in doll.bench_rows():
		var row: Dictionary = option
		if str(row.get("entry_id", "")) == pick:
			repainted = str(row.get("reason", "")).contains("already carries")
	check(repainted, "the rack now says the piece already carries it")

	# A dry wallet: every row reads why it cannot be laid, and pressing one says so
	# under the rack instead of spending nothing and saying nothing.
	warband.cruor.spend(Contracts.CruorTier.T1_RITUAL_TALLOW,
		warband.cruor.tier_count(Contracts.CruorTier.T1_RITUAL_TALLOW))
	warband.cruor.spend(Contracts.CruorTier.T2_BLACK_BILE,
		warband.cruor.tier_count(Contracts.CruorTier.T2_BLACK_BILE))
	warband.stash.remove(Cruor.BASIC_REAGENT, warband.stash.pooled_count(Cruor.BASIC_REAGENT))
	doll.refresh()
	var dry: Array = doll.bench_rows()
	var refused := not dry.is_empty()
	for option in dry:
		if str((option as Dictionary).get("reason", "")).is_empty():
			refused = false
	check(refused, "with a dry wallet every row says why it cannot be laid")
	if not dry.is_empty():
		var dry_press: Dictionary = doll.press_weld(str((dry[0] as Dictionary)["entry_id"]))
		check(not bool(dry_press.get("ok", false))
				and doll.bench_status_text().contains("does not have"),
			"and a press on one is refused in its own words: %s"
				% doll.bench_status_text())

	# A bare hand has nothing to work: no rack, and a press on it is refused.
	check(doll.open_bench("off"), "the bench opens on the off hand too")
	check(doll.bench_slot() == "off", "and the tabs move the work to it")
	check(doll.bench_rows().is_empty(), "a bare hand offers no rack")
	var bare: Dictionary = doll.press_weld(pick)
	check(not bool(bare.get("ok", false)), "and a press on it is refused")

	doll.close_bench()
	check(not doll.bench_is_open(), "the bench shuts on DONE")
	check(doll.open_bench("main"), "and opens again on a hand")
	doll.open_bench("head")
	check(doll.bench_slot() == "main", "a slot that is not a hand leaves the work where it was")
	doll.close()
	check(not doll.is_open() and not doll.bench_is_open(),
		"closing the page shuts the bench with it")

	# The page is a body's page: with the roster empty there is nobody to work for,
	# and the bench refuses rather than drawing a rack against no steel.
	warband.reset_state()
	doll.refresh()
	check(not doll.open_bench("main"), "a page with no body refuses to open the bench")
	doll.queue_free()

# --- the strip of bodies ---------------------------------------------------

## The strip over the page carries one chip per dressable body, and eight of them
## in one row measured 1488 px against the page's 1112: the page grew past the
## frame and `RE-EQUIP THE BAND` was drawn outside the window. The check is the
## frame's own page - where the frame puts its content, not where the content
## asked to be - on a real layout pass: nothing the strip draws may reach past it,
## and the whole column must still fit the page's height. A roster past the
## eight-body cap (a rescue leaves names in the reserve) keeps the two rows and
## scrolls instead of growing.
func _check_strip() -> void:
	warband.reset_state()
	_set_gold(1000)
	var names := ["Aldous", "Kestrel", "Bartholomew", "Wren", "Sable",
		"Ulric", "Ysolde", "Fenwick"]
	for index in names.size():
		var merc_id: int = warband.add_mercenary(names[index])
		if index % 3 == 1:
			warband.roster.apply_damage(merc_id, 100.0)
	var doll = DollScript.new()
	root.add_child(doll)
	doll.configure(warband)
	doll.open(-1)
	# Four frames: the panel, the frame's page and then the strip's own sort.
	for _pass in 4:
		await process_frame
	var frame: Control = doll.get_node("WarbandPaperdoll/Frame")
	var page := _page_rect(frame)
	check(doll.picker_buttons.size() == 8, "eight sworn bodies make eight chips, got %d"
		% doll.picker_buttons.size())
	check(doll._picker_box.columns * 2 >= doll.picker_buttons.size(),
		"two rows hold the cap of eight")
	var needed: Vector2 = frame.body.get_combined_minimum_size()
	check(needed.x <= page.size.x, "the page holds the strip: %s of %s"
		% [str(needed), str(page.size)])
	check(needed.y <= page.size.y, "and the stacked screen still fits: %s of %s"
		% [str(needed), str(page.size)])
	check(frame.body.size.x <= page.size.x, "the page is not widened by its own content")
	for merc_id in doll.picker_buttons.keys():
		var chip: Control = doll.picker_buttons[merc_id]
		check(page.encloses(chip.get_global_rect()),
			"chip %s sits inside the page, at %s"
			% [str((chip as Button).text), str(chip.get_global_rect())])
	check(page.encloses(doll._reequip_all_button.get_global_rect()),
		"RE-EQUIP THE BAND stays on the page, at %s"
		% str(doll._reequip_all_button.get_global_rect()))
	check(page.encloses(doll._hotbar_box.get_global_rect()), "and so does the hotbar")
	var strip: ScrollContainer = doll._picker_scroll
	check(not strip.get_v_scroll_bar().visible, "eight bodies need no strip scrollbar")
	var strip_height := strip.size.y
	for index in 4:
		warband.add_mercenary("Reserve %d" % (index + 1))
	for _pass in 3:
		await process_frame
	page = _page_rect(frame)
	needed = frame.body.get_combined_minimum_size()
	check(doll.picker_buttons.size() == 12, "a rescue's names join the strip, got %d"
		% doll.picker_buttons.size())
	check(needed.x <= page.size.x and needed.y <= page.size.y,
		"the page still holds a roster past the cap: %s of %s" % [str(needed), str(page.size)])
	check(frame.body.size.x <= page.size.x, "and its content still does not widen it")
	check(is_equal_approx(strip.size.y, strip_height),
		"the strip keeps its two rows (%s -> %s)" % [str(strip_height), str(strip.size.y)])
	check(strip.get_v_scroll_bar().visible, "the names below the fold are scrolled to")
	doll.close()
	doll.queue_free()
	await process_frame

## The page the frame hands its content: the frame's own rect less the inset and
## padding it reserves for the clamp, the title rail and the page's torn edge.
## Read from the frame, never from the body - a body that grew to fit an
## overflowing strip would otherwise measure itself and pass.
func _page_rect(frame: Control) -> Rect2:
	var rect := frame.get_global_rect()
	var inset := LedgerFrameScript.PAGE_INSET + LedgerFrameScript.BODY_PAD_X
	var top := rect.position.y + LedgerFrameScript.PAGE_INSET \
		+ LedgerFrameScript.HEADER + LedgerFrameScript.BODY_PAD_TOP
	var bottom := rect.end.y - LedgerFrameScript.PAGE_INSET \
		- LedgerFrameScript.BODY_PAD_BOTTOM
	return Rect2(rect.position.x + inset, top,
		rect.size.x - 2.0 * inset, bottom - top)

# --- item hover details ----------------------------------------------------

## The hover card is the only place a row says what a piece actually is: the
## paperdoll's rows carry a click instruction, so a card that slipped back to a
## sentence would leave the stash with no item details at all. Every check reads
## its expectation from the catalogue or the table that owns the number.
func _check_item_hover() -> void:
	warband.reset_state()
	_set_gold(1000)
	var first: int = warband.add_mercenary("Aldous")
	warband.stash.add("sword_short", 1)
	warband.stash.add("armor_leather_chest", 1)
	warband.stash.add("ring_melee", 1)
	var doll = DollScript.new()
	doll.configure(warband)
	root.add_child(doll)
	doll.open(first)

	# A weapon: name, kind, the catalogue's damage/speed/reach line and its worth.
	var sword_row := _stash_row(doll, "sword_short")
	check(not sword_row.is_empty(), "the shortsword is on the stash list")
	check(sword_row["button"].tooltip_text == "Shortsword",
		"the row's tooltip is the piece the card describes")
	check(sword_row["button"].call("_make_custom_tooltip",
		sword_row["button"].tooltip_text) != null,
		"the row answers Godot's tooltip callback with the card")
	var sword_card = sword_row["button"].make_card()
	check(sword_card != null, "hovering a stash row builds an item card")
	var sword_text := _card_text(sword_card)
	check(sword_text.contains("Shortsword"), "the card names the piece")
	check(sword_text.contains("ONE-HAND"), "the card carries the type line, got %s" % sword_text)
	check(sword_text.contains(str(State.ITEMS["sword_short"]["detail"])),
		"the card carries the catalogue's detail text")
	check(sword_text.contains("WORTH"), "the card prices the piece")

	# Armor: the guard the set actually grants, not a word about clicking.
	var armor_card = _stash_row(doll, "armor_leather_chest")["button"].make_card()
	check(armor_card != null, "hovering armor builds a card")
	var armor_text := _card_text(armor_card)
	var guard := int(round(ArmorData.reduction_for(
		ArmorData.set_of_item("armor_leather_chest"), "chest") * 100.0))
	check(armor_text.contains("BODY GUARD"),
		"the card names the guard channel, got %s" % armor_text)
	check(armor_text.contains("+%d%%" % guard),
		"the card prints the set's real guard (%d%%)" % guard)

	# A ring: the modifier rows come from the table combat reads.
	var ring_card = _stash_row(doll, "ring_melee")["button"].make_card()
	check(ring_card != null, "hovering a ring builds a card")
	var ring_text := _card_text(ring_card)
	var ring_row: Dictionary = TrinketStats.effect_rows("ring_melee")[0]
	check(ring_text.contains(str(ring_row["label"])),
		"the card names the ring's modifier, got %s" % ring_text)
	check(ring_text.contains(str(ring_row["value"])),
		"the card prints the ring's real value, got %s" % ring_text)

	# A worn slot describes what it holds; an empty one has nothing to describe.
	warband.equip_merc(first, "main", "sword_short")
	var worn_card = doll.slot_rows["main"]["button"].make_card()
	check(worn_card != null, "hovering a worn slot builds a card")
	check(_card_text(worn_card).contains(str(State.ITEMS["sword_short"]["detail"])),
		"the worn slot's card carries the piece's details")
	warband.unequip_merc(first, "main")
	check(doll.slot_rows["main"]["button"].make_card() == null,
		"an empty slot builds no card")
	doll.close()

## Every Label under the card, which is how a card says anything at all.
func _card_text(node: Node) -> String:
	var parts := PackedStringArray()
	_collect_card_text(node, parts)
	return "\n".join(parts)


func _collect_card_text(node: Node, parts: PackedStringArray) -> void:
	if node is Label:
		parts.append((node as Label).text)
	for child in node.get_children():
		_collect_card_text(child, parts)

# --- the two re-kits -------------------------------------------------------

## The stage's two buttons: this body's kit goes back and comes out again by the
## band's own priorities, and the band button rebuilds the whole roster out of
## one pool, oldest name first. Both read their answer off `Warband`.
func _check_reequip_buttons() -> void:
	warband.reset_state()
	_set_gold(1000)
	var first: int = warband.add_mercenary("Aldous")
	var second: int = warband.add_mercenary("Brine")
	warband.roster.equip(first, "main", "sword_short")
	warband.stash.add("sword_great", 1)
	var doll = DollScript.new()
	doll.configure(warband)
	root.add_child(doll)
	doll.open(first)
	check(doll._reequip_button.text.contains("ALDOUS"),
		"the re-kit button names the body on the stage, got %s" % doll._reequip_button.text)
	check(not doll._reequip_button.disabled, "and it is live for a body the screen may dress")
	doll._reequip_button.pressed.emit()
	check(str(warband.roster.equipped_of(first).get("main", "")) == "sword_great",
		"the button hands the shortsword back and takes the pool's better blade, got %s"
		% str(warband.roster.equipped_of(first).get("main", "")))
	check(doll.status_text().contains("re-equips"),
		"and the screen reports the fitting, got %s" % doll.status_text())
	check(doll.slot_rows["main"]["button"].text.contains("Greatsword"),
		"the worn slot repaints, got %s" % doll.slot_rows["main"]["button"].text)
	check(warband.stash.pooled_count("sword_short") == 1, "and the old blade is a stash row")

	# The band button dresses the whole roster out of that one pool.
	warband.stash.add("sword_short", 1)
	doll._reequip_all_button.pressed.emit()
	check(str(warband.roster.equipped_of(first).get("main", "")) == "sword_great",
		"the band pass dresses the oldest name with the pick of the pool")
	check(str(warband.roster.equipped_of(second).get("main", "")) == "sword_short",
		"and the next body with what is left")
	check(doll.status_text().contains("The band re-equips"),
		"and the screen says what the pass did, got %s" % doll.status_text())
	check(doll.picker_buttons.size() == 2, "the picker still has one button per body")
	doll.close()

# --- the recruiter ---------------------------------------------------------

func _check_recruiter() -> void:
	warband.reset_state()
	_set_gold(1000)
	warband.add_mercenary("Aldous")
	var screen = ScreenScript.new()
	screen.configure(warband)
	root.add_child(screen)
	screen.open()
	check(screen.hire_names.size() == 3, "the board offers three names")
	check(screen.hire_names.has("Aldous") == false, "the board skips names already sworn")
	var cost: int = warband.hire_cost()
	check(cost == 0, "the recruiter's first eight oaths are free, got %d" % cost)
	check(screen.hire_buttons[0].text.contains("FREE"), "the HIRE button says the oath is free")

	var gold_before: int = warband.gold()
	screen.hire_buttons[0].pressed.emit()
	check(warband.roster.count() == 2, "HIRE swears a body in")
	check(warband.gold() == gold_before - cost, "a free HIRE takes no gold")
	check(screen.rows.size() == 2, "the roster repaints immediately")
	check(screen.gold_label.text == "%d G" % warband.gold(), "the purse repaints immediately")

	# An empty purse still swears a body: gold is only asked for past the eighth.
	_set_gold(0)
	var broke: int = warband.roster.count()
	screen.hire_buttons[0].pressed.emit()
	check(warband.roster.count() == broke + 1, "a free oath needs no gold")
	check(warband.gold() == 0, "and leaves the empty purse alone")
	_set_gold(1000)

	while warband.roster.count() < warband.deployment_cap:
		warband.add_mercenary("")
	var sworn: int = warband.roster.count()
	var gold_at_cap: int = warband.gold()
	screen.hire_buttons[0].pressed.emit()
	check(warband.roster.count() == sworn, "the cap refuses the hire")
	check(warband.gold() == gold_at_cap, "a refused hire spends nothing")
	check(screen.status_text().contains("No more can be sworn"),
		"the refusal is reported, got %s" % screen.status_text())
	check(screen.rows.size() == sworn, "the roster is unchanged at the cap")

	# A dead mercenary no longer holds a place: the same cap can be filled again.
	var fallen: int = warband.roster.ids()[0]
	warband.roster.apply_damage(fallen, 1000.0)
	check(not warband.roster.has(fallen), "the fallen leave the books at the cap")
	check(warband.roster.count() == sworn - 1, "and free a place in the warband")
	_set_gold(10000)
	var freed: int = warband.roster.count()
	screen.hire_buttons[0].pressed.emit()
	check(warband.roster.count() == freed + 1, "the freed place can be sworn again")
	check(not screen.status_text().contains("No more can be sworn"),
		"the recruiter no longer refuses, got %s" % screen.status_text())
	screen.close()
