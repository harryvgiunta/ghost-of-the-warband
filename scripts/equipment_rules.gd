extends RefCounted
## Pure equipment vocabulary for the warband's ten equipment slots: the slot list,
## the category rules and the auto-slot routing. Nothing here touches a roster or a
## stash - the paperdoll and the loot ask what a piece may wear, and commit the
## move itself.

const SLOTS := ["head","chest","hands","legs","feet","neck","ring1","ring2","main","off"]
const SLOT_LABELS := {
	"head":"Head", "chest":"Chest", "hands":"Hands", "legs":"Legs", "feet":"Boots",
	"neck":"Neck", "ring1":"Ring 1", "ring2":"Ring 2", "main":"Main Hand", "off":"Off-Hand",
}
## Every category the catalog uses. `armor_bundle` and `misc` are carried, never
## worn: a bundle of mail is a purchase, and a bandage is a dressing. `ammo` is
## the third carried kind - shafts the shared quiver counts and a bow spends.
const CATEGORIES := ["1h","2h","bow","staff","shield","focus","armor","jewelry",
	"armor_bundle","misc","ammo"]
const EQUIPPABLE := ["1h","2h","bow","staff","shield","focus","armor","jewelry"]
const TWO_HANDED := ["2h","bow","staff"]

static func slot_label(slot: String) -> String:
	return str(SLOT_LABELS.get(slot, slot.capitalize()))

static func item_name(item: Dictionary) -> String:
	return str(item.get("name", "Gear"))

static func two_handed(item: Dictionary) -> bool:
	return str(item.get("category", "")) in TWO_HANDED

## Whether the item's category may occupy the slot at all.
static func allowed(item: Dictionary, slot: String) -> bool:
	if item.is_empty() or not slot in SLOTS:
		return false
	match str(item.get("category", "")):
		"1h":
			return slot == "main" or slot == "off"
		"2h", "bow", "staff":
			return slot == "main"
		"shield", "focus":
			return slot == "off"
		"armor":
			return slot == str(item.get("slot", ""))
		"jewelry":
			match str(item.get("slot", "")):
				"neck":
					return slot == "neck"
				"ring":
					return slot == "ring1" or slot == "ring2"
	return false

## The slot a fresh equip would choose: one-handers go to the main hand, off
## pieces to the off hand, armor and necklaces are fixed, and a ring fills the
## first empty ring slot before replacing ring 1.
static func auto_slot(item: Dictionary, equipped: Dictionary) -> String:
	var category := str(item.get("category", ""))
	match category:
		"1h", "2h", "bow", "staff":
			return "main"
		"shield", "focus":
			return "off"
		"armor":
			return str(item.get("slot", ""))
		"jewelry":
			match str(item.get("slot", "")):
				"neck":
					return "neck"
				"ring":
					if _slot_id(equipped, "ring1").is_empty():
						return "ring1"
					if _slot_id(equipped, "ring2").is_empty():
						return "ring2"
					return "ring1"
	return ""

## The id in one slot of a caller's own copy of the worn kit (`{"main": id, ...}`).
static func _slot_id(equipped: Dictionary, slot: String) -> String:
	return str(equipped.get(slot, ""))
