extends RefCounted
## Catalog icon lookup for the equipment menu, tooltip and vendor rows.
##
## Every icon is a screenshot of the piece as it appears on the character,
## rendered by `playtest/item_studio.gd` into `assets/ui/items/<item id>.png`.
## Missing art degrades to no icon instead of a broken resource path.

const DIR := "res://assets/ui/items/"

static var _cache: Dictionary = {}


static func path_for(item_id: String) -> String:
	return DIR + item_id + ".png"


static func texture(item_id: String) -> Texture2D:
	if item_id.is_empty():
		return null
	if _cache.has(item_id):
		return _cache[item_id]
	var path := path_for(item_id)
	if not ResourceLoader.exists(path):
		_cache[item_id] = null
		return null
	var image := load(path)
	_cache[item_id] = image
	return image


## True when every catalog id has a rendered screenshot.
static func missing(ids: Array) -> Array:
	var absent: Array = []
	for item_id in ids:
		if texture(str(item_id)) == null:
			absent.append(str(item_id))
	return absent
