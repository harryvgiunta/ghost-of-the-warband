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
## The vacuum this screen is watching, so a piece somebody else took - the host,
## a squadmate, a guest over the session - leaves the open screen too.
var _watched_loot = null

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
	_watch(loot)
	corpse_loot = loot
	_take_pointer()
	show_corpse(corpse_id, ids)
	return true

## Repaint when this body's record moves under the screen: a take by another
## soul empties the row, and the last piece closes the screen. The guest's copy
## is written by the session's corpse RPC, so this is the same path on both.
func _on_corpse_changed(changed_id: int, _items: Array) -> void:
	if not showing_corpse() or changed_id != corpse_id:
		return
	if corpse_loot == null or not is_instance_valid(corpse_loot):
		close()
		return
	var ids: Array = corpse_loot.corpse_items(corpse_id)
	if ids.is_empty():
		# Deferred: this can fire inside the very take that emptied the body, and
		# the take still has its own status line and repaint to finish first.
		call_deferred("close")
		return
	refresh_corpse()

func _watch(loot) -> void:
	_unwatch()
	if loot == null or not is_instance_valid(loot) or not loot.has_signal("corpse_changed"):
		return
	if loot.corpse_changed.is_connected(_on_corpse_changed):
		return
	_watched_loot = loot
	loot.corpse_changed.connect(_on_corpse_changed)

func _unwatch() -> void:
	if _watched_loot != null and is_instance_valid(_watched_loot) \
			and _watched_loot.has_signal("corpse_changed") \
			and _watched_loot.corpse_changed.is_connected(_on_corpse_changed):
		_watched_loot.corpse_changed.disconnect(_on_corpse_changed)
	_watched_loot = null

## Close the screen and give the pointer back. The corpse mode is released with
## it, so a paperdoll reopened later dresses mercenaries instead of a body that
## may have been picked clean in the meantime.
func close() -> void:
	super()
	clear_corpse()
	corpse_loot = null
	_unwatch()
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
