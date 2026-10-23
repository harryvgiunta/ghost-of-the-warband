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
	check(state.INVENTORY_CAPACITY == 10,"Inventory holds ten slots")
	check(state.STASH_CAPACITY == 20,"Stash holds twenty slots")
	check(state.inventory.size() == 7,"Starter kit fills seven inventory slots")
	check(state.stash.is_empty(),"Stash starts empty")
	check(state.credits == StateScript.STARTING_CREDITS,"Starting purse is the authoring constant")
	check(state.equipped_index("bow") == 0,"Starter shortbow is equipped")
	check(state.equipped_index("sword") == 0,"Starter shortsword is equipped")
	for armor_slot in ArmorData.SLOTS:
		check(state.equipped_index(armor_slot) == 0,"Starter leather %s is equipped" % armor_slot)
	check(state.owned_in_inventory("armor_leather_chest") == 1,"Starter leather chest is owned")
	check(state.owned_in_inventory("bow_short") == 1,"Starter bow is owned in the inventory")

	var credits_before: int = state.credits
	var result: Dictionary = state.buy("bow_long")
	check(not bool(result.ok),"A longbow is unaffordable with the starting purse")
	check(state.credits == credits_before,"A rejected purchase spends nothing")
	check(not state.inventory.has("bow_long"),"A rejected purchase stores nothing")

	state.credits = 2000
	result = state.buy("bow_long")
	check(bool(result.ok),"An affordable purchase succeeds")
	check(state.inventory[-1] == "bow_long","Purchases append to the inventory")
	check(state.credits == 1640,"Purchase spends the listed price")
	var long_index: int = state.inventory.size()-1
	check(bool(state.equip(long_index).ok),"Owned gear can be equipped")
	check(state.equipped_index("bow") == 2,"Equipping a longbow drives the gameplay bow index")
	check(state.is_equipped("bow_long"),"Equipped state is queryable")
	check(not bool(state.sell("inventory",long_index).ok),"The last copy of equipped gear cannot be sold")
	check(not bool(state.move_to_stash(long_index).ok),"The last copy of equipped gear cannot be stashed")

	result = state.buy("bow_long")
	check(bool(result.ok),"Duplicate gear can be bought")
	var duplicate_index: int = state.inventory.size()-1
	credits_before = state.credits
	result = state.sell("inventory",duplicate_index)
	check(bool(result.ok),"A duplicate copy sells even while that item type is equipped")
	check(state.credits == credits_before + state.sell_value("bow_long"),"Selling pays the sell rate")
	check(state.owned_in_inventory("bow_long") == 1,"Selling removes one copy only")

	var starter_index: int = state.inventory.find("bow_short")
	check(starter_index >= 0,"The unequipped starter bow is still present")
	check(bool(state.move_to_stash(starter_index).ok),"Unequipped gear moves to the stash")
	check(state.stash.size() == 1,"Stash receives the moved item")
	check(bool(state.move_to_inventory(0).ok),"Stashed gear returns to the inventory")
	check(state.stash.is_empty(),"Returning gear empties the stash slot")

	# Per-slot equipping: a mail chest must not replace the leather hood.
	state.credits = 2000
	check(bool(state.buy("armor_mail_chest").ok),"A single armor piece can be bought")
	var mail_chest: int = state.inventory.find("armor_mail_chest")
	check(bool(state.equip(mail_chest).ok),"A single armor piece can be equipped")
	check(state.equipped_index("chest") == 1,"The mail chest occupies only the chest slot")
	check(state.equipped_index("head") == 0,"The leather hood remains equipped")
	check(state.is_equipped("armor_mail_chest"),"The mixed armor piece is queryable")
	check(is_equal_approx(state.armor_reduction(),0.05),"Only the mail chest contributes guard")

	state.credits = 100000
	while not state.inventory_full():
		check(bool(state.buy("armor_leather").ok),"Buying fills the inventory")
	check(state.inventory.size() == StateScript.INVENTORY_CAPACITY,"Inventory stops at ten")
	result = state.buy("armor_leather")
	check(not bool(result.ok),"A full inventory rejects purchases")
	check(state.inventory.size() == StateScript.INVENTORY_CAPACITY,"A rejected purchase grows nothing")

	while not state.stash_full():
		if state.inventory_full():
			var moved := false
			for index in state.inventory.size():
				if bool(state.move_to_stash(index).ok):
					moved = true
					break
			check(moved,"A full inventory can always drain unequipped gear to the stash")
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
	state.save_state()
	var loaded = StateScript.new()
	loaded.save_path = TEST_SAVE
	loaded.load_state()
	check(loaded.credits == state.credits,"Credits survive a reload")
	check(PackedStringArray(loaded.inventory) == PackedStringArray(state.inventory),"Inventory survives a reload")
	check(PackedStringArray(loaded.stash) == PackedStringArray(state.stash),"Stash survives a reload")
	for kind in StateScript.DEFAULTS:
		check(loaded.equipped_id(kind) == state.equipped_id(kind),"Equipped %s survives a reload" % kind)
	loaded.free()
	# A version-1 save stored one whole-set armor id; it must migrate to five slots.
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
		check(legacy.equipped_id(slot) == "armor_mail","Version-1 armor migrates to the %s slot" % slot)
	check(legacy.equipped_index("chest") == 1,"Migrated mail preserves its set index")
	check(legacy.is_equipped("armor_mail"),"Migrated whole-set mail is queryable")
	legacy.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(v1_path))

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
	state.equipped = {"bow":"bow_long","sword":"sword_great",
		"head":"armor_mail_head","chest":"armor_mail_chest","hands":"armor_mail_hands",
		"legs":"armor_mail_legs","feet":"armor_mail_feet"}
	state.save_state()
	var menu = load("res://menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	check(str(ProjectSettings.get_setting("application/run/main_scene")) == "res://menu.tscn","The hub is the game's default screen")
	check(menu.state == state,"The hub uses the persistent PlayerState service")
	check(menu.archer != null and menu.archer.is_visible_in_tree(),"The ranger stands in the default screen")
	check(menu.camera != null and menu.camera.current,"The hub frames the ranger with an active camera")
	check(menu.archer.bow_index == 2,"Preview equips the stored longbow")
	check(menu.archer.sword_index == 2,"Preview equips the stored greatsword")
	check(menu.archer.armor_piece("head") == 1,"Preview equips the stored mail hood")
	check(menu.archer.armor_piece("chest") == 1,"Preview equips the stored mail chest")
	check(menu.archer.armor_piece("feet") == 1,"Preview equips the stored mail sabatons")
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
	check(menu.hud.inventory_buttons.size() == 10,"The hub renders ten inventory slots")
	check(menu.hud.stash_buttons.size() == 20,"The hub renders twenty stash slots")
	check(menu.hud.vendor_buttons.size() == 3,"The hub offers three vendors")
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
	var enabled := 0
	for button in menu.hud.inventory_buttons:
		if not button.disabled:
			enabled += 1
	check(enabled == state.inventory.size(),"Inventory slots match owned gear")
	var view_rect: Rect2 = menu.get_viewport().get_visible_rect()
	var panels: Array[Panel] = [menu.hud.header_panel,menu.hud.purse_panel,menu.hud.inventory_panel,menu.hud.stash_panel,menu.hud.vendor_panel,menu.hud.action_panel]
	for panel in panels:
		check(view_rect.encloses(panel.get_global_rect()),"Every hub panel stays on screen")
	for first in panels.size():
		for second in range(first+1,panels.size()):
			check(not panels[first].get_global_rect().intersects(panels[second].get_global_rect()),"Hub panels do not overlap each other")
	for button in menu.hud.inventory_buttons:
		check(menu.hud.inventory_panel.get_global_rect().encloses(button.get_global_rect()),"Inventory slots sit inside their panel")
	for button in menu.hud.stash_buttons:
		check(menu.hud.stash_panel.get_global_rect().encloses(button.get_global_rect()),"Stash slots sit inside their panel")
	check(menu.hud.vendor_panel.get_global_rect().encloses(menu.hud.stock_scroll.get_global_rect()),"Vendor stock scroll sits inside its panel")
	var visible_stock := 0
	for button in menu.hud.stock_buttons:
		if button.visible:
			visible_stock += 1
			if visible_stock <= 4:
				check(menu.hud.stock_scroll.get_global_rect().grow(2).encloses(button.get_global_rect()),"Visible vendor stock rows sit inside the scroll")
	check(visible_stock == 3,"The Fletcher lists three bows")
	var feet_on_screen: Vector2 = menu.camera.unproject_position(menu.archer.global_position)
	var head_on_screen: Vector2 = menu.camera.unproject_position(menu.archer.global_position+Vector3(0,1.85,0))
	check(view_rect.has_point(feet_on_screen) and view_rect.has_point(head_on_screen),"The ranger is framed on screen")
	check(head_on_screen.x > menu.hud.inventory_panel.get_global_rect().end.x,"The ranger stands clear of the inventory panel")
	check(head_on_screen.x < menu.hud.vendor_panel.get_global_rect().position.x,"The ranger stands clear of the vendor panel")
	check(feet_on_screen.y < menu.hud.stash_panel.get_global_rect().position.y,"The stash panel leaves the ranger's feet visible")
	var status_rect: Rect2 = menu.hud._status.get_global_rect()
	check(view_rect.encloses(status_rect),"The status line stays on screen")
	check(not status_rect.intersects(menu.hud.header_panel.get_global_rect()),"The status line clears the title panel")
	check(not status_rect.intersects(menu.hud.purse_panel.get_global_rect()),"The status line clears the purse panel")

	menu.hud.vendor_buttons[2].pressed.emit()
	var quartermaster_stock := 0
	for button in menu.hud.stock_buttons:
		if button.visible:
			quartermaster_stock += 1
	check(quartermaster_stock == 20,"The Quartermaster lists all twenty armor pieces")
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
	check(recurve_index >= 0,"Bought gear appears in the inventory")
	menu.hud.inventory_buttons[recurve_index].pressed.emit()
	check(not menu.hud.equip_button.disabled,"A fresh bow can be equipped")
	menu.hud.equip_button.pressed.emit()
	check(state.is_equipped("bow_recurve"),"Hub equip updates the stored kit")
	check(menu.archer.bow_index == 1,"Hub equip updates the rendered ranger")

	var sword_index: int = state.inventory.find("sword_short")
	check(sword_index >= 0,"The unequipped starter sword is listed")
	menu.hud.inventory_buttons[sword_index].pressed.emit()
	check(not menu.hud.move_button.disabled,"Unequipped gear can be stored")
	menu.hud.move_button.pressed.emit()
	check(state.stash.has("sword_short"),"Hub storage moves the item to the stash")
	menu.hud.stash_buttons[0].pressed.emit()
	var credits_before: int = state.credits
	menu.hud.sell_button.pressed.emit()
	check(state.stash.is_empty(),"Hub selling removes the stashed item")
	check(state.credits > credits_before,"Hub selling pays credits")
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
	state.equipped = {"bow":"bow_long","sword":"sword_great",
		"head":"armor_mail_head","chest":"armor_mail_chest","hands":"armor_mail_hands",
		"legs":"armor_mail_legs","feet":"armor_mail_feet"}
	state.credits = 480
	state.save_state()
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.5).timeout
	check(game.archer.bow_index == 2,"The frontier starts with the hub longbow")
	check(game.archer.sword_index == 2,"The frontier starts with the hub greatsword")
	check(game.archer.armor_piece("head") == 1,"The frontier starts with the hub mail hood")
	check(game.archer.armor_piece("chest") == 1,"The frontier starts with the hub mail chest")
	check(is_equal_approx(game.archer.armor_reduction(),0.15),"The full mail kit grants 15% guard")
	check(game.gold == 480,"The frontier starts with the hub purse")
	var before: int = state.credits
	game._award_gold(7)
	check(game.gold == 487,"Frontier rewards increase the session purse")
	check(state.credits == before+7,"Frontier rewards persist to the hub purse")
	game.queue_free()
	await process_frame

func _test_arena() -> void:
	state.reset()
	state.equipped = {"bow":"bow_long","sword":"sword_great",
		"head":"armor_mail_head","chest":"armor_mail_chest","hands":"armor_mail_hands",
		"legs":"armor_mail_legs","feet":"armor_mail_feet"}
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
	check(arena.actors[0].rig.bow_index == 2,"The arena host starts with the hub longbow")
	check(arena.actors[0].rig.sword_index == 2,"The arena host starts with the hub greatsword")
	check(arena.actors[0].rig.armor_piece("chest") == 1,"The arena host starts with the hub mail chest")
	check(is_equal_approx(arena.actors[0].rig.armor_reduction(),0.15),"The arena host starts with the full mail guard")
	await process_frame
	arena.hud.armor_buttons[1].pressed.emit()
	await process_frame
	check(arena.actors[0].rig.armor_piece("chest") == 2,"The arena slot button cycles only the chest")
	check(arena.actors[0].rig.armor_piece("head") == 1,"The other armor slots keep their mail")
	arena._apply_loadout(1,{"bow":2,"sword":0,"armor":ArmorData.pack({"head":2,"chest":2,"hands":2,"legs":2,"feet":2})})
	check(arena.actors[1].rig.bow_index == 2,"A validated client loadout applies to its seat")
	check(arena.actors[1].rig.sword_index == 0,"The whole validated client kit applies")
	check(arena.actors[1].rig.armor_piece("chest") == 2,"Armor selection applies to the hosted seat")
	check(is_equal_approx(arena.actors[1].rig.armor_reduction(),0.30),"A full plate loadout grants 30% guard")
	arena._apply_loadout(1,{"bow":9,"sword":"greatsword","armor":-1})
	check(arena.actors[1].rig.bow_index == 2,"An invalid bow index is ignored")
	check(arena.actors[1].rig.sword_index == 0,"An invalid sword type is ignored")
	check(arena.actors[1].rig.armor_piece("chest") == 2,"An invalid armor payload is ignored")
	arena.leave_game()
	check(arena.network_role == "offline","Leaving the arena returns to the lobby state")
	arena.queue_free()
	await process_frame
