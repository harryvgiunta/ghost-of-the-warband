extends SceneTree
## Sacrificial Altar regression: the reagent rite wakes a weapon into its skill
## and the body holding it carries that skill at once; the essence rites render
## exactly the spare magic gear, spend what they say they spend, and refuse out
## loud when the wallet is empty.
##
## Everything is driven through the real `AltarMenu` nodes - the row buttons emit
## their own `pressed` - against the real `Warband` autoload, so the numbers the
## test reads are the numbers the ledger and the panel agree on.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Catalog = preload("res://scripts/warband/cruor_catalog.gd")
const Branded = preload("res://scripts/warband/branded_skills.gd")
const State = preload("res://scripts/player_state.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const AnnointCatalog = preload("res://scripts/warband/annoint_catalog.gd")
const AltarMenuScript = preload("res://scripts/warband/altar_menu.gd")
const ItemCard = preload("res://scripts/warband/item_card.gd")
const SacrificialAltarScript = preload("res://scripts/warband/sacrificial_altar.gd")
const ControllerScript = preload("res://scripts/warband/possession_controller.gd")

const TEST_SAVE := "user://altar_regression_state.json"
const T1: int = Contracts.CruorTier.T1_RITUAL_TALLOW
const T2: int = Contracts.CruorTier.T2_BLACK_BILE
const T3: int = Contracts.CruorTier.T3_COAGULATED_CRUOR
const T4: int = Contracts.CruorTier.T4_STIGMATIC_RESIN
const T5: int = Contracts.CruorTier.T5_CRYSTALLIZED_SIN

var checks := 0
var failures := 0
var state = null
var warband = null
var menu = null
var altar_opens: Array[int] = []
var changed_hits := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("ALTAR_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

func run() -> void:
	_remove_test_save()
	state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = TEST_SAVE
	warband.reset_state()

	menu = AltarMenuScript.new()
	menu.name = "AltarMenuUnderTest"
	root.add_child(menu)
	menu.configure(warband)
	menu.changed.connect(_on_menu_changed)

	check_recipes()
	await check_anoint()
	check_bench()
	check_rack()
	check_unbind_list()
	check_unbind_press()
	check_distill()
	check_brand()
	check_shortfall()
	check_open_close()
	check_altar()

	_remove_test_save()
	print("ALTAR_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

# --- helpers ---------------------------------------------------------------

func _fresh(merc_name: String = "") -> int:
	warband.reset_state()
	return warband.add_mercenary(merc_name) if not merc_name.is_empty() else -1

func _unbind_row(item_id: String) -> Dictionary:
	for row in menu.unbind_rows():
		if str(row["item_id"]) == item_id:
			return row
	return {}

func _distill_row(tier: int) -> Dictionary:
	for row in menu.distill_rows():
		if int(row["tier"]) == tier:
			return row
	return {}

func _brand_row(item_id: String) -> Dictionary:
	for row in menu.brand_rows():
		if str(row["item_id"]) == item_id:
			return row
	return {}

func _header_row(tier: int) -> Dictionary:
	for row in menu.tier_rows():
		if int(row["tier"]) == tier:
			return row
	return {}

func _anoint_row(item_id: String) -> Dictionary:
	for row in menu.anoint_rows():
		if str(row["item_id"]) == item_id:
			return row
	return {}

func _rack_row(item_id: String, ordinal: int) -> Dictionary:
	for row in menu.anoint_rows():
		if str(row["item_id"]) == item_id and int(row["ordinal"]) == ordinal:
			return row
	return {}

func _menu_count(scan: Node) -> int:
	var total := 0
	for child in scan.get_children():
		if child.get_script() == AltarMenuScript:
			total += 1
		total += _menu_count(child)
	return total

func _on_altar_opened(peer_id: int) -> void:
	altar_opens.append(peer_id)

func _on_menu_changed() -> void:
	changed_hits += 1

# --- the reagent rite ------------------------------------------------------

## Every weapon and shield in the catalog, forged or salvage, wakes into a skill,
## and every such skill has a rite made of catalog reagents. A skill with no rite
## would leave its weapon plain for good.
func check_recipes() -> void:
	for item_id in State.ITEMS:
		var item: Dictionary = State.ITEMS[item_id]
		var wielded := str(item.get("category", "")) in ["1h", "2h", "bow", "staff", "shield"] \
			and str(item.get("kind", "")) in ["sword", "dagger", "bow", "staff", "shield"]
		var skill: Dictionary = WarbandCruor.anoint_skill(str(item_id))
		check(wielded == not skill.is_empty(),
			"%s wakes at the altar exactly when it is held steel (%s)" % [item_id, str(skill.get("id", ""))])
		if skill.is_empty():
			continue
		var recipe: Dictionary = WarbandCruor.anoint_recipe(str(skill.get("id", "")))
		check(not recipe.is_empty(), "%s's skill %s has a rite" % [item_id, str(skill.get("id", ""))])
		for reagent in recipe:
			check(bool(State.ITEMS.get(str(reagent), {}).get("reagent", false)) and int(recipe[reagent]) >= 1,
				"%s's rite asks for a catalog reagent, got %s x%s" % [item_id, str(reagent), str(recipe[reagent])])

## The rite on the real panel and the real roster: a worn bow and a pooled sword
## are both offered, one press spends exactly the recipe and wakes the bow, the
## body the controller dressed carries the skill without being dressed by hand, a
## short stash refuses out loud, a woken piece is never woken twice, and the
## ledger rides the save.
func check_anoint() -> void:
	warband.reset_state()
	var stash = warband.stash
	var reagent := WarbandCruor.BASIC_REAGENT
	var merc: int = warband.add_mercenary("Wick", {"main": "bow_short"})
	stash.add("sword_short", 1)
	stash.add("ring_silver", 1)
	stash.add(reagent, 1)
	check(warband.quests.offer("bind_the_ichor") and bool(warband.quests.accept("bind_the_ichor").get("ok", false)),
		"the ichor order is on the ledger")

	# A body dressed off the roster, the way every scene fields one.
	var field := Node3D.new()
	field.name = "AnointField"
	root.add_child(field)
	var bodies_root := Node3D.new()
	bodies_root.name = "Bodies"
	field.add_child(bodies_root)
	var camera := Camera3D.new()
	field.add_child(camera)
	var controller = ControllerScript.new()
	controller.name = "Soul"
	controller.auto_simulate = false
	field.add_child(controller)
	controller.setup(warband, camera, bodies_root)
	var posts: Array[Vector3] = [Vector3.ZERO]
	controller.spawn_mercenaries(posts, true)
	await physics_frame
	var body = controller.body_of(merc)
	check(body != null, "the archer is fielded")
	if body == null:
		field.queue_free()
		return
	check(str(body.rig.weapon) == "bow", "the body holds the stock bow")
	check(body.ability.definition(0).is_empty(), "a stock bow carries no skill")

	menu.open()
	check(menu.page() == AltarMenuScript.PAGE_ANOINT, "the altar opens on the reagent rite")
	var bow := _anoint_row("bow_short")
	var sword := _anoint_row("sword_short")
	check(not bow.is_empty(), "a worn bow is offered")
	check(not sword.is_empty(), "a pooled sword is offered")
	check(_anoint_row("ring_silver").is_empty(), "a ring has no pool and is not offered")
	check(int(bow.get("count", -1)) == warband.annoints.count("bow_short", 0),
		"the card counts the welds on its own copy")
	check(bow.get("button") != null, "a plain piece carries a button")

	# The die is forced for the test: same ritual, same code, a known band.
	var result: Dictionary = warband.anoint("bow_short", -1, _seed_in_band(0, 24))
	check(bool(result.get("ok", false)), "the rite commits: %s" % str(result.get("message", "")))
	check(int(result.get("outcome", -1)) == 0, "the forced band added an ability")
	var entry = AnnointCatalog.by_id(str(result.get("entry_id", "")))
	check(entry != null and int(entry.kind) == AnnointCatalog.Kind.ABILITY,
		"the piece took an ability")
	check(warband.annoints.has("bow_short", 0, str(entry.id)), "the copy carries it")
	check(stash.pooled_count(reagent) == 0, "exactly one ichor left the shared stash")
	check(warband.quests.is_complete("bind_the_ichor"), "the ichor order heard about it")
	var skill_id := str(entry.ability)
	check(str(warband.annointment_skills(merc).get("main", "")) == skill_id,
		"the body's main hand wakes the skill")
	check(str(body.ability.definition(0).get("id", "")) == skill_id,
		"the fielded body carries the skill at once, got %s" \
			% str(body.ability.definition(0).get("id", "")))

	# Six annointments fit, so a marked piece is not "done": the second rite is
	# spent, and it can only ever add, strip or swap - never destroy.
	stash.add(reagent, 1)
	var second: Dictionary = warband.anoint("bow_short", -1, _seed_in_band(25, 49))
	check(bool(second.get("ok", false)) or int(second.get("outcome", -1)) == 2,
		"a second rite is allowed")
	check(stash.pooled_count(reagent) == 0, "the second rite spent its ichor")
	var after := _anoint_row("bow_short")
	check(after.get("button") != null, "a piece with room still offers the button")
	check(State.ITEMS.has("bow_short"), "the piece still exists - nothing is destroyed")

	# A piece the warband does not carry is refused, and refuses for free.
	stash.add(reagent, 1)
	var foreign: Dictionary = warband.anoint("bow_long", -1, _seed_in_band(75, 99))
	check(not bool(foreign.get("ok", true)), "a piece the warband does not carry is refused")
	check(stash.pooled_count(reagent) == 1, "that refusal spent nothing")

	# The copy rides the save.
	var saved: Dictionary = warband.to_dict()
	var held: Array = warband.annoints.ids("bow_short", 0)
	warband.reset_state()
	check(warband.annoints.count("bow_short", 0) == 0, "a reset forgets the steel")
	warband.from_dict(saved)
	check(warband.annoints.ids("bow_short", 0) == held, "the annointments survive the save")
	check(not warband.annoints.has("sword_short", 0, str(entry.id)),
		"an untouched piece stays plain")

	# With the stash dry the panel refuses out loud and nothing moves.
	stash.remove(reagent, stash.pooled_count(reagent))
	var before_hits := changed_hits
	(_anoint_row("sword_short")["button"] as Button).pressed.emit()
	check(warband.annoints.count("sword_short", 0) == 0, "an empty stash welds nothing")
	check(changed_hits == before_hits, "a refused rite announces nothing")
	check(menu.doctrine_text().contains(str(State.ITEMS[reagent]["name"])),
		"the bench names the reagent it wants: %s" % menu.doctrine_text())

	menu.close()
	field.queue_free()
	await process_frame

## The bench: the square holds exactly one piece, the chips only lay it there,
## and the one ANOINT button works whatever is laid - it is never a row's verb.
func check_bench() -> void:
	_fresh()
	var stash = warband.stash
	stash.add("sword_arming", 1)
	stash.add("bow_short", 1)
	stash.add("dagger_ironwood", 1)
	stash.add("ichor_vial", 2)
	warband.add_mercenary("Fen")
	menu.refresh()
	check(not menu.selected_anoint_item().is_empty(),
		"the bench lays a piece by itself so it is never empty for nothing")
	check(menu.select_anoint_item("sword_arming"), "a carried sword can be laid")
	check(menu.selected_anoint_item() == "sword_arming", "the square keeps what was laid in it")
	check(not menu.select_anoint_item("bow_long"),
		"a piece the warband does not carry cannot be laid")
	check(menu.selected_anoint_item() == "sword_arming",
		"a refused piece leaves the square alone")

	# The one button works the piece in the square, and the square keeps it. The
	# roll may come back with nothing to take (a vial can be spent for nothing),
	# so the bench must announce the rite exactly when the copy really changed.
	var before: int = stash.pooled_count("ichor_vial")
	var before_ids: Array = warband.annoints.ids("sword_arming", 0)
	var hits := changed_hits
	menu.anoint_button().pressed.emit()
	check(stash.pooled_count("ichor_vial") == before - 1, "the one button spends one vial")
	var after_ids: Array = warband.annoints.ids("sword_arming", 0)
	check((changed_hits == hits + 1) == (after_ids != before_ids),
		"the bench announces the rite exactly when the copy changed")
	check(menu.selected_anoint_item() == "sword_arming", "the worked piece stays in the square")
	check(stash.pooled_count("dagger_ironwood") == 1, "the chips spend nothing by being pressed")

	# Taking the piece off leaves nothing to work, and the button says so by
	# being dead - there is no row left to press by mistake.
	var socket: Button = menu.find_child("AnointSocket", true, false)
	check(socket != null, "the bench has its square")
	socket.pressed.emit()
	check(menu.selected_anoint_item().is_empty(), "pressing the square takes the piece off")
	check(menu.anoint_button().disabled, "with nothing laid the one button is dead")

## The rack: one card per **copy**, not one per catalogue id. Four swords are four
## cards, each printing the annointments welded to that copy; laying a card works
## that copy and leaves its neighbours untouched.
func check_rack() -> void:
	_fresh()
	var stash = warband.stash
	stash.add("sword_arming", 4)
	stash.add("ichor_vial", 12)
	warband.add_mercenary("Ledge")
	warband.anoint("sword_arming", 1, _seed_in_band(0, 24))
	warband.anoint("sword_arming", 3, _seed_in_band(0, 24))
	menu.refresh()

	var rows: Array = menu.anoint_rows()
	check(rows.size() == 4, "four copies are four cards, got %d" % rows.size())
	var ordinals: Array[int] = []
	for row in rows:
		ordinals.append(int(row["ordinal"]))
		check(row.get("button") != null, "every copy is a card of its own")
	ordinals.sort()
	check(ordinals == [0, 1, 2, 3], "the rack addresses every copy: %s" % str(ordinals))
	check(int(_rack_row("sword_arming", 1)["count"]) == 1, "a card counts its own welds")
	check(int(_rack_row("sword_arming", 0)["count"]) == 0, "a bare copy stays bare")
	var welded := str(_rack_row("sword_arming", 1)["welded"])
	var entry = warband.annoints.entries_of("sword_arming", 1)[0]
	check(welded.contains(str(entry.name)),
		"the card names what is welded to it: %s" % welded)
	check(str(_rack_row("sword_arming", 0)["welded"]).is_empty(),
		"a bare copy's card names nothing")
	check(ItemCard.annoint_entries("sword_arming", warband, 1).size()
		== warband.annoints.count("sword_arming", 1),
		"the hover card asks for the copy the row stands for")
	check(ItemCard.annoint_entries("sword_arming", warband, 0).is_empty(),
		"and a bare copy's hover card is bare")

	# Laying a card addresses that copy, and the one ANOINT works only it.
	check(menu.select_anoint_item("sword_arming", 1), "a card is laid by its copy")
	check(menu.selected_anoint_ordinal() == 1, "the square holds the copy, not just the piece")
	var neighbours: Array = [warband.annoints.ids("sword_arming", 0),
		warband.annoints.ids("sword_arming", 2), warband.annoints.ids("sword_arming", 3)]
	menu.anoint_button().pressed.emit()
	check(warband.annoints.ids("sword_arming", 0) == neighbours[0]
		and warband.annoints.ids("sword_arming", 2) == neighbours[1]
		and warband.annoints.ids("sword_arming", 3) == neighbours[2],
		"the rite moved only the copy in the square")
	check(menu.selected_anoint_ordinal() == 1, "the square keeps the copy it worked")
	check(menu.selected_anoint_item() == "sword_arming", "and the piece it belongs to")

	# The rack is the warband's own count: a fifth sword is a fifth card.
	stash.add("sword_great", 1)
	menu.refresh()
	check(menu.anoint_rows().size() == 5, "a copy added behind the panel is a card")

	# The filter: only the copies a body is wearing right now.
	var wielder: int = warband.add_mercenary("Brann")
	check(bool(warband.equip_merc(wielder, "main", "sword_great").get("ok", false)),
		"a body takes a greatsword")
	menu.refresh()
	check(menu.rack_filter() == AltarMenuScript.RACK_ALL, "the rack starts listing every copy")
	var every: int = menu.anoint_rows().size()
	check(menu.set_rack_filter(AltarMenuScript.RACK_WORN), "the rack filters to worn copies")
	var worn_rows: Array = menu.anoint_rows()
	check(worn_rows.size() == 1, "exactly the worn sword is listed, got %d" % worn_rows.size())
	check(not str(worn_rows[0]["worn"]).is_empty(),
		"the listed copy says who wears it: %s" % str(worn_rows[0]["worn"]))
	check(worn_rows.size() < every, "the filter drops the copies nobody wears")
	check(menu.selected_anoint_item() == "sword_great",
		"the square holds a copy the filtered rack shows")
	check(not menu.set_rack_filter("nonsense"), "an unknown filter is refused")
	check(menu.rack_filter() == AltarMenuScript.RACK_WORN, "a refused filter changes nothing")
	check(menu.set_rack_filter(AltarMenuScript.RACK_ALL), "the rack can list everything again")
	check(menu.anoint_rows().size() == every, "and every copy comes back")

## An RNG whose first draw lands in `[lo, hi]`, so a band can be forced without
## reaching into the roll's guts.
func _seed_in_band(lo: int, hi: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var seed := 1
	while seed < 300000:
		rng.seed = seed
		var drawn := rng.randi_range(0, 99)
		if drawn >= lo and drawn <= hi:
			rng.seed = seed
			return rng
		seed += 1
	rng.seed = 1
	return rng

# --- the unbind list -------------------------------------------------------

func check_unbind_list() -> void:
	warband.reset_state()
	var stash = warband.stash
	stash.add("sword_arming", 1)
	stash.add("bow_short", 1)
	stash.add("ring_silver", 1)
	stash.add("dagger_ironwood", 2)
	stash.add("club_makeshift", 1)
	stash.add("shield_buckler", 1)
	var merc: int = warband.add_mercenary("Kettle")
	var worn: Dictionary = warband.equip_merc(merc, "off", "shield_buckler")
	check(bool(worn.get("ok", false)), "the shield is worn, so it leaves the pool")
	check(stash.pooled_count("shield_buckler") == 0, "a worn piece is not pooled")
	state.credits = 4321
	menu.refresh()

	var rows: Array = menu.unbind_rows()
	check(rows.size() == 3, "exactly the three spare magic pieces are offered, got %d" % rows.size())
	var ids: Array[String] = []
	for row in rows:
		ids.append(str(row["item_id"]))
	check(ids == ["sword_arming", "bow_short", "ring_silver"],
		"the list is the magic gear, value-first: %s" % str(ids))
	check(not ids.has("shield_buckler"), "a worn piece is never unbound")
	check(not ids.has("dagger_ironwood") and not ids.has("club_makeshift"),
		"junk below the magic floor is never unbound")

	for row in rows:
		var price := int(row["value"])
		var expected := Catalog.yield_text(Catalog.unbind_yield(price))
		check(str(row["yield_text"]) == expected, "%s previews %s" % [row["name"], expected])
		var button: Button = row["button"]
		check(button.text.contains(expected), "the row prints its yield: %s" % button.text)
		check(button.text.contains(str(price)), "the row prints the item's value")

	# Header: five tier chips in the catalog's colours, plus the purse.
	var tiers: Array = menu.tier_rows()
	check(tiers.size() == 5, "the header shows all five tiers")
	for row in tiers:
		var tier := int(row["tier"])
		var label: Label = row["label"]
		check(label.get_theme_color("font_color") == Catalog.tier_color(tier),
			"%s chip uses the catalog colour" % Catalog.tier_name(tier))
		check(label.text.contains(Catalog.tier_name(tier)),
			"the chip names %s" % Catalog.tier_name(tier))
		check(label.text.contains(str(int(row["count"]))),
			"the chip prints its count: %s" % label.text)
	check(menu.gold_text().contains("4321"), "the header shows the warband purse: %s" % menu.gold_text())

# --- clicking a row --------------------------------------------------------

func check_unbind_press() -> void:
	var row := _unbind_row("sword_arming")
	check(not row.is_empty(), "the arming sword is on the bench")
	var button: Button = row["button"]
	var before_hits := changed_hits
	button.pressed.emit()

	check(changed_hits == before_hits + 1, "the panel announces the change")
	check(warband.stash.pooled_count("sword_arming") == 0, "the copy is destroyed")
	check(warband.cruor.tier_count(T1) == 10, "a 195 c sword renders 10 Ritual Tallow, got %d"
		% warband.cruor.tier_count(T1))
	check(warband.cruor.tier_count(T2) == 1, "and one Black Bile")
	check(warband.cruor.tier_count(T3) == 0, "nothing reaches the third tier")

	var header := _header_row(T1)
	check(int(header["count"]) == 10, "the tier header refreshed to 10")
	check(str(header["label"].text).contains("10"), "the chip text refreshed")
	check(menu.status_text().contains("Unbound"), "the panel reports the render: %s" % menu.status_text())

	var left: Array[String] = []
	for other in menu.unbind_rows():
		left.append(str(other["item_id"]))
	check(not left.has("sword_arming"), "the destroyed piece leaves the list")
	check(left.size() == 2, "the other two spare pieces remain")

# --- distilling ------------------------------------------------------------

func check_distill() -> void:
	_fresh()
	warband.cruor.add(T1, 12)
	menu.refresh()
	var one := _distill_row(T1)
	check(not one.is_empty(), "Tier 1 has a distil row")
	check(str(one["text"]).contains("12 -> 2"), "the row projects 12 -> 2: %s" % str(one["text"]))
	check(not bool(one["batch_button"].disabled), "one batch is affordable")
	one["batch_button"].pressed.emit()
	check(warband.cruor.tier_count(T1) == 7, "one batch leaves 7 Tier 1, got %d"
		% warband.cruor.tier_count(T1))
	check(warband.cruor.tier_count(T2) == 1, "and adds one Tier 2")

	warband.cruor.add(T2, 24)
	menu.refresh()
	var all_row := _distill_row(T2)
	check(str(all_row["text"]).contains("25 -> 5"), "the row projects 25 -> 5: %s" % str(all_row["text"]))
	all_row["all_button"].pressed.emit()
	check(warband.cruor.tier_count(T2) == 0, "distil all empties Tier 2")
	check(warband.cruor.tier_count(T3) == 5, "and banks five Tier 3")

	var top := _distill_row(T5)
	check(bool(top["batch_button"].disabled) and bool(top["all_button"].disabled),
		"the last tier's buttons are disabled")
	check(not str(top["reason"]).is_empty(), "the last tier explains why")
	check(str(top["text"]).contains(str(top["reason"])), "the reason is printed on the row")
	check(str(top["reason"]).contains("last tier"), "the reason names the last tier")

	var thin := _distill_row(T4)
	check(int(thin["count"]) == 0, "Tier 4 is empty")
	check(bool(thin["batch_button"].disabled) and bool(thin["all_button"].disabled),
		"a tier holding nothing cannot distil")

# --- branding --------------------------------------------------------------

func check_brand() -> void:
	var merc := _fresh("Wren")
	var stash = warband.stash
	stash.add("sword_arming", 1)
	stash.add("shield_buckler", 1)
	check(bool(warband.equip_merc(merc, "off", "shield_buckler").get("ok", false)),
		"the shield is worn")
	warband.cruor.add(T3, 4)
	menu.refresh()

	var offered: Array[String] = []
	for row in menu.brand_rows():
		offered.append(str(row["item_id"]))
	check(offered.has("sword_arming"), "a pooled one-hander is a vessel")
	check(not offered.has("shield_buckler"), "a shield is not offered, worn or not")

	check(menu.select_brand_item("sword_arming"), "the arming sword can be selected")
	check(menu.select_brand_tier(T3), "Coagulated Cruor can be selected")
	check(menu.select_brand_item("shield_buckler") == false, "a shield cannot be selected")

	var preview: Dictionary = menu.brand_preview()
	check(str(preview["ability"]) == "rending_strike", "a one-hander brands Rending Strike")
	check(int(preview["cost"]) == 2, "the brand costs two Coagulated Cruor")
	check(str(preview["line"]) == Branded.tier_line("rending_strike", T3),
		"the preview prints the power line: %s" % str(preview["line"]))
	check(bool(preview["ok"]), "the altar is willing")
	check(not bool(preview["branded"]), "the sword is not branded yet")

	menu.brand_button().pressed.emit()
	check(warband.cruor.is_branded("sword_arming"), "the brand is banked")
	check(str(warband.cruor.brand_of("sword_arming")["ability"]) == "rending_strike",
		"Rending Strike is the ability")
	check(warband.cruor.tier_count(T3) == 2, "two Tier 3 were spent")
	check(menu.status_text().contains("Rending Strike"), "the panel prints the line: %s"
		% menu.status_text())
	var row := _brand_row("sword_arming")
	check(bool(row["branded"]), "the vessel row now reads as branded")
	check(str(row["line"]) == warband.cruor.brand_line("sword_arming"), "the row prints its current line")
	check(str(menu.brand_preview()["line"]).contains("Rending Strike"),
		"the preview still names the sigil")

	# Branding the same piece again rerolls it.
	menu.brand_button().pressed.emit()
	check(warband.cruor.tier_count(T3) == 0, "the reroll spent the last two")
	check(int(warband.cruor.brand_of("sword_arming")["rerolls"]) == 1, "the reroll is counted")
	check(menu.status_text().contains("Rebranded"), "the panel reports the reroll: %s"
		% menu.status_text())

# --- an empty wallet -------------------------------------------------------

func check_shortfall() -> void:
	check(warband.cruor.total() == 0, "the wallet is empty after the reroll")
	menu.refresh()
	check(warband.cruor.tier_count(T3) == 0, "no Tier 3 left")
	var preview: Dictionary = menu.brand_preview()
	check(not bool(preview["ok"]), "the preview knows the wallet is short")
	check(str(preview["message"]).contains("needs"), "the preview names the shortfall")
	var before: int = warband.cruor.total()
	var before_hits := changed_hits
	check(not menu.brand_button().disabled, "the button stays pressable so the refusal is visible")
	menu.brand_button().pressed.emit()
	check(menu.status_text().contains("needs"), "the button reports the shortfall: %s"
		% menu.status_text())
	check(warband.cruor.total() == before, "a refused brand spends nothing")
	check(changed_hits == before_hits, "a refused brand announces nothing")
	check(int(warband.cruor.brand_of("sword_arming")["rerolls"]) == 1, "a refused brand does not reroll")

# --- open / close ----------------------------------------------------------

func check_open_close() -> void:
	check(not menu.is_open(), "the panel starts closed")
	check(not menu.visible, "and hidden")
	menu.open()
	check(menu.is_open(), "open() opens it")
	check(menu.visible, "open() shows it")
	menu.close()
	check(not menu.is_open(), "close() closes it")
	check(not menu.visible, "close() hides it")

# --- the altar node --------------------------------------------------------

func check_altar() -> void:
	var altar = SacrificialAltarScript.new()
	altar.name = "Altar"
	root.add_child(altar)
	check(is_equal_approx(altar.interact_range, 3.0), "the kneel radius is 3 m")

	var meshes := 0
	var lights := 0
	for child in altar.find_children("*", "", true, false):
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			meshes += 1
		if child is Light3D:
			lights += 1
	check(meshes >= 1, "the altar is drawn")
	check(lights == 1, "one ritual light hangs over it")
	check(altar.in_reach(altar.global_position + Vector3(2.0, 0.0, 0.0)), "2 m is inside reach")
	check(not altar.in_reach(altar.global_position + Vector3(4.0, 0.0, 0.0)), "4 m is outside reach")

	altar.opened.connect(_on_altar_opened)
	altar.interact(7)
	check(altar_opens.size() == 1 and altar_opens[0] == 7,
		"interact announces the peer that knelt: %s" % str(altar_opens))
	check(altar.last_peer == 7, "the altar remembers the last peer")
	check(altar.is_open(), "interact opens the panel")
	var panel = altar.ensure_menu()
	check(panel == menu, "an existing panel in the tree is adopted, not duplicated")
	check(panel.tier_rows().size() == 5, "the adopted panel is configured with the warband")
	altar.interact(8)
	check(altar.ensure_menu() == panel, "a second interact reuses the same panel")
	check(_menu_count(root) == 1, "the altar never stacks a second panel, got %d" % _menu_count(root))
	altar.close()
	check(not altar.is_open(), "the altar can close its panel")

	# With no panel in the tree, the altar has to build and place its own.
	root.remove_child(menu)
	menu.free()
	menu = null
	var fresh = altar.ensure_menu()
	check(fresh != null and fresh != panel, "with no UI in the tree the altar creates one")
	check(fresh.get_parent() == root, "the created panel lands on the scene root")
	check(fresh.tier_rows().size() == 5, "the created panel is configured with the warband")
	var fresh_rows: Array = fresh.unbind_rows()
	check(fresh_rows.size() == 1 and str(fresh_rows[0]["item_id"]) == "sword_arming",
		"the created panel reads the live stash")
	check(_menu_count(root) == 1, "exactly one panel exists, got %d" % _menu_count(root))
	check(not altar.is_open(), "ensure_menu alone does not open the panel")
