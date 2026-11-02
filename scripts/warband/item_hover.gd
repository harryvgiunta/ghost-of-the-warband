class_name WarbandItemHover
extends RefCounted
## The hover half of an item row: the control the player points at answers
## Godot's `_make_custom_tooltip` with the piece's own card (`WarbandItemCard`)
## instead of a plain sentence about clicking it.
##
## Two shapes, because the screens build rows two ways: `Row` is the Button row
## the paperdoll, delve prep, loot window and altar use, and `LabelRow` is the
## name half of a keeper row (a Label beside its BUY/SELL button). Both carry the
## same fields, so one `show_item()` call is the whole wiring.
##
## The tooltip string itself stays on the control (`tooltip_text` = the piece's
## name): Godot only asks for a custom tooltip when that string is non-empty, and
## it is also what a screen reader announces while the card is shut.
##
## Both shapes preload their own dependencies rather than naming this file's
## `class_name`: a headless run against a stale global class cache would not
## resolve it.

class Row extends Button:
	const Card = preload("res://scripts/warband/item_card.gd")
	const State = preload("res://scripts/player_state.gd")

	var item_id := ""
	var warband = null
	var hint := ""
	var note := ""
	var count := 1

	## Point this row at `item_id`. `owner` is the warband whose brand/anointing
	## ledger the card prints (optional); `text` is the row's own instruction.
	func show_item(id: String, owner = null, text: String = "", copies: int = 1,
			board_note: String = "") -> void:
		item_id = id
		warband = owner
		hint = text
		count = maxi(copies, 1)
		note = board_note
		tooltip_text = str(State.ITEMS.get(id, {}).get("name", id)) if not id.is_empty() else ""

	## The card for the row's current piece, or null when it holds none.
	func make_card() -> Control:
		if item_id.is_empty() or not Card.has(item_id):
			return null
		var card = Card.new()
		card.compose(item_id, warband, hint, count, note)
		return card

	func _make_custom_tooltip(_for_text: String) -> Object:
		return make_card()


class LabelRow extends Label:
	const Card = preload("res://scripts/warband/item_card.gd")
	const State = preload("res://scripts/player_state.gd")

	var item_id := ""
	var warband = null
	var hint := ""
	var note := ""
	var count := 1

	func show_item(id: String, owner = null, text: String = "", copies: int = 1,
			board_note: String = "") -> void:
		item_id = id
		warband = owner
		hint = text
		count = maxi(copies, 1)
		note = board_note
		tooltip_text = str(State.ITEMS.get(id, {}).get("name", id)) if not id.is_empty() else ""
		# A Label is not hoverable by default; the row's name is the thing the
		# player points at, so it answers the mouse itself.
		mouse_filter = Control.MOUSE_FILTER_STOP

	func make_card() -> Control:
		if item_id.is_empty() or not Card.has(item_id):
			return null
		var card = Card.new()
		card.compose(item_id, warband, hint, count, note)
		return card

	func _make_custom_tooltip(_for_text: String) -> Object:
		return make_card()
