class_name CorpseLootPanel
extends WarbandPaperdoll
## The dead body's screen: the same paperdoll renderer and the same shared stash,
## pointed at a corpse instead of a mercenary.
##
## It is a class of its own so a scene can own one screen layer: build a
## `CorpseLootPanel` where it would build a `WarbandPaperdoll`, and `open()` still
## dresses the warband while `open_corpse()` searches the body at the player's
## feet. The two modes are never shown at once, and both land on the same booking
## path - a piece taken off a corpse is a `WarbandStash` row the instant it is
## taken, so there is no second inventory to reconcile.
##
## Looting a body is a click, not an aim, so opening this screen takes the mouse
## pointer and closing it hands back the mode the scene had. `is_open()` is the
## base class's and answers for both modes.

var _pointer_before := Input.MOUSE_MODE_CAPTURED
var _pointer_taken := false

## Open on the body `corpse_id` names in `loot`. Answers false - and opens
## nothing - when there is no such body or it has already been stripped, so a key
## press that found no corpse in reach is never answered with an empty screen.
func open_corpse(loot, corpse_id: int) -> bool:
	if loot == null or not is_instance_valid(loot):
		return false
	if not loot.has_method("corpse_items"):
		return false
	var ids: Array[String] = loot.corpse_items(corpse_id)
	if ids.is_empty():
		return false
	corpse_loot = loot
	_take_pointer()
	show_corpse(corpse_id, ids)
	return true

## Close the screen and give the pointer back. The corpse mode is released with
## it, so a paperdoll reopened later dresses mercenaries instead of a body that
## may have been picked clean in the meantime.
func close() -> void:
	super()
	clear_corpse()
	corpse_loot = null
	_release_pointer()

func _exit_tree() -> void:
	_release_pointer()
	super()

func _take_pointer() -> void:
	if _pointer_taken:
		return
	_pointer_before = Input.mouse_mode
	_pointer_taken = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _release_pointer() -> void:
	if not _pointer_taken:
		return
	_pointer_taken = false
	Input.mouse_mode = _pointer_before
