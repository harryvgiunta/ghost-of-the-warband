extends RefCounted
## Ability definitions shared by every mode.
##
## An ability is data: cost, cooldown, duration, movement, animation, sound and
## icon. `AbilityRunner` owns the lifecycle; controllers only supply authority
## and the current base movement speed. Add a new entry here, an icon beside it,
## and the same HUD/input/network path works for the next ability.

const SLOT_COUNT := 1
const ABILITIES := [
	{
		"id": "charge",
		"name": "CHARGE",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": 10.0,
		"cooldown": 2.5,
		"duration": 1.0,
		"speed_scale": 2.0,
		"sound": "charge",
		"animation": "Sprint_Loop",
		"lean": 0.18,
		"icon": "res://assets/ui/abilities/charge.png",
		"description": "Lunge forward at double speed for one second.",
	},
]

static var _icon_cache: Dictionary = {}


static func by_slot(slot: int) -> Dictionary:
	for ability: Dictionary in ABILITIES:
		if int(ability.slot) == slot:
			return ability
	return {}


static func by_id(id: String) -> Dictionary:
	for ability: Dictionary in ABILITIES:
		if str(ability.id) == id:
			return ability
	return {}


static func slot_of(id: String) -> int:
	var ability := by_id(id)
	return int(ability.get("slot", -1))


static func icon_texture(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var path := str(by_id(id).get("icon", ""))
	var texture: Texture2D = null
	if not path.is_empty() and ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_icon_cache[id] = texture
	return texture
