extends SceneTree
## Ten-slot paperdoll rules, hand conflicts, floor drops, persistence and hub UI.

const StateScript = preload("res://scripts/player_state.gd")
const Rules = preload("res://scripts/equipment_rules.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const Archer = preload("res://scripts/archer.gd")
const ItemArt = preload("res://scripts/item_art.gd")
const Combat = preload("res://scripts/combat.gd")
const Actor = preload("res://scripts/arena_actor.gd")
const TEST_SAVE := "user://paperdoll_regression_state.json"

## The pack this test works with. A new journey starts with an empty backpack, so
## a regression that is about the paperdoll has to bring its own kit instead of
## borrowing the starter one.
const TEST_KIT := [
	"bow_short","bow_recurve","bow_long",
	"sword_short","sword_arming","sword_great",
	"dagger_iron","staff_fire","staff_bone","shield_buckler",
	"shield_kite","shield_tower",
]

var state
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("PAPERDOLL_FAIL  ",message)

func _initialize() -> void:
	call_deferred("run")

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _collect_labels(node: Node, out: Array[String]) -> void:
	if node is Label:
		out.append(str(node.text))
	for child in node.get_children():
		_collect_labels(child,out)

func run() -> void:
	_remove(TEST_SAVE)
	state = root.get_node("PlayerState")
	state.save_path = TEST_SAVE
	state.reset()
	_test_taxonomy()
	_stock_pack()
	_test_weapon_sets()
	_test_hand_rules()
	_test_overflow_and_off_override()
	_test_dual_and_jewelry()
	_test_drop_and_pickup()
	_test_persistence()
	await _test_rig_loadouts()
	await _test_gear_replication()
	await _test_world_kit()
	await _test_frontier_loot()
	state.reset()
	_remove(TEST_SAVE)
	print("PAPERDOLL_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

## Give the pack the pieces the paperdoll checks put on and take off.
func _stock_pack() -> void:
	for item_id in TEST_KIT:
		if not state.inventory.has(item_id):
			state.inventory.append(item_id)


func _find(item_id: String) -> int:
	return state.inventory.find(item_id)

func _test_taxonomy() -> void:
	check(state.equipped.size() == Rules.SLOTS.size(),"The ranger has exactly ten equipment slots")
	for slot in Rules.SLOTS:
		check(state.equipped.has(slot),"Equipment exposes the %s slot" % slot)
	check(state.equipped_id("head") == "armor_makeshift_head","The Makeshift antler helm starts equipped")
	check(state.equipped_id("feet") == "armor_makeshift_feet","The Makeshift root boots start equipped")
	check(state.main_item() == "bow_short" and state.off_item().is_empty(),"The shortbow starts in the main hand with an empty off hand")
	check(state.inventory.is_empty(),"A new journey starts with an empty backpack")
	check(state.credits == StateScript.STARTING_CREDITS,"The starter purse is unchanged")
	for item_id: String in StateScript.ITEMS:
		var item: Dictionary = StateScript.ITEMS[item_id]
		check(not str(item.get("category","")).is_empty(),"%s has a taxonomy category" % item_id)
		var category := str(item.get("category",""))
		check(category in Rules.CATEGORIES,"%s uses a known category" % item_id)
		if category == "armor":
			check(Rules.allowed(item,str(item.get("slot",""))),"%s is legal in its armor slot" % item_id)
			check(not Rules.allowed(item,"main") and not Rules.allowed(item,"off"),"%s cannot enter a hand slot" % item_id)
		elif category == "1h":
			check(Rules.allowed(item,"main") and Rules.allowed(item,"off"),"%s is legal in either hand" % item_id)
			check(not Rules.allowed(item,"head"),"%s cannot enter an armor slot" % item_id)
		elif category in ["2h","bow","staff"]:
			check(Rules.allowed(item,"main"),"%s is legal in the main hand" % item_id)
			check(not Rules.allowed(item,"off"),"%s locks the off hand" % item_id)
		elif category in ["shield","focus"]:
			check(Rules.allowed(item,"off"),"%s is off-hand only" % item_id)
			check(not Rules.allowed(item,"main"),"%s cannot enter the main hand" % item_id)
		elif category == "jewelry":
			if str(item.get("slot","")) == "ring":
				check(Rules.allowed(item,"ring1") and Rules.allowed(item,"ring2"),"%s fits either ring slot" % item_id)
				check(not Rules.allowed(item,"neck"),"%s cannot enter the neck slot" % item_id)
			else:
				check(Rules.allowed(item,"neck"),"%s is neck only" % item_id)
		elif category == "armor_bundle":
			check(not Rules.allowed(item,"head") and not Rules.allowed(item,"main"),"%s is a legacy bundle, not equippable" % item_id)
	for item_id: String in StateScript.ITEMS:
		var item: Dictionary = StateScript.ITEMS[item_id]
		var category := str(item.get("category",""))
		var stats: Dictionary = StateScript.ITEM_STATS.get(item_id,{})
		check(not state.item_type_line(item_id).is_empty(),"%s has a HUD type line" % item_id)
		check(not state.item_quote(item_id).is_empty(),"%s has a quoted flavor line" % item_id)
		check(not state.item_stat_rows(item_id).is_empty() or category == "armor_bundle","%s has HUD stat rows" % item_id)
		if category == "bow":
			var bow_index := int(item.get("index",0))
			check(is_equal_approx(float(stats.get("damage",0.0)),float(Combat.BASE_DAMAGE[bow_index])),"%s HUD damage matches the bow profile" % item_id)
			check(is_equal_approx(float(stats.get("attack",0.0)),float(Archer.BOW_DATA[bow_index].draw_seconds)),"%s HUD draw speed matches the bow profile" % item_id)
		elif category in ["1h","2h"]:
			if str(item.get("kind","")) == "dagger":
				var dagger_index := int(item.get("index",0))
				var dagger: Dictionary = Archer.dagger_profile(dagger_index)
				check(is_equal_approx(float(stats.get("damage",0.0)),float(dagger.damage)),"%s HUD damage matches its dagger profile" % item_id)
				check(is_equal_approx(float(stats.get("attack",0.0)),float(dagger.seconds)),"%s HUD speed matches its dagger profile" % item_id)
				check(is_equal_approx(float(stats.get("reach",0.0)),float(dagger.reach)),"%s HUD reach matches its dagger profile" % item_id)
			else:
				var sword_index := int(item.get("index",0))
				check(is_equal_approx(float(stats.get("damage",0.0)),float(Archer.SWORD_DATA[sword_index].damage)),"%s HUD damage matches the sword profile" % item_id)
				check(is_equal_approx(float(stats.get("attack",0.0)),float(Archer.SWORD_DATA[sword_index].seconds)),"%s HUD swing speed matches the sword profile" % item_id)
				check(is_equal_approx(float(stats.get("reach",0.0)),float(Archer.SWORD_DATA[sword_index].reach)),"%s HUD reach matches the sword profile" % item_id)
		elif category == "staff":
			check(is_equal_approx(float(stats.get("damage",0.0)),float(Archer.SWORD_DATA[2].damage)),"%s HUD damage matches the staff's greatsword profile" % item_id)
			check(is_equal_approx(float(stats.get("attack",0.0)),float(Archer.SWORD_DATA[2].seconds)),"%s HUD swing speed matches the staff's greatsword profile" % item_id)
			check(is_equal_approx(float(stats.get("reach",0.0)),state.item_reach(item_id)),"%s HUD reach matches its middle-grip staff profile" % item_id)
		elif category == "shield":
			check(int(stats.get("block",0)) == int(Combat.SHIELD_BLOCK_STAMINA),"%s HUD block stamina matches the shield block" % item_id)
	check(StateScript.ITEMS.has("staff_fire") and StateScript.ITEMS.has("focus_skull") and StateScript.ITEMS.has("ring_blood"),"Staffs, skulls and rings are in the catalog")
	check(StateScript.ITEMS["shield_kite"].get("category","") == "shield","Shields use the shield category")
	check(StateScript.ITEMS["sword_great"].get("category","") == "2h","The greatsword is two-handed")
	check(StateScript.ITEMS["sword_short"].get("category","") == "1h","The shortsword is one-handed")
	var bow_loadout: Dictionary = state.loadout()
	check(str(bow_loadout.weapon) == "bow" and int(bow_loadout.bow) == 0,"The bow loadout maps to bow mode")
	var sword_loadout: Dictionary = StateScript.build_loadout("sword_arming","shield_kite",{"head":1,"chest":1,"hands":0,"legs":0,"feet":0})
	check(str(sword_loadout.weapon) == "sword" and int(sword_loadout.sword) == 1,"A one-handed sword loadout maps to sword mode")
	check(bool(sword_loadout.shield),"A shield off hand marks the shield")
	check(int(sword_loadout.armor.head) == 1,"Armor indexes survive build_loadout")
	var staff_loadout: Dictionary = StateScript.build_loadout("staff_fire","",{})
	check(str(staff_loadout.weapon) == "sword" and int(staff_loadout.sword) == 2 and int(staff_loadout.staff) == 0,"A staff maps to two-handed sword mode with a staff index")
	var focus_loadout: Dictionary = StateScript.build_loadout("sword_short","focus_tome",{})
	check(str(focus_loadout.focus.kind) == "tome","A tome off hand marks the focus")
	var off_weapon: Dictionary = StateScript.build_loadout("sword_short","dagger_iron",{})
	check(str(off_weapon.off_weapon.kind) == "dagger","An off-hand dagger marks the off weapon")

func _test_weapon_sets() -> void:
	state.reset()
	_stock_pack()
	check(state.weapon_sets.size() == StateScript.WEAPON_SET_COUNT,"Every player owns two weapon set slots")
	check(state.active_weapon_set() == 0,"Set 1 is the active set at the start")
	check(state.weapon_set_label(0) == "Shortbow","Set 1 starts on the equipped starter bow")
	check(state.weapon_set_label(1) == "Shortsword + Buckler","Set 2 starts on the starter sword and buckler")
	var bow_carried := _carried("bow_short")
	var sword_carried := _carried("sword_short")
	var before: int = state.inventory.size()
	var result: Dictionary = state.swap_weapon_set()
	check(bool(result.ok),"TAB brings up the other weapon set")
	check(state.main_item() == "sword_short" and state.off_item() == "shield_buckler","Both hands change together")
	check(state.active_weapon_set() == 1,"Set 2 is active after the swap")
	check(state.inventory.has("bow_short") and not state.inventory.has("sword_short") and not state.inventory.has("shield_buckler"),"The bow trades places with the melee pair")
	check(state.inventory.size() == before - 1,"The two-hand melee pair and one bow keep the backpack count honest")
	check(state.weapon_set_label(0) == "Shortbow","The set left behind remembers the bow")
	result = state.swap_weapon_set()
	check(bool(result.ok) and state.main_item() == "bow_short" and state.off_item().is_empty(),"TAB brings Set 1 back")
	check(state.active_weapon_set() == 0,"Set 1 is active again")
	check(state.inventory.has("sword_short") and state.inventory.has("shield_buckler"),"The melee pair returns to the backpack")
	check(_carried("bow_short") == bow_carried and _carried("sword_short") == sword_carried,"A swap never duplicates or loses a weapon")

	# Equipping something different rewrites the active set and leaves the
	# weapon waiting in the other set exactly where it was.
	result = state.equip_from_inventory(_find("staff_fire"))
	check(bool(result.ok) and state.main_item() == "staff_fire","The ember staff equips by hand")
	check(state.weapon_set_label(0) == "Ember Staff","The active set now holds the staff")
	check(state.weapon_set_label(1) == "Shortsword + Buckler","The other set still remembers its pair")
	check(state.inventory.has("bow_short"),"The replaced bow returns to the backpack")
	result = state.swap_weapon_set()
	check(bool(result.ok) and state.main_item() == "sword_short","TAB reaches the set the player left alone")
	result = state.swap_weapon_set()
	check(bool(result.ok) and state.main_item() == "staff_fire","TAB brings the newly equipped weapon back")

	# A hand change made while the other set is active lands in that set.
	result = state.swap_weapon_set()
	check(state.active_weapon_set() == 1,"Set 2 is active again")
	result = state.unequip_to_backpack("off")
	check(bool(result.ok),"The buckler comes off")
	result = state.equip_from_inventory(_find("dagger_iron"))
	check(bool(result.ok) and state.main_item() == "dagger_iron","The dagger equips into Set 2")
	check(state.weapon_set_label(1) == "Iron Dagger","Set 2 remembers the dagger")
	result = state.swap_weapon_set()
	check(bool(result.ok) and state.main_item() == "staff_fire","Set 1 kept the staff across that change")
	result = state.swap_weapon_set()
	check(bool(result.ok) and state.main_item() == "dagger_iron","Set 2 kept the dagger")

	# A two-hander fills its own set's main hand and leaves that set with no
	# off hand; the other set is untouched.
	result = state.equip_from_inventory(_find("sword_great"))
	check(bool(result.ok) and state.main_item() == "sword_great","The greatsword equips into Set 2")
	result = state.swap_weapon_set()
	check(bool(result.ok) and state.main_item() == "staff_fire","Set 1 survives the two-hander")
	result = state.swap_weapon_set()
	check(bool(result.ok) and state.main_item() == "sword_great" and state.off_item().is_empty(),"Set 2 keeps the greatsword")

	# An emptied set is still a real set: TAB leaves the ranger unarmed.
	state.reset()
	_stock_pack()
	result = state.unequip_to_backpack("main")
	check(bool(result.ok) and state.main_item().is_empty(),"Set 1 can be emptied")
	result = state.swap_weapon_set()
	check(bool(result.ok) and state.main_item() == "sword_short","Set 2 still swaps in")
	result = state.swap_weapon_set()
	check(bool(result.ok) and state.main_item().is_empty(),"TAB reaches the emptied set")
	check(state.active_weapon_set() == 0,"The emptied set is the active one")

	state.unequip_to_backpack("main")
	state.swap_weapon_set()
	state.unequip_to_backpack("main")
	state.unequip_to_backpack("off")
	result = state.swap_weapon_set()
	check(not bool(result.ok) and str(result.get("message","")).contains("empty"),"Two empty sets refuse the swap")

	# Both sets have to be carried: a stashed piece blocks the swap and leaves
	# the hands and the active set alone.
	state.reset()
	_stock_pack()
	result = state.move_to_stash(_find("shield_buckler"))
	check(bool(result.ok),"The buckler moves to the stash")
	result = state.swap_weapon_set()
	check(not bool(result.ok) and str(result.get("message","")).contains("not carried"),"A stashed set weapon blocks the swap")
	check(state.main_item() == "bow_short" and state.active_weapon_set() == 0,"A refused swap changes nothing")

func _carried(item_id: String) -> int:
	var count := 0
	if state.main_item() == item_id:
		count += 1
	if state.off_item() == item_id:
		count += 1
	for entry in state.inventory:
		if entry == item_id:
			count += 1
	return count

func _test_hand_rules() -> void:
	state.reset()
	_stock_pack()
	# A slot with no piece wears nothing on its channel; the body kit is
	# untouched, and the helm can go back on.
	var head_guard: float = state.head_reduction()
	var body_guard: float = state.body_reduction()
	check(head_guard > 0.0 and body_guard > 0.0,"The starter Makeshift kit guards both channels")
	check(bool(state.unequip_to_backpack("head").ok),"A helm can return to the backpack")
	check(is_equal_approx(state.head_reduction(),0.0),"An empty head slot guards nothing")
	check(is_equal_approx(state.body_reduction(),body_guard),"The body channel ignores the helm")
	check(bool(state.equip_from_inventory(_find("armor_makeshift_head")).ok),"The helm re-equips")
	check(is_equal_approx(state.head_reduction(),head_guard),"The head channel comes back with it")
	var sword := _find("sword_short")
	check(sword >= 0,"The starter sword is in the backpack")
	var result: Dictionary = state.equip_from_inventory(sword)
	check(bool(result.ok),"A backpack sword equips")
	check(state.main_item() == "sword_short","Right-click puts a one-hander in the main hand")
	check(state.inventory.has("bow_short"),"The displaced bow returns to the backpack")
	check(state.off_item().is_empty(),"The off hand stays empty")
	check(str(state.loadout().weapon) == "sword","The loadout follows the main sword")

	var shield := _find("shield_buckler")
	check(shield >= 0,"The starter buckler is in the backpack")
	result = state.equip_from_inventory(shield,"off")
	check(bool(result.ok),"A shield equips into the off hand")
	check(state.off_item() == "shield_buckler","The shield occupies the off slot")
	check(state.main_item() == "sword_short","The main sword stays equipped")
	check(bool(state.loadout().shield),"The loadout reports the shield")

	state.credits = 100000
	check(bool(state.buy("sword_great").ok),"The greatsword can be bought")
	var great := _find("sword_great")
	result = state.equip_from_inventory(great)
	check(bool(result.ok),"A two-hander equips")
	check(state.main_item() == "sword_great","The greatsword occupies the main hand")
	check(state.off_item().is_empty(),"The two-hander clears the off hand")
	check(state.inventory.count("sword_short") == 1,"The displaced sword returns to the backpack")
	check(state.inventory.count("shield_buckler") == 1,"The displaced shield returns to the backpack")
	check(not state.floor_items.has("sword_short") and not state.floor_items.has("shield_buckler"),"With room, both displaced pieces go to the backpack")

	# Off override: equipping an off piece from the backpack displaces the 2H.
	result = state.equip_from_inventory(_find("shield_buckler"),"off")
	check(bool(result.ok),"A shield can replace a two-handed grip")
	check(state.main_item().is_empty(),"The off override leaves the main hand empty")
	check(state.off_item() == "shield_buckler","The shield occupies the off hand")
	check(state.inventory.has("sword_great"),"The two-hander returns to the backpack")

	# Armor is per slot and a duplicate copy can remain in the backpack.
	check(bool(state.buy("armor_mail_chest").ok),"A mail chest can be bought")
	check(bool(state.buy("armor_mail_chest").ok),"A spare mail chest can be bought")
	result = state.equip_from_inventory(_find("armor_mail_chest"))
	check(bool(result.ok),"A mail chest equips")
	check(state.equipped_id("chest") == "armor_mail_chest","The mail chest occupies only the chest slot")
	check(state.equipped_id("head") == "armor_makeshift_head","The Makeshift helm stays equipped")
	# The worn pieces fill two channels: the Makeshift helm keeps its own head
	# figure, the four body pieces add up, and the mail chest replaces one.
	var makeshift := ArmorData.SET_IDS.find("makeshift")
	check(is_equal_approx(state.head_reduction(),ArmorData.reduction_for(makeshift,"head")),
		"The Makeshift helm keeps its head figure")
	check(is_equal_approx(state.body_reduction(),
			ArmorData.reduction_for(1,"chest") + ArmorData.reduction_for(makeshift,"legs")
			+ 2.0 * ArmorData.reduction_for(makeshift,"hands")),
		"The body channel adds exactly the worn pieces")
	check(is_equal_approx(state.body_reduction(),
			0.10 + ArmorData.reduction_for(1,"chest") - ArmorData.reduction_for(makeshift,"chest")),
		"A mail chest moves the full kit off the Makeshift body figure")
	check(state.inventory.count("armor_mail_chest") == 1,"The backpack keeps a spare copy")

func _test_overflow_and_off_override() -> void:
	state.reset()
	_stock_pack()
	state.credits = 100000
	check(bool(state.buy("sword_great").ok),"The overflow test buys a greatsword")
	# Fill the backpack completely, with the greatsword in the last slot.
	while state.inventory.size() < StateScript.INVENTORY_CAPACITY:
		state.inventory.append("ring_copper")
	var great := _find("sword_great")
	var sword := _find("sword_short")
	check(sword >= 0 and great >= 0,"The overflow test has both blades")
	check(bool(state.equip_from_inventory(sword).ok),"The shortsword enters the main hand")
	check(bool(state.equip_from_inventory(_find("shield_buckler"),"off").ok),"The buckler enters the off hand")
	# The backpack is full again after the shield left and the displaced bow returned?
	# Put the greatsword back and ensure exactly one free slot before the 2H equip.
	var great_slot := _find("sword_great")
	if great_slot < 0:
		state.inventory.append("sword_great")
		great_slot = state.inventory.size()-1
	# Make exactly one free slot: the 2H source leaves its own slot, so the old
	# main fits and the old off spills to the floor.
	while state.inventory.size() < StateScript.INVENTORY_CAPACITY:
		state.inventory.append("ring_copper")
	great_slot = state.inventory.find("sword_great")
	var before_floor: int = state.floor_items.size()
	var result: Dictionary = state.equip_from_inventory(great_slot)
	check(bool(result.ok),"The 2H override succeeds with one free slot")
	check(state.main_item() == "sword_great" and state.off_item().is_empty(),"The greatsword takes the main hand and locks off")
	check(state.floor_items.size() == before_floor+1,"The second displaced item drops to the floor")
	check(state.inventory.count("sword_short") == 1,"The first displaced item fits in the freed backpack slot")
	check(state.floor_items.has("shield_buckler"),"The shield is the second displaced item and lands on the floor")
	check(state.inventory.size() == StateScript.INVENTORY_CAPACITY,"The backpack stays at capacity")

func _test_dual_and_jewelry() -> void:
	state.reset()
	_stock_pack()
	# Main sword + off dagger is the routing contract; the rig decides the pose.
	state.inventory.append("sword_short")
	state.inventory.append("dagger_iron")
	var sword := _find("sword_short")
	check(bool(state.equip_from_inventory(sword).ok),"The main sword equips")
	check(bool(state.equip_from_inventory(_find("shield_buckler"),"off").ok),"A shield fills the off hand first")
	var dagger := _find("dagger_iron")
	var result: Dictionary = state.equip_from_inventory(dagger,"off")
	check(bool(result.ok),"A second one-hander equips into the off hand")
	check(state.off_item() == "dagger_iron","The dagger occupies the off hand")
	check(state.inventory.has("shield_buckler"),"The shield returns to the backpack")
	check(state.main_item() == "sword_short","The main sword is unchanged")
	check(str(state.loadout().off_weapon.kind) == "dagger","The loadout exposes the off dagger")

	# Alt-style routing without a target still goes to main.
	var second := _find("sword_arming")
	if second < 0:
		state.inventory.append("sword_arming")
		second = state.inventory.size()-1
	result = state.equip_from_inventory(second)
	check(bool(result.ok),"A second sword equips to the main hand")
	check(state.main_item() == "sword_arming" and state.off_item() == "dagger_iron","Replacing main keeps the off hand")

	# Paperdoll move/swap: ring1 to an empty ring2, then swap.
	state.equipped["ring1"] = "ring_copper"
	state.equipped["ring2"] = ""
	result = state.move_equipped("ring1","ring2")
	check(bool(result.ok),"A ring moves to the empty second ring slot")
	check(state.equipped_id("ring1").is_empty() and state.equipped_id("ring2") == "ring_copper","The ring moved")
	state.equipped["ring1"] = "ring_silver"
	result = state.move_equipped("ring1","ring2")
	check(bool(result.ok),"Two rings swap between the ring slots")
	check(state.equipped_id("ring1") == "ring_copper" and state.equipped_id("ring2") == "ring_silver","The ring swap landed")
	result = state.move_equipped("ring1","neck")
	check(not bool(result.ok),"A ring cannot move to the neck slot")
	state.equipped["main"] = "sword_great"
	state.equipped["off"] = ""
	result = state.move_equipped("main","off")
	check(not bool(result.ok),"A two-hander cannot move into the off hand")
	state.equipped["main"] = "sword_short"

	# Auto-routing fills ring1, then ring2, then replaces ring1.
	state.reset()
	_stock_pack()
	state.equipped["ring1"] = ""
	state.equipped["ring2"] = ""
	state.inventory.append("ring_copper")
	state.inventory.append("ring_silver")
	state.inventory.append("ring_blood")
	check(bool(state.equip_from_inventory(_find("ring_copper")).ok),"The first ring auto-equips")
	check(state.equipped_id("ring1") == "ring_copper","The first ring goes to ring1")
	check(bool(state.equip_from_inventory(_find("ring_silver")).ok),"The second ring auto-equips")
	check(state.equipped_id("ring2") == "ring_silver","The second ring goes to ring2")
	check(bool(state.equip_from_inventory(_find("ring_blood")).ok),"A third ring replaces ring1")
	check(state.equipped_id("ring1") == "ring_blood","The third ring takes ring1")
	check(state.inventory.has("ring_copper"),"The replaced ring returns to the backpack")

func _test_drop_and_pickup() -> void:
	state.reset()
	_stock_pack()
	var sword := _find("sword_short")
	var result: Dictionary = state.drop_from_inventory(sword)
	check(bool(result.ok),"A backpack item can be dropped")
	check(state.floor_items.has("sword_short"),"The dropped item is on the floor")
	check(not state.inventory.has("sword_short"),"The dropped item left the backpack")
	result = state.pickup_floor(0)
	check(bool(result.ok),"A floor item can be picked up")
	check(state.inventory.has("sword_short") and state.floor_items.is_empty(),"Picking up returns the item to the backpack")
	check(bool(state.equip_from_inventory(_find("sword_short")).ok),"The picked-up sword equips")
	result = state.drop_equipped("main")
	check(bool(result.ok),"An equipped item can be dropped")
	check(state.main_item().is_empty() and state.floor_items.has("sword_short"),"Dropping the main hand empties it and lands on the floor")
	while state.inventory.size() < StateScript.INVENTORY_CAPACITY:
		state.inventory.append("ring_copper")
	result = state.pickup_floor(0)
	check(not bool(result.ok),"A full backpack rejects a floor pickup")
	check(not state.floor_items.is_empty(),"The rejected floor item stays on the floor")
	result = state.try_pickup("ring_silver")
	check(not bool(result.ok),"A full backpack rejects world loot")
	state.inventory.remove_at(state.inventory.size()-1)
	result = state.try_pickup("ring_silver")
	check(bool(result.ok) and state.inventory.has("ring_silver"),"World loot enters the backpack")
	check(state.equipped_id("ring1").is_empty(),"World loot is never auto-equipped")

func _test_persistence() -> void:
	state.reset()
	_stock_pack()
	state.credits = 321
	state.equipped["neck"] = "neck_ember"
	state.equipped["ring1"] = "ring_copper"
	state.equipped["ring2"] = "ring_silver"
	state.floor_items.assign(["staff_fire","focus_tome"])
	state.inventory.append("sword_arming")
	# The hands are the active set, so a save writes them as Set 1 and keeps
	# whatever the other slot remembers.
	state.equipped["main"] = "sword_great"
	state.equipped["off"] = ""
	state.weapon_sets[1] = {"main":"bow_long", "off":""}
	state.save_state()
	var loaded = StateScript.new()
	loaded.save_path = TEST_SAVE
	loaded.load_state()
	check(loaded.credits == 321,"Credits survive a version-3 reload")
	check(loaded.equipped_id("neck") == "neck_ember","Neck jewelry survives a reload")
	check(loaded.equipped_id("ring1") == "ring_copper" and loaded.equipped_id("ring2") == "ring_silver","Rings survive a reload")
	check(loaded.main_item() == "sword_great" and loaded.off_item().is_empty(),"The active set survives a reload")
	check(loaded.weapon_set_label(0) == "Greatsword","Set 1 is the pair that was in hand")
	check(loaded.weapon_set_label(1) == "Longbow","Set 2 survives a reload")
	check(loaded.active_weapon_set() == 0,"The active set index survives a reload")
	check(PackedStringArray(loaded.floor_items) == PackedStringArray(state.floor_items),"Floor items survive a reload")
	loaded.free()

	# Version 1: one whole-set armor id and the old bow/sword keys.
	var v1_path := "user://paperdoll_v1.json"
	var v1 := FileAccess.open(v1_path,FileAccess.WRITE)
	v1.store_string(JSON.stringify({"version":1,"credits":200,
		"inventory":["bow_short","sword_short","armor_mail"],"stash":[],
		"equipped":{"bow":"bow_short","sword":"sword_short","armor":"armor_mail"}}))
	v1.close()
	var legacy = StateScript.new()
	legacy.save_path = v1_path
	legacy.load_state()
	check(legacy.main_item() == "bow_short","Version-1 the bow wins the main hand")
	for slot in ArmorData.SLOTS:
		check(legacy.equipped_id(slot) == ArmorData.item_id(1,slot),"Version-1 mail migrates to %s" % slot)
	check(legacy.inventory.has("sword_short"),"Version-1 the displaced sword returns to the backpack")
	check(not legacy.inventory.has("armor_mail"),"Version-1 the whole-set bundle is consumed by migration")
	check(not legacy.inventory.has("bow_short"),"Version-1 the equipped bow is not duplicated in the backpack")
	legacy.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(v1_path))

	# Version 2: per-slot armor pieces plus the old bow/sword.
	var v2_path := "user://paperdoll_v2.json"
	var v2 := FileAccess.open(v2_path,FileAccess.WRITE)
	v2.store_string(JSON.stringify({"version":2,"credits":140,
		"inventory":["bow_long","armor_mail_chest"],"stash":[],
		"equipped":{"bow":"bow_long","sword":"sword_short",
			"head":"armor_leather_head","chest":"armor_mail_chest","hands":"armor_leather_hands",
			"legs":"armor_leather_legs","feet":"armor_leather_feet"}}))
	v2.close()
	var v2_state = StateScript.new()
	v2_state.save_path = v2_path
	v2_state.load_state()
	check(v2_state.main_item() == "bow_long","Version-2 the longbow wins the main hand")
	check(v2_state.equipped_id("chest") == "armor_mail_chest","Version-2 per-slot armor migrates directly")
	check(v2_state.equipped_id("head") == "armor_leather_head","Version-2 the leather hood is preserved")
	check(v2_state.inventory.has("sword_short"),"Version-2 the sword returns to the backpack")
	check(not v2_state.inventory.has("bow_long") and not v2_state.inventory.has("armor_mail_chest"),"Version-2 equipped copies are peeled from the backpack")
	v2_state.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(v2_path))

	# Version 4 stored a single quick pair. When that pair was the one in hand,
	# the save carried no real second side at all, so migration gives the still
	# carried starter melee set the second slot.
	var v4_path := "user://paperdoll_v4.json"
	var v4 := FileAccess.open(v4_path,FileAccess.WRITE)
	v4.store_string(JSON.stringify({"version":4,"credits":90,
		"inventory":["bow_short","sword_short","shield_buckler"],"stash":[],
		"equipped":{"main":"bow_short","off":""},
		"quick":{"main":"bow_short","off":""}}))
	v4.close()
	var dead = StateScript.new()
	dead.save_path = v4_path
	dead.load_state()
	check(dead.weapon_set_label(1) == "Shortsword + Buckler","A version-4 pair equal to the hands leaves the carried melee set as Set 2")
	check(dead.weapon_set_label(0) == "Shortbow","...and the pair in hand stays Set 1")
	var rescued: Dictionary = dead.swap_weapon_set()
	check(bool(rescued.ok) and dead.main_item() == "sword_short","The migrated toggle swaps")
	rescued = dead.swap_weapon_set()
	check(bool(rescued.ok) and dead.main_item() == "bow_short","...and swaps back")
	dead.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(v4_path))

	# A version-4 save whose stored pair was not in hand already had two sides:
	# the pair in hand becomes the active set, the stored one the other.
	var v4_live := FileAccess.open(v4_path,FileAccess.WRITE)
	v4_live.store_string(JSON.stringify({"version":4,"credits":90,
		"inventory":["bow_short","sword_short","shield_buckler"],"stash":[],
		"equipped":{"main":"sword_short","off":"shield_buckler"},
		"quick":{"main":"bow_short","off":""}}))
	v4_live.close()
	var live = StateScript.new()
	live.save_path = v4_path
	live.load_state()
	check(live.weapon_set_label(0) == "Shortsword + Buckler","A version-4 save keeps the pair in hand as the active set")
	check(live.weapon_set_label(1) == "Shortbow","...and the stored pair as the other set")
	check(live.active_weapon_set() == 0,"The pair in hand is the active set after migration")
	live.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(v4_path))

	# A version-5 save stored both sides of the old toggle. The pair in hand
	# becomes the active set and the other side stays reachable by TAB.
	var v5_path := "user://paperdoll_v5.json"
	var v5 := FileAccess.open(v5_path,FileAccess.WRITE)
	v5.store_string(JSON.stringify({"version":5,"credits":120,
		"inventory":["bow_short","sword_great"],"stash":[],
		"equipped":{"main":"sword_short","off":"shield_buckler"},
		"quick":{"main":"sword_great","off":""},
		"quick_back":{"main":"sword_short","off":"shield_buckler"},
		"floor":[]}))
	v5.close()
	var toggle = StateScript.new()
	toggle.save_path = v5_path
	toggle.load_state()
	check(toggle.weapon_set_label(0) == "Shortsword + Buckler","A version-5 save keeps the pair in hand as Set 1")
	check(toggle.weapon_set_label(1) == "Greatsword","...and the other stored side as Set 2")
	check(toggle.active_weapon_set() == 0,"The pair in hand is active after migration")
	var migrated: Dictionary = toggle.swap_weapon_set()
	check(bool(migrated.ok) and toggle.main_item() == "sword_great","TAB reaches the migrated second set")
	migrated = toggle.swap_weapon_set()
	check(bool(migrated.ok) and toggle.main_item() == "sword_short","...and swaps back")
	toggle.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(v5_path))

func _test_rig_loadouts() -> void:
	var rig = Archer.new()
	root.add_child(rig)
	await process_frame
	await process_frame
	check(rig._built,"The ranger rig builds for loadout coverage")
	var armor := {"head":0,"chest":0,"hands":0,"legs":0,"feet":0}
	rig.apply_loadout(StateScript.build_loadout("bow_short","",armor))
	check(rig.weapon == "bow","A bow loadout enters bow mode")
	check(not rig.staff_active and not rig.focus_active and not rig.shield_equipped,"A bow loadout hides the off-hand gear")
	check(rig.active_bow.visible and not rig.active_sword.visible,"Only the bow is visible")

	rig.apply_loadout(StateScript.build_loadout("staff_fire","",armor))
	check(rig.weapon == "sword" and rig.staff_active and rig._staff_shown(),"A staff loadout shows the staff in sword mode")
	check(rig.active_staff.visible and not rig.active_sword.visible,"The staff replaces the greatsword mesh")
	check(not rig.can_equip_shield() and not rig.set_shield(true),"A staff locks the shield")
	var staff_base: Vector3 = rig.get_blade_base()
	var staff_tip: Vector3 = rig.get_blade_tip()
	check(staff_base.distance_to(staff_tip) > 1.0,"The staff has a long blade endpoint")
	check(is_equal_approx(rig.melee_reach(),state.item_reach("staff_fire")),"The rig's staff reach matches its middle-grip catalog profile")
	rig.set_weapon("sword")
	check(not rig.staff_active and not rig.active_staff.visible and rig.active_sword.visible,"Selecting a sword stows the staff")

	rig.apply_loadout(StateScript.build_loadout("sword_short","focus_tome",armor))
	check(rig.weapon == "sword" and not rig.shield_equipped,"A focus pairs with a one-handed main")
	check(rig.focus_active and rig.active_focus != null and rig.active_focus.visible,"The tome renders in the left hand")
	check(not rig.shield_equipped and rig.off_weapon_active == false,"A focus does not arm the off-hand weapon")

	rig.apply_loadout(StateScript.build_loadout("sword_short","shield_kite",armor))
	check(rig.shield_equipped and rig.active_shield.visible,"A shield loadout raises the carried shield")
	check(is_equal_approx(rig.active_shield.radius(),0.36),"The kite shield keeps its authored radius")
	rig.set_shield_variant(2)
	check(rig.active_shield.radius() > 0.40,"The tower shield uses a larger physical disc")
	rig.set_off_weapon("dagger",0,true)
	check(rig.set_weapon("dual") and not rig.shield_equipped,"Entering dual with an off weapon stows the shield")

	rig.apply_loadout(StateScript.build_loadout("sword_short","sword_arming",armor))
	check(rig.weapon == "dual" and rig.off_weapon_kind == "sword","Two one-handers enter dual wield")
	check(rig.active_off_weapon != null and rig.active_off_weapon.visible,"The off sword is visible")
	check(is_equal_approx(rig.melee_damage("left"),float(Archer.SWORD_DATA[1].damage)),"The left hand uses the off sword's damage")
	check(is_equal_approx(rig.melee_seconds("left"),float(Archer.SWORD_DATA[1].seconds)),"The left hand uses the off sword's timing")
	var left_hand: Vector3 = rig._bone_world(rig._arms[0][2]).origin
	check(rig.get_blade_base("left").distance_to(left_hand) < 0.25,"The left blade is socketed in the left hand")

	rig.apply_loadout(StateScript.build_loadout("","",armor))
	check(rig.weapon == "none","An empty main hand enters the unarmed mode")
	check(not rig.active_bow.visible and not rig.active_sword.visible and not rig.active_dagger.visible,"Unarmed hides every weapon")
	check(not rig.can_begin_melee("right") and not rig.can_begin_melee("left"),"Unarmed cannot start a melee attack")
	rig.apply_loadout(StateScript.build_loadout("","dagger_iron",armor))
	check(not rig.set_weapon("dual"),"An empty main hand cannot dual-wield the off weapon")
	rig.queue_free()
	await process_frame

func _test_gear_replication() -> void:
	var world := Node3D.new()
	world.name = "GearWorld"
	root.add_child(world)
	var host = Actor.new()
	host.slot = 0
	host.authoritative = true
	world.add_child(host)
	host.configure(1,false,"Host",Vector3.ZERO)
	host.rig.set_process(false)
	host.rig.set_physics_process(false)
	var replica = Actor.new()
	replica.slot = 1
	world.add_child(replica)
	replica.configure(2,false,"Replica",Vector3(1.5,0,0))
	replica.rig.set_process(false)
	replica.rig.set_physics_process(false)
	await physics_frame
	await physics_frame
	var armor := {"head":0,"chest":0,"hands":0,"legs":0,"feet":0}
	host.rig.apply_loadout(StateScript.build_loadout("staff_fire","",armor))
	var packed: Dictionary = host.snapshot()
	check(JSON.stringify(packed).to_utf8_buffer().size() < 1100,"The fighter snapshot stays below the ENet MTU budget")
	replica.apply_snapshot(packed)
	check(replica.rig.staff_active and replica.rig.active_staff.visible,"A staff survives the snapshot hand-off")
	host.rig.apply_loadout(StateScript.build_loadout("sword_short","sword_arming",armor))
	replica.apply_snapshot(host.snapshot())
	check(replica.rig.weapon == "dual" and replica.rig.off_weapon_kind == "sword","An off sword survives the snapshot hand-off")
	check(is_equal_approx(replica.rig.melee_damage("left"),float(Archer.SWORD_DATA[1].damage)),"The replicated left sword keeps its damage")
	host.rig.apply_loadout(StateScript.build_loadout("sword_short","focus_tome",armor))
	replica.apply_snapshot(host.snapshot())
	check(replica.rig.focus_active and replica.rig.active_focus.visible,"A focus survives the snapshot hand-off")
	host.rig.apply_loadout(StateScript.build_loadout("sword_short","shield_tower",armor))
	replica.apply_snapshot(host.snapshot())
	check(replica.rig.shield_equipped and replica.rig.active_shield.radius() > 0.40,"A tower shield survives the snapshot hand-off")
	world.queue_free()
	await process_frame

func _test_world_kit() -> void:
	state.reset()
	_stock_pack()
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.5).timeout
	game.set_physics_process(false)
	for enemy in game.enemies:
		enemy.set_physics_process(false)
	game.world_ui.open_equipment()
	check(game.world_ui.paperdoll_buttons.size() == 10,"The in-world kit renders ten paperdoll slots")
	check(game.world_ui.backpack_buttons.size() == StateScript.INVENTORY_CAPACITY,"The in-world kit buffers every backpack slot")
	check(game.world_ui.stash_buttons.size() == 20,"The stash panel renders twenty slots")
	var largest_stock := 0
	for vendor: Dictionary in StateScript.VENDORS:
		largest_stock = maxi(largest_stock,(vendor.stock as Array).size())
	check(game.world_ui.stock_buttons.size() == largest_stock,"The vendor list buffers every stock row")
	check(largest_stock > 28,"The quartermaster sells more than the old fixed pool")
	check(game.world_ui.paperdoll_panel.visible and game.world_ui.inventory_panel.visible,"Equipment shows the ranger and the backpack together")
	check(StateScript.INVENTORY_CAPACITY == 60,"The backpack is sixty single-item slots")
	check(game.world_ui.backpack_buttons.size() == 60,"The screen renders all sixty backpack cells")
	var missing: Array = ItemArt.missing(StateScript.ITEMS.keys())
	check(missing.is_empty(),"Every catalog item has a rendered screenshot")
	check(game.world_ui.preview != null,"Opening the kit builds the live ranger preview")
	check(game.world_ui.preview.rig != null and game.world_ui.preview.rig.armor_piece("head") == 4,"The preview wears the equipped armour")
	for index in state.inventory.size():
		check(game.world_ui.backpack_buttons[index].icon != null,"Backpack cell %d shows the item screenshot" % index)
	check(game.world_ui.paperdoll_buttons[0].text.begins_with("HEAD"),"The first paperdoll slot is the head")
	check(game.world_ui.paperdoll_buttons[5].slot == "neck" and game.world_ui.paperdoll_buttons[6].slot == "ring1","The trinket rail follows the slot order")
	check(game.world_ui.paperdoll_buttons[8].text.begins_with("MAIN HAND"),"The ninth paperdoll slot is the main hand")
	check(game.world_ui.paperdoll_buttons[9].text.begins_with("OFF-HAND"),"The tenth paperdoll slot is the off hand")
	var card = game.world_ui._item_card("dagger_iron","backpack")
	var card_labels: Array[String] = []
	_collect_labels(card,card_labels)
	var card_text := "\n".join(card_labels)
	check(card_text.contains("Iron Dagger"),"The hover card is titled with the item")
	check(card_text.contains("Type:"),"The hover card has a Type line")
	check(card_text.contains("Speed:"),"The hover card has a Speed line")
	check(card_text.contains("Damage:"),"The hover card has a Damage line")
	check(card_text.contains("EXTRA MODIFIERS"),"The hover card has an extra-modifier section")
	check(card_text.contains("Prison shank"),"The dagger's passive is on its extra line")
	check(card_text.contains(state.item_quote("dagger_iron")),"The hover card carries the item quote")
	check(card_text.contains("Speed:") and card_text.contains("Damage:"),"A weapon card keeps Speed and Damage")
	var wired_slot = game.world_ui.backpack_buttons[0]
	var wired_card = wired_slot._make_custom_tooltip(wired_slot.tooltip_text)
	check(wired_card is Control,"A backpack cell builds its hover card through the slot")
	wired_card.free()
	var shield_card = game.world_ui._item_card("shield_kite","backpack")
	var shield_labels: Array[String] = []
	_collect_labels(shield_card,shield_labels)
	var shield_text := "\n".join(shield_labels)
	check(shield_text.contains("BLOCK"),"A shield card shows its block channel")
	check(not shield_text.contains("Speed:") and not shield_text.contains("Damage:"),"A shield card omits weapon lines")
	var armor_card = game.world_ui._item_card("armor_plate_chest","backpack")
	var armor_labels: Array[String] = []
	_collect_labels(armor_card,armor_labels)
	var armor_text := "\n".join(armor_labels)
	check(not armor_text.contains("Speed:") and not armor_text.contains("Damage:"),"An armour card omits Speed and Damage")
	check(armor_text.contains("BODY GUARD"),"An armour card keeps its guard modifier")
	check(armor_card.custom_minimum_size.x <= 260.0,"The hover card stays content-sized")
	armor_card.free()
	# The custom tooltip is measured at the card's real content width; a Label
	# wrapped at zero width otherwise reports a screen-tall minimum.
	var hover_slot = game.world_ui.backpack_buttons[0]
	var hover_card = hover_slot._make_custom_tooltip(hover_slot.tooltip_text)
	check(hover_card is Control,"A hovered slot builds the custom tooltip control")
	var hover_min: Vector2 = (hover_card as Control).get_combined_minimum_size()
	check(hover_min.x < 400.0 and hover_min.y < 400.0,"The tooltip control is content-sized, not screen-tall")
	hover_card.free()
	check(game.world_ui._stat_values["defense"].text == "%d%%" % state.defense_percent(),"The summary shows the worn damage reduction")
	card.free()
	shield_card.free()
	for button in game.world_ui.paperdoll_buttons:
		check(game.world_ui.paperdoll_panel.get_global_rect().encloses(button.get_global_rect()),"Paperdoll slots sit inside their panel")
	game.world_ui.close()
	game.world_ui.open_inventory()
	check(game.world_ui.inventory_panel.visible and game.world_ui.paperdoll_panel.visible,"Inventory keeps the ranger and the pack together")
	for button in game.world_ui.backpack_buttons:
		check(game.world_ui.inventory_panel.get_global_rect().encloses(button.get_global_rect()),"Backpack slots sit inside their panel")
	# Equip the starter sword from the pack and check the live rig follows.
	var sword: int = state.inventory.find("sword_short")
	check(sword >= 0,"The starter sword is in the pack")
	game.world_ui._location = "backpack"
	game.world_ui._index = sword
	game.world_ui._on_primary()
	check(state.main_item() == "sword_short","Equipping from the pack updates the main hand")
	check(game.archer.weapon == "sword","The live rig applies the equipped sword")
	check(game.world_ui.preview.rig.weapon == "sword","The live preview follows the equipped sword")
	check(state.inventory.has("bow_short"),"The displaced bow returns to the pack")
	# Right-click unequips the main hand back into the pack.
	game.world_ui._on_right_clicked("paperdoll",-1,"main","sword_short")
	check(state.main_item().is_empty() and state.inventory.has("sword_short"),"Right-click unequips the paperdoll")
	# Click-to-pick and click-to-place, then drag to the backpack.
	var click_index: int = state.inventory.find("sword_short")
	check(click_index >= 0,"The unequipped sword is back in the pack")
	game.world_ui._on_slot_pressed("backpack",click_index,"")
	check(game.world_ui._held_item == "sword_short","Clicking a backpack piece picks it up")
	game.world_ui._on_slot_pressed("paperdoll",-1,"main")
	check(state.main_item() == "sword_short" and game.world_ui._held_item.is_empty(),"Clicking a worn slot places the picked piece")
	game.world_ui._on_slot_pressed("paperdoll",-1,"main")
	check(game.world_ui._held_item == "sword_short","Clicking a worn piece picks it up")
	game.world_ui._on_slot_pressed("paperdoll",-1,"main")
	check(state.main_item() == "sword_short" and game.world_ui._held_item.is_empty(),"Clicking the same slot puts the piece back")
	var drag_payload := {"area":"paperdoll", "index":-1, "slot":"main", "item":"sword_short"}
	var drag_target = game.world_ui.backpack_buttons[0]
	check(drag_target._can_drop_data(Vector2.ZERO,drag_payload),"A backpack cell accepts the dragged piece")
	drag_target._drop_data(Vector2.ZERO,drag_payload)
	check(state.main_item().is_empty() and state.inventory.has("sword_short"),"Dragging a worn piece onto the pack unequips it")
	check(game.world_ui._held_item.is_empty(),"A drop clears the held piece")
	var drag_index: int = state.inventory.find("sword_short")
	var bag_payload := {"area":"backpack", "index":drag_index, "slot":"", "item":"sword_short"}
	var hand_target = game.world_ui.paperdoll_buttons[8]
	check(hand_target._can_drop_data(Vector2.ZERO,bag_payload),"A worn slot accepts a dragged backpack piece")
	hand_target._drop_data(Vector2.ZERO,bag_payload)
	check(state.main_item() == "sword_short","Dragging a backpack piece onto the main hand equips it")
	game.world_ui.close()
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	game._unhandled_input(tab)
	check(state.main_item() == "sword_short" and state.off_item() == "shield_buckler","TAB brings up the other weapon set")
	check(game.archer.weapon == "sword" and game.archer.shield_equipped,"TAB applies the other set to the live rig")
	# The paperdoll's SWAP SET button is the clickable form of TAB.
	game.world_ui.open_equipment()
	game.world_ui._location = "paperdoll"
	game.world_ui._slot = "main"
	game.world_ui._on_secondary()
	check(state.main_item() == "sword_short" and state.off_item().is_empty() and state.active_weapon_set() == 0,
		"SWAP SET brings the first set back")
	check(not game.archer.shield_equipped,"The live rig follows the paperdoll swap")
	game.world_ui.close()
	game.queue_free()
	await process_frame

func _test_frontier_loot() -> void:
	state.reset()
	_stock_pack()
	state.equipped["main"] = "sword_short"
	state.equipped["off"] = "shield_buckler"
	state.equipped["head"] = "armor_mail_head"
	state.equipped["chest"] = "armor_mail_chest"
	state.equipped["hands"] = "armor_mail_hands"
	state.equipped["legs"] = "armor_mail_legs"
	state.equipped["feet"] = "armor_mail_feet"
	state.inventory.clear()
	state.save_state()
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.5).timeout
	game.set_physics_process(false)
	for enemy in game.enemies:
		enemy.set_physics_process(false)
	check(game.archer.weapon == "sword","The frontier starts with the paperdoll main sword")
	check(game.archer.shield_equipped,"The frontier starts with the paperdoll shield")
	check(game.archer.armor_piece("chest") == 1,"The frontier starts with the paperdoll armor")
	check(state.inventory.is_empty(),"The frontier starts with an empty backpack")
	var pickup = game._spawn_loot("ring_copper",game.player.global_position)
	await process_frame
	check(pickup != null and is_instance_valid(pickup),"A floor pickup spawns")
	game._collect_loot(0.0)
	check(state.inventory.has("ring_copper"),"Walking over a pickup banks it in the backpack")
	check(pickup.is_queued_for_deletion() and not game.loot_pickups.has(pickup),"A claimed pickup is removed from the ground")
	# A full backpack leaves the drop on the ground.
	while state.inventory.size() < StateScript.INVENTORY_CAPACITY:
		state.inventory.append("ring_silver")
	var blocked = game._spawn_loot("ring_blood",game.player.global_position)
	await process_frame
	game._collect_loot(0.0)
	check(state.inventory.size() == StateScript.INVENTORY_CAPACITY,"A full backpack does not accept loot")
	check(is_instance_valid(blocked) and game.loot_pickups.has(blocked),"The rejected pickup stays on the ground")
	state.inventory.remove_at(state.inventory.size()-1)
	game._collect_loot(0.0)
	check(state.inventory.has("ring_blood"),"The same pickup is claimable after making room")
	var cinder = null
	for enemy in game.enemies:
		if int(enemy.kind) == 2:
			cinder = enemy
			break
	check(cinder != null,"The frontier contains a cinder devil")
	if cinder != null:
		cinder.devil_weapon = "sword"
		var pickups_before: int = game.loot_pickups.size()
		# Loot now rolls at one tenth, so drive the authoritative kill path until
		# the roll lands; the mapping it produces is what this test owns.
		seed(20261025)
		var dropped := false
		for attempt in 240:
			game._on_enemy_defeated(cinder,6)
			for drop_node in game.loot_pickups:
				if is_instance_valid(drop_node) and str(drop_node.item_id) == "sword_short":
					dropped = true
			if dropped:
				break
		check(dropped and game.loot_pickups.size() == pickups_before + 1,"A sword devil's held shortsword is the loot when the roll lands")
	game.queue_free()
	await process_frame
