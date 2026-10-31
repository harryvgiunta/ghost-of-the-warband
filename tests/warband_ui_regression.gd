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
	check(doll.picker_buttons.size() == 2, "the picker strip has one button per mercenary")
	check(doll.stash_rows.size() == 3, "the stash lists every owned piece, got %d"
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

	# The list is value-ordered and tags a piece another mercenary is wearing.
	var values: Array[int] = []
	for shown in doll.stash_rows:
		values.append(int(shown["value"]))
	var ordered := true
	for index in range(1, values.size()):
		if values[index] > values[index - 1]:
			ordered = false
	check(ordered, "the stash list is value-ordered, got %s" % str(values))
	var reference: Array[Dictionary] = warband.stash.rows(warband.roster, warband.cruor.brands)
	check(doll.stash_rows.size() == reference.size(), "the panel shows every stash row")
	for index in reference.size():
		check(str(doll.stash_rows[index]["item_id"]) == str(reference[index]["item_id"]),
			"row %d matches the stash's own order" % index)

	doll.picker_buttons[other].pressed.emit()
	check(doll.selected_merc == other, "the picker strip switches mercenary")
	var tagged := _stash_row(doll, "shield_buckler")
	check(not tagged.is_empty(), "the worn shield is still on the list")
	check(int(tagged["pooled"]) == 0, "a worn piece has no free copy")
	# The stash is one pool, so a piece another body wears is a hand-off, not a
	# locked row: clicking it takes it off that body and puts it on this one.
	check(not tagged["button"].disabled, "a worn piece can be handed over from the list")
	tagged["button"].pressed.emit()
	check(str(warband.roster.equipped_of(other).get("off", "")) == "shield_buckler",
		"clicking the worn row dresses the selected mercenary")
	check(str(warband.roster.equipped_of(first).get("off", "")) == "",
		"and takes it off the mercenary who wore it")
	check(warband.stash.pooled_count("shield_buckler") == 0,
		"a hand-off leaves no copy in the pool")
	# Hand it straight back so the rest of the checks start where they expected.
	doll.picker_buttons[first].pressed.emit()
	doll._on_stash_pressed("shield_buckler")
	check(str(warband.roster.equipped_of(first).get("off", "")) == "shield_buckler",
		"and the piece can be handed straight back")
	doll.picker_buttons[other].pressed.emit()
	var tag_lines: Array = tagged["tags"]
	check(tag_lines.size() == 1, "the worn piece carries one tag, got %s" % str(tag_lines))
	check(str(tag_lines[0]).contains("Equipped") and str(tag_lines[0]).contains("Aldous"),
		"the tag names the Equipped wearer, got %s" % str(tag_lines))
	check(doll.slot_rows["off"]["button"].text.contains("empty"),
		"the newly picked mercenary shows their own bare slots")

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
	doll.close()
	check(not doll.is_open(), "close() closes the paperdoll")

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
