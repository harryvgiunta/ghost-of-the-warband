extends SceneTree
## Hub economy, persistence, preview wiring and mode hand-off.

const StateScript = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const TEST_SAVE := "user://hub_regression_state.json"

var failures := 0
var checks := 0
var state
var session

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("HUB_FAIL  ",message)

func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

func run() -> void:
	_remove_test_save()
	state = root.get_node("PlayerState")
	session = root.get_node("Session")
	state.save_path = TEST_SAVE
	state.reset()
	_test_state_rules()
	_test_persistence()
	_test_session_bridge()
	await _test_menu()
	await _test_frontier()
	await _test_arena()
	session.clear()
	_remove_test_save()
	print("HUB_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func _test_state_rules() -> void:
	check(state.INVENTORY_CAPACITY == 10,"Backpack holds ten slots")
	check(state.STASH_CAPACITY == 20,"Stash holds twenty slots")
	check(state.inventory.size() == 3,"Starter backpack holds three items")
	check(PackedStringArray(state.inventory) == PackedStringArray(["sword_short","dagger_iron","shield_buckler"]),"Starter backpack carries the sword, dagger and buckler")
	check(state.stash.is_empty(),"Stash starts empty")
	check(state.floor_items.is_empty(),"The floor starts clear")
	check(state.credits == StateScript.STARTING_CREDITS,"Starting purse is the authoring constant")
	check(state.equipped_id("main") == "bow_short","The starter shortbow fills the main hand")
	check(state.equipped_id("off").is_empty(),"The starter off hand is empty")
	check(state.equipped_index("bow") == 0,"Starter shortbow drives the gameplay bow index")
	check(state.equipped_index("sword") == 0,"A bow main hand reports the short sword index")
	for armor_slot in ArmorData.SLOTS:
		check(state.equipped_id(armor_slot) == "armor_leather_" + armor_slot,"Starter leather %s is equipped" % armor_slot)
		check(state.equipped_index(armor_slot) == 0,"Starter leather %s reports set index zero" % armor_slot)
	check(state.is_equipped("bow_short"),"The paperdoll bow is queryable")
	check(state.is_equipped("armor_leather_chest"),"The paperdoll chest is queryable")
	check(state.owned_in_inventory("bow_short") == 0,"Equipped starter gear is not duplicated in the backpack")
	check(state.owned_in_inventory("armor_leather_chest") == 0,"Equipped starter armor leaves the backpack")

	var credits_before: int = state.credits
	var result: Dictionary = state.buy("bow_long")
	check(not bool(result.ok),"A longbow is unaffordable with the starting purse")
	check(state.credits == credits_before,"A rejected purchase spends nothing")
	check(not state.inventory.has("bow_long"),"A rejected purchase stores nothing")

	state.credits = 2000
	result = state.buy("bow_long")
	check(bool(result.ok),"An affordable purchase succeeds")
	check(state.inventory[-1] == "bow_long","Purchases append to the backpack")
	check(state.credits == 1640,"Purchase spends the listed price")
	var long_index: int = state.inventory.size()-1
	result = state.equip_from_inventory(long_index)
	check(bool(result.ok),"Backpack gear can be equipped through the paperdoll flow")
	check(state.equipped_id("main") == "bow_long","Equipping a longbow fills the main hand")
	check(state.equipped_index("bow") == 2,"Equipping a longbow drives the gameplay bow index")
	check(state.is_equipped("bow_long"),"Equipped state is queryable")
	check(state.owned_in_inventory("bow_long") == 0,"Equipped gear leaves the backpack")
	check(state.owned_in_inventory("bow_short") == 1,"The displaced starter bow returns to the backpack")
	check(state.equipped_id("off").is_empty(),"A bow leaves the off hand empty")

	result = state.buy("bow_long")
	check(bool(result.ok),"Duplicate gear can be bought")
	var duplicate_index: int = state.inventory.size()-1
	credits_before = state.credits
	result = state.sell("inventory",duplicate_index)
	check(bool(result.ok),"A duplicate copy sells while that item type is equipped")
	check(state.credits == credits_before + state.sell_value("bow_long"),"Selling pays the sell rate")
	check(state.owned_in_inventory("bow_long") == 0,"Selling removes one copy only")
	check(state.equipped_index("bow") == 2,"Selling a duplicate leaves the paperdoll bow equipped")

	# The paperdoll owns equipped gear, so a spare backpack copy is ordinary
	# stock: there is no last-copy protection left.
	state.credits = 2000
	check(bool(state.buy("armor_leather_head").ok),"A spare copy of equipped armor can be bought")
	var spare_hood: int = state.inventory.find("armor_leather_head")
	check(spare_hood >= 0,"The spare hood sits in the backpack")
	credits_before = state.credits
	result = state.sell("inventory",spare_hood)
	check(bool(result.ok),"The backpack's only copy of the equipped hood sells")
	check(state.credits == credits_before + state.sell_value("armor_leather_head"),"Selling the spare pays the sell rate")
	check(state.equipped_id("head") == "armor_leather_head","Selling a backpack copy leaves the hood equipped")

	var starter_index: int = state.inventory.find("bow_short")
	check(starter_index >= 0,"The displaced starter bow is still present")
	check(bool(state.move_to_stash(starter_index).ok),"Unequipped gear moves to the stash")
	check(state.stash.size() == 1,"Stash receives the moved item")
	check(bool(state.move_to_inventory(0).ok),"Stashed gear returns to the backpack")
	check(state.stash.is_empty(),"Returning gear empties the stash slot")

	# Per-slot equipping: a mail chest must not replace the leather hood.
	check(bool(state.buy("armor_mail_chest").ok),"A single armor piece can be bought")
	var mail_chest: int = state.inventory.find("armor_mail_chest")
	check(bool(state.equip_from_inventory(mail_chest).ok),"A single armor piece can be equipped")
	check(state.equipped_id("chest") == "armor_mail_chest","The mail chest occupies only the chest slot")
	check(state.equipped_index("chest") == 1,"The mail chest reports the mail set index")
	check(state.equipped_index("head") == 0,"The leather hood remains equipped")
	check(state.is_equipped("armor_mail_chest"),"The mixed armor piece is queryable")
	check(state.owned_in_inventory("armor_mail_chest") == 0,"Equipped mail leaves the backpack")
	check(state.inventory.has("armor_leather_chest"),"The displaced leather chest returns to the backpack")
	check(is_equal_approx(state.armor_reduction(),0.05),"Only the mail chest contributes guard")

	check(bool(state.buy("sword_arming").ok),"A one-handed sword can be bought")
	var arming_index: int = state.inventory.find("sword_arming")
	check(bool(state.equip_from_inventory(arming_index).ok),"A sword equips from the backpack")
	check(state.equipped_id("main") == "sword_arming","The arming sword fills the main hand")
	check(state.equipped_index("sword") == 1,"Equipping an arming sword drives the gameplay sword index")
	check(state.equipped_index("bow") == 0,"A sword main hand reports no bow")
	check(state.owned_in_inventory("sword_arming") == 0,"The equipped sword leaves the backpack")

	state.credits = 100000
	while not state.inventory_full():
		check(bool(state.buy("armor_leather").ok),"Buying fills the backpack")
	check(state.inventory.size() == StateScript.INVENTORY_CAPACITY,"Backpack stops at ten")
	result = state.buy("armor_leather")
	check(not bool(result.ok),"A full backpack rejects purchases")
	check(state.inventory.size() == StateScript.INVENTORY_CAPACITY,"A rejected purchase grows nothing")

	while not state.stash_full():
		if state.inventory_full():
			var moved := false
			for index in state.inventory.size():
				if bool(state.move_to_stash(index).ok):
					moved = true
					break
			check(moved,"A full backpack can always drain unequipped gear to the stash")
		check(bool(state.buy("armor_leather").ok),"Refill after draining")
		check(bool(state.move_to_stash(state.inventory.size()-1).ok),"Move the refill to the stash")
	check(state.stash.size() == StateScript.STASH_CAPACITY,"Stash stops at twenty")
	check(bool(state.buy("armor_leather").ok),"An item can still be bought with a full stash")
	result = state.move_to_stash(state.inventory.size()-1)
	check(not bool(result.ok),"A full stash rejects further storage")
	check(state.stash.size() == StateScript.STASH_CAPACITY,"A rejected move grows nothing")

	credits_before = state.credits
	result = state.sell("stash",0)
	check(bool(result.ok),"Stashed gear can be sold")
	check(state.stash.size() == StateScript.STASH_CAPACITY-1,"Selling frees a stash slot")
	check(state.credits > credits_before,"Selling from the stash pays credits")

	credits_before = state.credits
	state.add_credits(7)
	check(state.credits == credits_before + 7,"Frontier rewards reach the purse")

func _test_persistence() -> void:
	var dropped_id: String = state.inventory[0]
	check(bool(state.drop_from_inventory(0).ok),"A backpack item can be dropped to the floor")
	check(PackedStringArray(state.floor_items) == PackedStringArray([dropped_id]),"Dropped gear waits on the floor")
	state.save_state()
	var saved_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE))
	check(typeof(saved_data) == TYPE_DICTIONARY,"The save is readable JSON")
	if typeof(saved_data) == TYPE_DICTIONARY:
		var saved: Dictionary = saved_data
		check(int(saved.get("version",0)) == StateScript.SAVE_VERSION,"The save writes the current version")
	var loaded = StateScript.new()
	loaded.save_path = TEST_SAVE
	loaded.load_state()
	check(loaded.credits == state.credits,"Credits survive a reload")
	check(PackedStringArray(loaded.inventory) == PackedStringArray(state.inventory),"Backpack survives a reload")
	check(PackedStringArray(loaded.stash) == PackedStringArray(state.stash),"Stash survives a reload")
	check(PackedStringArray(loaded.floor_items) == PackedStringArray(state.floor_items),"Floor items survive a reload")
	for kind in StateScript.DEFAULTS:
		check(loaded.equipped_id(kind) == state.equipped_id(kind),"Equipped %s survives a reload" % kind)
	loaded.free()

	# A version-1 save stored one whole-set armor id; it must expand to the five
	# per-slot pieces and stop answering as the legacy bundle.
	var v1_path := "user://hub_regression_v1.json"
	var v1_file := FileAccess.open(v1_path, FileAccess.WRITE)
	v1_file.store_string(JSON.stringify({"version":1,"credits":200,
		"inventory":["bow_short","sword_short","armor_mail"],"stash":[],
		"equipped":{"bow":"bow_short","sword":"sword_short","armor":"armor_mail"}}))
	v1_file.close()
	var legacy = StateScript.new()
	legacy.save_path = v1_path
	legacy.load_state()
	for slot in ArmorData.SLOTS:
		check(legacy.equipped_id(slot) == "armor_mail_" + slot,"Version-1 armor migrates to the %s slot" % slot)
	check(legacy.equipped_index("chest") == 1,"Migrated mail preserves its set index")
	check(legacy.is_equipped("armor_mail_chest"),"Migrated per-slot mail is queryable")
	check(not legacy.is_equipped("armor_mail"),"The legacy bundle id is no longer queryable")
	check(legacy.equipped_id("main") == "bow_short","The legacy bow keeps the main hand")
	check(legacy.equipped_id("off").is_empty(),"Legacy saves leave the off hand empty")
	check(not legacy.inventory.has("bow_short") and not legacy.inventory.has("armor_mail"),"Migrated equipped copies leave the backpack")
	check(legacy.inventory.has("sword_short"),"The displaced legacy sword stays in the backpack")
	check(is_equal_approx(legacy.armor_reduction(),0.15),"A migrated mail kit keeps its full guard")
	legacy.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(v1_path))

	# A version-2 save stored one armor piece per slot; every piece must survive.
	var v2_path := "user://hub_regression_v2.json"
	var v2_file := FileAccess.open(v2_path, FileAccess.WRITE)
	v2_file.store_string(JSON.stringify({"version":2,"credits":260,
		"inventory":["bow_recurve","sword_arming","armor_leather_head"],"stash":["dagger_iron"],
		"equipped":{"bow":"bow_recurve","sword":"sword_arming",
			"head":"armor_plate_head","chest":"armor_plate_chest","hands":"armor_leather_hands",
			"legs":"armor_plate_legs","feet":"armor_cloth_feet"}}))
	v2_file.close()
	var per_slot = StateScript.new()
	per_slot.save_path = v2_path
	per_slot.load_state()
	var expected_pieces := {
		"head":"armor_plate_head","chest":"armor_plate_chest","hands":"armor_leather_hands",
		"legs":"armor_plate_legs","feet":"armor_cloth_feet"
	}
	for slot in ArmorData.SLOTS:
		check(per_slot.equipped_id(slot) == expected_pieces[slot],"Version-2 keeps the %s piece" % slot)
	check(per_slot.equipped_id("main") == "bow_recurve","Version-2 keeps the stored bow")
	check(per_slot.equipped_index("chest") == 2,"Version-2 keeps the plate chest index")
	check(is_equal_approx(per_slot.armor_reduction(),0.22),"Version-2 keeps the mixed-set guard")
	check(per_slot.inventory.has("sword_arming"),"The stored legacy sword returns to the backpack")
	check(not per_slot.inventory.has("bow_recurve"),"The equipped legacy bow leaves the backpack")
	check(PackedStringArray(per_slot.stash) == PackedStringArray(["dagger_iron"]),"Version-2 keeps the stash")
	per_slot.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(v2_path))

func _test_session_bridge() -> void:
	session.clear()
	check(not session.has_request(),"No arena request is pending at rest")
	session.arm_arena("host","127.0.0.1",70000,"  Branch  ")
	check(session.has_request(),"A hub deploy arms an arena request")
	var request: Dictionary = session.take()
	check(not session.has_request(),"The arena consumes its request exactly once")
	check(str(request.mode) == "host" and str(request.address) == "127.0.0.1","A host request carries its mode and address")
	check(int(request.port) == 65535,"The session clamps an out-of-range port")
	check(str(request.name) == "Branch","The session trims the player name")
	session.arm_arena("client","10.0.0.5",7777,"")
	request = session.take()
	check(str(request.mode) == "client" and str(request.address) == "10.0.0.5","A join request carries the host address")
	check(str(request.name) == "Ranger","An empty join name falls back to Ranger")
	session.arm_arena("skirmish","127.0.0.1",7777,"Practice")
	request = session.take()
	check(str(request.mode) == "skirmish","Practice keeps its own mode so the arena can pick a free port")
	session.arm_delve("delve-solo","127.0.0.1",7777,"Delver")
	request = session.take()
	check(str(request.mode) == "delve-solo","The hub arms a solo delve request")
	check(str(request.address) == "127.0.0.1" and int(request.port) == 7777,"A solo delve keeps the local route")
	check(str(request.name) == "Delver","A delve request carries the preferred name")
	session.arm_delve("delve-join","10.0.0.6",7900,"")
	request = session.take()
	check(str(request.mode) == "delve-join","A delve join keeps its own mode")
	check(str(request.address) == "10.0.0.6","A delve join carries the host address")
	check(str(request.name) == "Ranger","An empty delve name falls back to Ranger")

func _test_menu() -> void:
	state.reset()
	state.equipped = {
		"head":"armor_mail_head","chest":"armor_mail_chest","hands":"armor_mail_hands",
		"legs":"armor_mail_legs","feet":"armor_mail_feet",
		"neck":"neck_ember","ring1":"ring_copper","ring2":"",
		"main":"sword_arming","off":"shield_kite"
	}
	state.save_state()
	var menu = load("res://menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	check(str(ProjectSettings.get_setting("application/run/main_scene")) == "res://menu.tscn","The hub is the game's default screen")
	check(menu.state == state,"The hub uses the persistent PlayerState service")
	check(menu.archer != null and menu.archer.is_visible_in_tree(),"The ranger stands in the default screen")
	check(menu.camera != null and menu.camera.current,"The hub frames the ranger with an active camera")
	check(menu.archer.bow_index == 0,"The preview reads the stored bow slot")
	check(menu.archer.sword_index == 1,"Preview equips the stored arming sword")
	check(menu.archer.shield_equipped,"Preview raises the stored off-hand shield")
	check(menu.archer.weapon == "sword","The preview derives sword mode from the paperdoll")
	check(menu.archer.armor_piece("head") == 1,"Preview equips the stored mail hood")
	check(menu.archer.armor_piece("chest") == 1,"Preview equips the stored mail chest")
	check(menu.archer.armor_piece("feet") == 1,"Preview equips the stored mail sabatons")
	var stored_loadout: Dictionary = state.loadout()
	check(int(stored_loadout["sword"]) == menu.archer.sword_index,"The preview consumes PlayerState.loadout()")
	check(bool(stored_loadout["shield"]) == menu.archer.shield_equipped,"The preview consumes the loadout's off hand")
	check(int(stored_loadout["armor"]["chest"]) == menu.archer.armor_piece("chest"),"The preview consumes the loadout's armor map")
	var mail_chest_mesh := menu.archer._model.find_child("Armor_Mail_Chest",true,false) as MeshInstance3D
	var leather_body := menu.archer._model.find_child("Male_Ranger_Body",true,false) as MeshInstance3D
	check(mail_chest_mesh != null and mail_chest_mesh.visible,"The mail chest replaces the leather torso mesh")
	check(leather_body != null and not leather_body.visible,"The source leather torso is hidden under another chest")
	menu.archer.set_armor_pieces({"head":0,"chest":0,"hands":0,"legs":0,"feet":2})
	var base_calf := menu.archer._model.find_child("Ranger_Base_Calf",true,false) as MeshInstance3D
	var leather_boots := menu.archer._model.find_child("Male_Ranger_Feet_Boots",true,false) as MeshInstance3D
	check(base_calf != null and base_calf.visible,"The base calf fills the shin under short sabatons")
	check(leather_boots != null and not leather_boots.visible,"Plate sabatons hide the leather boots independently")
	menu.archer.set_armor_pieces(state.equipped_pieces())
	check(menu.hud.paperdoll_buttons.size() == 10,"The hub renders ten paperdoll slots")
	check(menu.hud.backpack_buttons.size() == 10,"The hub renders ten backpack slots")
	check(menu.hud.stash_buttons.size() == 20,"The hub renders twenty stash slots")
	check(menu.hud.stock_buttons.size() == 28,"The hub renders the whole stock list")
	check(menu.hud.vendor_buttons.size() == 3,"The hub offers three vendors")
	check(menu.hud.paperdoll_buttons[1].item == "armor_mail_chest","The paperdoll shows the stored chest")
	check(menu.hud.paperdoll_buttons[8].item == "sword_arming","The paperdoll shows the main hand")
	var deploy_buttons: Array[Button] = [menu.hud.skirmish_button,menu.hud.host_button,menu.hud.join_button,menu.hud.frontier_button,
		menu.hud.delve_button,menu.hud.delve_host_button,menu.hud.delve_join_button]
	for button in deploy_buttons:
		check(button.visible,"Every deploy action is available from the default screen")
		check(menu.hud.action_panel.get_global_rect().encloses(button.get_global_rect()),"Deploy actions sit inside their panel")
	for first in deploy_buttons.size():
		for second in range(first+1,deploy_buttons.size()):
			check(not deploy_buttons[first].get_global_rect().intersects(deploy_buttons[second].get_global_rect()),"Deploy actions do not overlap each other")
	var action_rect: Rect2 = menu.hud.action_panel.get_global_rect()
	check(is_equal_approx(action_rect.size.x,600.0) and is_equal_approx(action_rect.size.y,306.0),"The deploy panel keeps its authored two-column size")
	var left_column_end: float = maxf(menu.hud.frontier_button.get_global_rect().end.x,menu.hud.host_button.get_global_rect().end.x)
	check(menu.hud.delve_button.get_global_rect().position.x > left_column_end,"The delve column starts clear of the arena column")
	check(action_rect.encloses(menu.hud.delve_host_button.get_global_rect()) and action_rect.encloses(menu.hud.delve_join_button.get_global_rect()),"Both delve host and join actions sit in the right column")
	menu.hud.set_delve_progress(2,false)
	check(menu.hud.delve_button.text.begins_with("RESUME THE DELVE"),"A stored run resumes the delve instead of descending fresh")
	check(menu.hud.delve_button.text.ends_with("WAVE 2"),"The resume label names the stored wave")
	menu.hud.set_delve_progress(3,true)
	check(menu.hud.delve_button.text.ends_with("FINAL CACHE"),"A cleared wave offers the final cache")
	menu.hud.set_delve_progress(0,false)
	check(menu.hud.delve_button.text == "DESCEND THE DELVE","Without a stored run the delve starts fresh")
	var filled := 0
	for button in menu.hud.backpack_buttons:
		if not str(button.item).is_empty():
			filled += 1
	check(filled == state.inventory.size(),"Backpack slots match owned gear")
	var view_rect: Rect2 = menu.get_viewport().get_visible_rect()
	var panels: Array[Panel] = [menu.hud.header_panel,menu.hud.purse_panel,menu.hud.paperdoll_panel,
		menu.hud.backpack_panel,menu.hud.stash_panel,menu.hud.vendor_panel,menu.hud.action_panel]
	for panel in panels:
		check(view_rect.encloses(panel.get_global_rect()),"Every hub panel stays on screen")
	for first in panels.size():
		for second in range(first+1,panels.size()):
			check(not panels[first].get_global_rect().intersects(panels[second].get_global_rect()),"Hub panels do not overlap each other")
	for button in menu.hud.paperdoll_buttons:
		check(menu.hud.paperdoll_panel.get_global_rect().encloses(button.get_global_rect()),"Paperdoll slots sit inside their panel")
	for button in menu.hud.backpack_buttons:
		check(menu.hud.backpack_panel.get_global_rect().encloses(button.get_global_rect()),"Backpack slots sit inside their panel")
	for button in menu.hud.stash_buttons:
		check(menu.hud.stash_panel.get_global_rect().encloses(button.get_global_rect()),"Stash slots sit inside their panel")
	check(menu.hud.backpack_panel.get_global_rect().encloses(menu.hud.floor_scroll.get_global_rect()),"The bottom floor strip sits inside the backpack panel")
	check(menu.hud.backpack_panel.get_global_rect().encloses(menu.hud._floor_label.get_global_rect()),"The floor label sits inside the backpack panel")
	check(menu.hud.vendor_panel.get_global_rect().encloses(menu.hud.stock_scroll.get_global_rect()),"Vendor stock scroll sits inside its panel")
	var visible_stock := 0
	for button in menu.hud.stock_buttons:
		if button.visible:
			visible_stock += 1
			if visible_stock <= 4:
				check(menu.hud.stock_scroll.get_global_rect().grow(2).encloses(button.get_global_rect()),"Visible vendor stock rows sit inside the scroll")
	check(visible_stock == 5,"The Fletcher lists five bows and staves")
	var feet_on_screen: Vector2 = menu.camera.unproject_position(menu.archer.global_position)
	var head_on_screen: Vector2 = menu.camera.unproject_position(menu.archer.global_position+Vector3(0,1.85,0))
	check(view_rect.has_point(feet_on_screen) and view_rect.has_point(head_on_screen),"The ranger is framed on screen")
	check(head_on_screen.x > menu.hud.paperdoll_panel.get_global_rect().end.x,"The ranger stands clear of the paperdoll panel")
	check(head_on_screen.x < menu.hud.vendor_panel.get_global_rect().position.x,"The ranger stands clear of the vendor panel")
	check(feet_on_screen.y < menu.hud.stash_panel.get_global_rect().position.y,"The stash panel leaves the ranger's feet visible")
	var status_rect: Rect2 = menu.hud._status.get_global_rect()
	check(view_rect.encloses(status_rect),"The status line stays on screen")
	check(not status_rect.intersects(menu.hud.header_panel.get_global_rect()),"The status line clears the title panel")
	check(not status_rect.intersects(menu.hud.purse_panel.get_global_rect()),"The status line clears the purse panel")

	menu.hud.vendor_buttons[2].pressed.emit()
	var quartermaster_stock := 0
	var quartermaster_rows := 0
	for button in menu.hud.stock_buttons:
		if button.visible:
			quartermaster_stock += 1
			quartermaster_rows += 1
			if quartermaster_rows <= 4:
				check(menu.hud.stock_scroll.get_global_rect().grow(2).encloses(button.get_global_rect()),"Quartermaster rows sit inside the scroll")
	check(quartermaster_stock == 27,"The Quartermaster lists all twenty-seven pieces")
	menu.hud.vendor_buttons[0].pressed.emit()
	menu.hud.stock_buttons[2].pressed.emit()
	check(menu.hud.buy_button.visible,"Selecting vendor stock reveals the purchase action")
	check(menu.hud.buy_button.disabled,"The longbow is disabled while the purse is short")
	state.add_credits(500)
	menu.hud.stock_buttons[1].pressed.emit()
	check(not menu.hud.buy_button.disabled,"Credits re-enable the purchase action")
	var stock_before: int = state.inventory.size()
	menu.hud.buy_button.pressed.emit()
	check(state.inventory.size() == stock_before+1,"The hub purchase adds the selected item")
	check(state.inventory[-1] == "bow_recurve","The hub buys the selected stock item")
	var recurve_index: int = state.inventory.find("bow_recurve")
	check(recurve_index >= 0,"Bought gear appears in the backpack")

	menu.hud.backpack_buttons[recurve_index].right_clicked.emit("backpack",recurve_index,"","bow_recurve")
	check(state.equipped_id("main") == "bow_recurve","Right-click equips a backpack bow into the main hand")
	check(state.owned_in_inventory("bow_recurve") == 0,"The equipped bow leaves the backpack")
	check(menu.archer.bow_index == 1,"The preview follows a right-click equip")
	check(not menu.archer.shield_equipped,"A bow stows the shield")
	check(state.owned_in_inventory("sword_arming") == 1,"The displaced sword returns to the backpack")
	check(state.owned_in_inventory("shield_kite") == 1,"The displaced shield returns to the backpack")

	var arming_index: int = state.inventory.find("sword_arming")
	check(arming_index >= 0,"The displaced sword is listed in the backpack")
	menu.hud.backpack_buttons[arming_index].pressed.emit()
	check(not menu.hud.equip_button.disabled,"A fresh sword can be equipped")
	menu.hud.equip_button.pressed.emit()
	check(state.equipped_id("main") == "sword_arming","Hub EQUIP updates the stored main hand")
	check(menu.archer.sword_index == 1,"Hub EQUIP updates the rendered sword")

	var kite_index: int = state.inventory.find("shield_kite")
	check(kite_index >= 0,"The displaced shield is listed in the backpack")
	menu.hud.backpack_buttons[kite_index].right_clicked.emit("backpack",kite_index,"","shield_kite")
	check(state.equipped_id("off") == "shield_kite","Right-click routes a shield to the off hand")
	check(menu.archer.shield_equipped,"The preview raises the equipped shield")

	var stash_index: int = state.inventory.find("bow_recurve")
	check(stash_index >= 0,"The displaced bow is in the backpack")
	menu.hud.backpack_buttons[stash_index].pressed.emit()
	check(not menu.hud.move_button.disabled,"Unequipped gear can be stored")
	menu.hud.move_button.pressed.emit()
	check(state.stash.has("bow_recurve"),"Hub storage moves the item to the stash")
	menu.hud.stash_buttons[0].pressed.emit()
	var credits_before: int = state.credits
	menu.hud.sell_button.pressed.emit()
	check(state.stash.is_empty(),"Hub selling removes the stashed item")
	check(state.credits > credits_before,"Hub selling pays credits")

	check(state.inventory.has("sword_short"),"The starter sword is still in the backpack")
	var floor_item: String = state.inventory[0]
	menu.hud._on_world_dropped({"area":"backpack","index":0,"item":floor_item})
	check(state.floor_items.size() == 1 and state.floor_items[0] == floor_item,"Dropping over the viewport drops the item at the ranger's feet")
	check(menu.hud.floor_buttons.size() == 1,"The floor strip lists the dropped item")
	if menu.hud.floor_buttons.size() == 1:
		check(menu.hud.floor_buttons[0].item == floor_item,"The floor strip names the dropped gear")
		menu.hud.floor_buttons[0].pressed.emit()
		menu.hud.equip_button.pressed.emit()
		check(state.floor_items.is_empty(),"Picking up clears the floor")
		check(state.inventory.has(floor_item),"Picked-up gear returns to the backpack")

	for panel in panels:
		for child in panel.get_children():
			if child is Label:
				var inside := panel.get_global_rect().encloses(child.get_global_rect())
				if not inside:
					print("HUB_LABEL_OUT panel=",panel.name," text=",child.text," label=",child.get_global_rect()," panel_rect=",panel.get_global_rect())
				check(inside,"Panel labels stay inside their panel")
	check(menu.hud._vendor_tag.get_visible_line_count() == menu.hud._vendor_tag.get_line_count(),"Vendor copy is not clipped")
	check(menu.hud._detail_text.get_visible_line_count() == menu.hud._detail_text.get_line_count(),"Item copy is not clipped")
	menu.hud.host_button.pressed.emit()
	await process_frame
	check(menu.hud.is_form_open(),"The host action opens the hosting form")
	var modal: Rect2 = menu.hud._modal_panel.get_global_rect()
	check(view_rect.encloses(modal),"The host form fits on screen")
	check(modal.encloses(menu.hud._name_input.get_global_rect()),"The host name field fits the form")
	check(modal.encloses(menu.hud._port_input.get_global_rect()),"The host port field fits the form")
	check(modal.encloses(menu.hud._confirm_button.get_global_rect()),"The host confirm button fits the form")
	check(not menu.hud._address_input.visible,"The host form hides the join address field")
	menu.hud.close_form()
	menu.hud.join_button.pressed.emit()
	await process_frame
	check(menu.hud.is_form_open(),"The join action opens the join form")
	check(view_rect.encloses(menu.hud._modal_panel.get_global_rect()),"The join form fits on screen")
	check(menu.hud._address_input.visible,"The join form shows the host address field")
	check(menu.hud._modal_panel.get_global_rect().encloses(menu.hud._address_input.get_global_rect()),"The join address field fits the form")
	check(menu.hud._modal_panel.get_global_rect().encloses(menu.hud._confirm_button.get_global_rect()),"The join confirm button fits the form")
	menu.hud.close_form()
	menu.hud.delve_host_button.pressed.emit()
	await process_frame
	check(menu.hud.is_form_open(),"The delve host action opens the delve hosting form")
	check(menu.hud._modal_kind == "delve_host","The delve host form is the delve host kind")
	var delve_modal: Rect2 = menu.hud._modal_panel.get_global_rect()
	check(view_rect.encloses(delve_modal),"The delve host form fits on screen")
	check(delve_modal.encloses(menu.hud._name_input.get_global_rect()),"The delve host name field fits the form")
	check(delve_modal.encloses(menu.hud._port_input.get_global_rect()),"The delve host port field fits the form")
	check(delve_modal.encloses(menu.hud._confirm_button.get_global_rect()),"The delve host confirm button fits the form")
	check(delve_modal.encloses(menu.hud._cancel_button.get_global_rect()),"The delve host cancel button fits the form")
	check(not menu.hud._address_input.visible,"The delve host form hides the join address field")
	check(menu.hud._confirm_button.text == "HOST DELVE","The delve host form confirms a delve")
	menu.hud.close_form()
	check(not menu.hud.is_form_open(),"The delve host form closes")
	menu.hud.delve_join_button.pressed.emit()
	await process_frame
	check(menu.hud.is_form_open(),"The delve join action opens the delve join form")
	check(menu.hud._modal_kind == "delve_join","The delve join form is the delve join kind")
	check(view_rect.encloses(menu.hud._modal_panel.get_global_rect()),"The delve join form fits on screen")
	check(menu.hud._address_input.visible,"The delve join form shows the host address field")
	check(menu.hud._modal_panel.get_global_rect().encloses(menu.hud._name_input.get_global_rect()),"The delve join name field fits the form")
	check(menu.hud._modal_panel.get_global_rect().encloses(menu.hud._address_input.get_global_rect()),"The delve join address field fits the form")
	check(menu.hud._modal_panel.get_global_rect().encloses(menu.hud._port_input.get_global_rect()),"The delve join port field fits the form")
	check(menu.hud._modal_panel.get_global_rect().encloses(menu.hud._confirm_button.get_global_rect()),"The delve join confirm button fits the form")
	check(menu.hud._modal_panel.get_global_rect().encloses(menu.hud._cancel_button.get_global_rect()),"The delve join cancel button fits the form")
	check(menu.hud._confirm_button.text == "JOIN DELVE","The delve join form confirms a delve")
	menu.hud.close_form()
	check(not menu.hud.is_form_open(),"The delve join form closes")
	menu.queue_free()
	await process_frame

func _test_frontier() -> void:
	state.reset()
	state.equipped = {
		"head":"armor_mail_head","chest":"armor_mail_chest","hands":"armor_mail_hands",
		"legs":"armor_mail_legs","feet":"armor_mail_feet",
		"neck":"","ring1":"","ring2":"","main":"sword_great","off":""
	}
	state.credits = 480
	state.save_state()
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.5).timeout
	check(game.archer.sword_index == 2,"The frontier starts with the hub greatsword")
	check(game.archer.bow_index == 0,"A greatsword main hand reports the short bow index")
	check(game.archer.armor_piece("head") == 1,"The frontier starts with the hub mail hood")
	check(game.archer.armor_piece("chest") == 1,"The frontier starts with the hub mail chest")
	check(is_equal_approx(game.archer.armor_reduction(),0.15),"The full mail kit grants 15% guard")
	check(not game.archer.shield_equipped,"An empty off hand starts with the shield stowed")
	check(game.gold == 480,"The frontier starts with the hub purse")
	var before: int = state.credits
	game._award_gold(7)
	check(game.gold == 487,"Frontier rewards increase the session purse")
	check(state.credits == before+7,"Frontier rewards persist to the hub purse")
	game.queue_free()
	await process_frame

func _test_arena() -> void:
	state.reset()
	state.equipped = {
		"head":"armor_mail_head","chest":"armor_mail_chest","hands":"armor_mail_hands",
		"legs":"armor_mail_legs","feet":"armor_mail_feet",
		"neck":"","ring1":"","ring2":"","main":"sword_great","off":""
	}
	state.credits = 480
	state.save_state()
	session.clear()
	session.arm_arena("host","127.0.0.1",7811,"Hub regression")
	var arena = load("res://arena.tscn").instantiate()
	root.add_child(arena)
	var deadline := Time.get_ticks_msec() + 5000
	while arena.network_role != "host" and Time.get_ticks_msec() < deadline:
		await process_frame
	check(arena.network_role == "host","A hub host request starts an arena server")
	check(arena.local_slot == 0,"The hub host owns the first seat")
	check(arena.actors[0].rig.sword_index == 2,"The arena host starts with the hub greatsword")
	check(arena.actors[0].rig.bow_index == 0,"A greatsword main hand reports the short bow index")
	check(arena.actors[0].rig.armor_piece("chest") == 1,"The arena host starts with the hub mail chest")
	check(is_equal_approx(arena.actors[0].rig.armor_reduction(),0.15),"The arena host starts with the full mail guard")
	await process_frame
	await process_frame
	arena.hud.armor_buttons[1].pressed.emit()
	await process_frame
	check(arena.actors[0].rig.armor_piece("chest") == 2,"The arena slot button cycles only the chest")
	check(arena.actors[0].rig.armor_piece("head") == 1,"The other armor slots keep their mail")
	var plate_pieces := {"head":2,"chest":2,"hands":2,"legs":2,"feet":2}
	arena._apply_loadout(1,{"main":"sword_arming","off":"shield_kite","armor":ArmorData.pack(plate_pieces)})
	check(arena.actors[1].rig.bow_index == 0,"A validated client loadout reports the short bow index")
	check(arena.actors[1].rig.sword_index == 1,"The client's main hand applies to its seat")
	check(arena.actors[1].rig.shield_equipped,"The client's off hand raises the shield")
	check(arena.actors[1].rig.armor_piece("chest") == 2,"Armor selection applies to the hosted seat")
	check(is_equal_approx(arena.actors[1].rig.armor_reduction(),0.30),"A full plate loadout grants 30% guard")
	arena._apply_loadout(1,{"main":"armor_mail_chest","off":"not_a_real_item","armor":-1})
	check(arena.actors[1].rig.sword_index == 1,"An invalid main hand is ignored")
	check(arena.actors[1].rig.shield_equipped,"An invalid off hand keeps the shield")
	check(arena.actors[1].rig.armor_piece("chest") == 2,"An invalid armor payload is ignored")
	arena._apply_loadout(1,{"bow":9,"sword":"greatsword","armor":-1})
	check(arena.actors[1].rig.bow_index == 0,"An invalid bow index is ignored")
	check(arena.actors[1].rig.sword_index == 1,"An invalid sword type is ignored")
	check(arena.actors[1].rig.armor_piece("chest") == 2,"An invalid index payload is ignored")
	arena._apply_loadout(9,{"main":"sword_short","off":"","armor":0})
	check(arena.actors[1].rig.sword_index == 1,"An out-of-range seat is ignored")
	arena._apply_loadout(1,{"main":"","off":"","armor":ArmorData.pack(plate_pieces)})
	check(arena.actors[1].rig.weapon == "none","Explicitly empty paperdoll hands apply as unarmed")
	arena.leave_game()
	check(arena.network_role == "offline","Leaving the arena returns to the lobby state")
	arena.queue_free()
	await process_frame
