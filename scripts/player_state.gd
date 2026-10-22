extends Node
## Persistent out-of-raid state: the ranger's inventory, stash, purse and equipped kit.
## The hub owns the authoritative copy; matches only read the initial loadout.

signal changed

const INVENTORY_CAPACITY := 10
const STASH_CAPACITY := 20
const STARTING_CREDITS := 200
const SELL_RATE := 0.6
const SAVE_VERSION := 1
const DEFAULT_SAVE_PATH := "user://player_state.json"

const ITEMS := {
	"bow_short": {"name":"Shortbow", "short":"Shortbow", "kind":"bow", "index":0, "price":120,
		"summary":"Quick ashwood scout bow",
		"detail":"30 damage at full draw / 1.0 s draw / light and fast"},
	"bow_recurve": {"name":"Recurve", "short":"Recurve", "kind":"bow", "index":1, "price":220,
		"summary":"Balanced horn-and-yew recurve",
		"detail":"38 damage at full draw / 2.0 s draw / all-round draw"},
	"bow_long": {"name":"Longbow", "short":"Longbow", "kind":"bow", "index":2, "price":360,
		"summary":"Heavy heartwood war bow",
		"detail":"50 damage at full draw / 3.0 s draw / slow but crushing"},
	"sword_short": {"name":"Shortsword", "short":"Shortswd", "kind":"sword", "index":0, "price":110,
		"summary":"A compact camp blade",
		"detail":"30 damage / 1.0 s swing / 1.8 m reach"},
	"sword_arming": {"name":"Arming sword", "short":"Arming", "kind":"sword", "index":1, "price":195,
		"summary":"A soldier's balanced sidearm",
		"detail":"38 damage / 2.0 s swing / 2.1 m reach"},
	"sword_great": {"name":"Greatsword", "short":"Greatswd", "kind":"sword", "index":2, "price":340,
		"summary":"A deliberate two-handed cut",
		"detail":"50 damage / 3.0 s swing / 2.5 m reach"},
	"armor_leather": {"name":"Ranger leather", "short":"Leather", "kind":"armor", "index":0, "price":55,
		"summary":"The road-worn ranger outfit",
		"detail":"No damage reduction / full mobility"},
	"armor_mail": {"name":"Sentinel mail", "short":"Mail", "kind":"armor", "index":1, "price":180,
		"summary":"Riveted rings under a wool coat",
		"detail":"15% less incoming damage / hung from the old watch"},
	"armor_plate": {"name":"Warden plate", "short":"Plate", "kind":"armor", "index":2, "price":320,
		"summary":"The wardens' blackened steel",
		"detail":"30% less incoming damage / heavy frontier plate"},
}

const VENDORS := [
	{"name":"Fletcher Orla", "tag":"FLETCHER", "line":"Bows, strings and staves.", "stock":["bow_short","bow_recurve","bow_long"]},
	{"name":"Smith Brann", "tag":"SMITH", "line":"Swords balanced on the anvil.", "stock":["sword_short","sword_arming","sword_great"]},
	{"name":"Quartermaster Vey", "tag":"STORE", "line":"Armor for the long patrol.", "stock":["armor_leather","armor_mail","armor_plate"]},
]

const DEFAULTS := {"bow":"bow_short", "sword":"sword_short", "armor":"armor_leather"}

var credits := STARTING_CREDITS
var inventory: Array[String] = []
var stash: Array[String] = []
var equipped := DEFAULTS.duplicate()
var save_path := DEFAULT_SAVE_PATH

func _ready() -> void:
	# Script-mode regressions must not read or overwrite a player's real purse.
	if DisplayServer.get_name() == "headless" and OS.get_cmdline_args().has("--script"):
		save_path = "user://player_state_test.json"
		reset(false)
		return
	load_state()

func _item(id: String) -> Dictionary:
	return ITEMS.get(id, {})

func item_definition(id: String) -> Dictionary:
	return _item(id)

func item_name(id: String) -> String:
	return str(_item(id).get("name", id))

func item_short(id: String) -> String:
	return str(_item(id).get("short", id))

func item_kind(id: String) -> String:
	return str(_item(id).get("kind", ""))

func item_detail(id: String) -> String:
	return str(_item(id).get("detail", ""))

func item_summary(id: String) -> String:
	return str(_item(id).get("summary", ""))

func item_price(id: String) -> int:
	return int(_item(id).get("price", 0))

func sell_value(id: String) -> int:
	return int(floor(float(item_price(id)) * SELL_RATE))

func inventory_full() -> bool:
	return inventory.size() >= INVENTORY_CAPACITY

func stash_full() -> bool:
	return stash.size() >= STASH_CAPACITY

func equipped_id(kind: String) -> String:
	return str(equipped.get(kind, DEFAULTS.get(kind, "")))

func equipped_index(kind: String) -> int:
	return int(_item(equipped_id(kind)).get("index", 0))

func is_equipped(id: String) -> bool:
	return id == equipped_id(item_kind(id))

func owned_in_inventory(id: String) -> int:
	var count := 0
	for entry in inventory:
		if entry == id:
			count += 1
	return count

func owned_in_stash(id: String) -> int:
	var count := 0
	for entry in stash:
		if entry == id:
			count += 1
	return count

func reset(persist: bool = true) -> void:
	credits = STARTING_CREDITS
	inventory = ["bow_short","sword_short","armor_leather"]
	stash = []
	equipped = DEFAULTS.duplicate()
	changed.emit()
	if persist:
		save_state()

func buy(item_id: String) -> Dictionary:
	if not ITEMS.has(item_id):
		return {"ok":false, "message":"That item is not in any vendor's stock."}
	if inventory_full():
		return {"ok":false, "message":"Inventory full (%d / %d). Move something to the stash first." % [inventory.size(), INVENTORY_CAPACITY]}
	var price := item_price(item_id)
	if credits < price:
		return {"ok":false, "message":"Not enough credits. %s costs %d; you carry %d." % [item_name(item_id), price, credits]}
	credits -= price
	inventory.append(item_id)
	changed.emit()
	save_state()
	return {"ok":true, "index":inventory.size()-1, "message":"Bought %s for %d credits." % [item_name(item_id), price]}

func sell(location: String, index: int) -> Dictionary:
	var list := _list_for(location)
	if list.is_empty():
		return {"ok":false, "message":"That slot is empty."}
	if index < 0 or index >= list.size():
		return {"ok":false, "message":"That slot is empty."}
	var item_id := str(list[index])
	if location == "inventory" and _is_last_equipped_copy(item_id):
		return {"ok":false, "message":"%s is equipped. Equip another %s before selling it." % [item_name(item_id), item_kind(item_id)]}
	var value := sell_value(item_id)
	list.remove_at(index)
	credits += value
	changed.emit()
	save_state()
	return {"ok":true, "value":value, "message":"Sold %s for %d credits." % [item_name(item_id), value]}

func move_to_stash(index: int) -> Dictionary:
	if index < 0 or index >= inventory.size():
		return {"ok":false, "message":"That slot is empty."}
	var item_id := inventory[index]
	if stash_full():
		return {"ok":false, "message":"Stash full (%d / %d). Sell something first." % [stash.size(), STASH_CAPACITY]}
	if _is_last_equipped_copy(item_id):
		return {"ok":false, "message":"%s is equipped. Equip another %s first." % [item_name(item_id), item_kind(item_id)]}
	inventory.remove_at(index)
	stash.append(item_id)
	changed.emit()
	save_state()
	return {"ok":true, "message":"Stored %s in the stash." % item_name(item_id)}

func move_to_inventory(index: int) -> Dictionary:
	if index < 0 or index >= stash.size():
		return {"ok":false, "message":"That stash slot is empty."}
	if inventory_full():
		return {"ok":false, "message":"Inventory full (%d / %d). Store or sell something first." % [inventory.size(), INVENTORY_CAPACITY]}
	var item_id := stash[index]
	stash.remove_at(index)
	inventory.append(item_id)
	changed.emit()
	save_state()
	return {"ok":true, "message":"Took %s from the stash." % item_name(item_id)}

func equip(inventory_index: int) -> Dictionary:
	if inventory_index < 0 or inventory_index >= inventory.size():
		return {"ok":false, "message":"Choose a piece of gear in your inventory."}
	var item_id := inventory[inventory_index]
	var kind := item_kind(item_id)
	if kind.is_empty():
		return {"ok":false, "message":"That item cannot be equipped."}
	equipped[kind] = item_id
	changed.emit()
	save_state()
	return {"ok":true, "message":"Equipped %s." % item_name(item_id)}

func add_credits(amount: int) -> void:
	if amount == 0:
		return
	credits = maxi(0, credits + amount)
	changed.emit()
	save_state()

func _list_for(location: String) -> Array[String]:
	if location == "inventory":
		return inventory
	if location == "stash":
		return stash
	return []

func _is_last_equipped_copy(item_id: String) -> bool:
	if not is_equipped(item_id):
		return false
	return owned_in_inventory(item_id) <= 1

func save_state() -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write player state to %s" % save_path)
		return
	file.store_string(JSON.stringify({
		"version":SAVE_VERSION,
		"credits":credits,
		"inventory":inventory,
		"stash":stash,
		"equipped":equipped,
	}))
	file.close()

func load_state() -> void:
	if not FileAccess.file_exists(save_path):
		reset(false)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Ignoring unreadable player state at %s" % save_path)
		reset(false)
		return
	var data: Dictionary = parsed
	credits = maxi(0, int(data.get("credits", STARTING_CREDITS)))
	inventory.clear()
	for entry: Variant in data.get("inventory", []):
		var item_id := str(entry)
		if ITEMS.has(item_id) and inventory.size() < INVENTORY_CAPACITY:
			inventory.append(item_id)
	stash.clear()
	for entry: Variant in data.get("stash", []):
		var item_id := str(entry)
		if ITEMS.has(item_id) and stash.size() < STASH_CAPACITY:
			stash.append(item_id)
	var saved_equipped: Variant = data.get("equipped", {})
	equipped = DEFAULTS.duplicate()
	if typeof(saved_equipped) == TYPE_DICTIONARY:
		for kind: String in DEFAULTS:
			var item_id := str(saved_equipped.get(kind, ""))
			if ITEMS.has(item_id) and item_kind(item_id) == kind:
				equipped[kind] = item_id
	changed.emit()
