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
const AltarMenuScript = preload("res://scripts/warband/altar_menu.gd")
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
	check(not bow.is_empty(), "a worn bow is offered: an anointing lives on the piece")
	check(not sword.is_empty(), "a pooled sword is offered")
	check(_anoint_row("ring_silver").is_empty(), "a ring wakes into nothing and is not offered")
	var bow_skill := str(AbilityRules.skill_for(State.ITEMS["bow_short"]).get("id", ""))
	check(str(bow.get("ability", "")) == bow_skill and not bow_skill.is_empty(),
		"the row names the skill the bow wakes into (%s)" % str(bow.get("ability", "")))
	check(str(bow.get("key", "")) == "1", "a bow's skill is the main hand's key")
	check(not bool(bow.get("anointed", true)) and bow.get("button") != null, "a plain piece carries a button")

	var before := changed_hits
	(bow["button"] as Button).pressed.emit()
	check(warband.cruor.is_anointed("bow_short"), "the press wakes the bow")
	check(stash.pooled_count(reagent) == 0, "exactly the recipe left the shared stash")
	check(changed_hits == before + 1, "the panel announces the rite once")
	check(str(body.ability.definition(0).get("id", "")) == bow_skill,
		"the fielded body carries the skill at once, got %s" % str(body.ability.definition(0).get("id", "")))
	check(warband.quests.is_complete("bind_the_ichor"), "the ichor order hears about the rite")
	var woken := _anoint_row("bow_short")
	check(bool(woken.get("anointed", false)) and woken.get("button") == null,
		"the woken bow reads as done and offers no button")

	# The sword with the stash empty: refused out loud, nothing moves.
	before = changed_hits
	(_anoint_row("sword_short")["button"] as Button).pressed.emit()
	check(not warband.cruor.is_anointed("sword_short"), "an empty stash wakes nothing")
	check(changed_hits == before, "a refused rite announces nothing")
	check(menu.status_text().contains(str(State.ITEMS[reagent]["name"])),
		"the refusal names the reagent it wants: %s" % menu.status_text())

	# A woken piece is not woken twice, and a piece the band does not carry is refused.
	stash.add(reagent, 1)
	check(not bool(warband.anoint("bow_short").get("ok", true)), "a woken piece refuses a second rite")
	check(not bool(warband.anoint("bow_long").get("ok", true)), "a piece the warband does not carry is refused")
	check(stash.pooled_count(reagent) == 1, "neither refusal spends the reagent")

	# The ledger rides the save.
	var saved: Dictionary = warband.to_dict()
	warband.reset_state()
	check(not warband.cruor.is_anointed("bow_short"), "a reset forgets the rite")
	warband.from_dict(saved)
	check(warband.cruor.anointed_skill("bow_short") == bow_skill, "the anointing survives the save")
	check(not warband.cruor.is_anointed("sword_short"), "and the refused sword is still plain")

	menu.close()
	field.queue_free()
	await process_frame

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
