class_name VendorMenu
extends Control
## One of the town's three keepers, as a ledger panel: the stock they hold on the
## left, the shared stash on the right, and the purse over both.
##
## The panel is deliberately thin. Stock is exactly the keeper's entry in
## `PlayerState.VENDORS` (filtered to real, priced catalogue ids), buying goes
## through `Warband.buy_gear` and selling through `Warband.sell_gear`, so the
## prices, the refusal rules and the stash write live in one place. The menu only
## decides what is on the board and what the keeper says about it.
##
## A `Control`, not a `CanvasLayer`: the town (or the world embedding it) owns
## the layer, and the same node walks from keeper to keeper with `configure()`.

signal changed
## A keeper actually took the coin: the stock left the board and the purse paid
## for it. `changed` cannot carry this - it also fires when the panel opens or a
## body sells something back - and what the town wants to answer is the trade.
signal purchased(item_id: String)

const State = preload("res://scripts/player_state.gd")
const LedgerFrameScript = preload("res://scripts/ui/ledger_frame.gd")
const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")

const INK := LedgerThemeScript.INK
const MUTED := LedgerThemeScript.INK_MUTED

## What a keeper pays back for a piece. Mirrors `Warband.sell_gear`'s default, so
## the price on the board is the price the purse is actually paid.
const SELL_SHARE := 0.6
const PANEL_SIZE := Vector2(860, 620)

var _warband = null
var _vendor_index := 0
var _open := false
var _built := false

var _keeper: Label
var _line: Label
var _purse: Label
var _status: Label
var _stock_list: VBoxContainer
var _stash_list: VBoxContainer

func _ready() -> void:
	if not _built:
		_build()
	# A panel configured before it entered the tree was built without a viewport
	# rect; fixing the anchors here keeps the screen-sized overlay honest either way.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = _open

## Point this one panel at a keeper seat. Safe before or after the node enters
## the tree; the board is rebuilt because the stock is the keeper's, not the
## panel's.
func configure(warband, vendor_index: int) -> void:
	_warband = warband
	if State.VENDORS.is_empty():
		_vendor_index = 0
	else:
		_vendor_index = clampi(vendor_index, 0, State.VENDORS.size() - 1)
	if not _built:
		_build()
	_apply_keeper()
	refresh()

func open() -> void:
	if not _built:
		_build()
	_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_apply_keeper()
	refresh()

func close() -> void:
	_open = false
	visible = false

func is_open() -> bool:
	return _open

func vendor_index() -> int:
	return _vendor_index

func keeper_name() -> String:
	return str(_vendor().get("name", "Keeper"))

func keeper_tag() -> String:
	return str(_vendor().get("tag", "KEEPER"))

func keeper_line() -> String:
	return str(_vendor().get("line", ""))

func status_text() -> String:
	return str(_status.text) if _status != null else ""

## The keeper's stock, filtered to ids this build actually carries at a price.
## Rows: `{item_id, name, category, price, affordable}`.
func stock_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if _warband == null or State.VENDORS.is_empty():
		return rows
	var gold: int = _warband.gold()
	var stock: Array = _vendor().get("stock", [])
	for entry in stock:
		var item_id := str(entry)
		var item: Dictionary = State.ITEMS.get(item_id, {})
		if item.is_empty():
			continue
		var price := int(item.get("price", 0))
		if price <= 0:
			continue
		rows.append({
			"item_id": item_id,
			"name": str(item.get("name", item_id)),
			"category": str(item.get("category", "")),
			"price": price,
			"affordable": gold >= price,
		})
	return rows

## Every pooled copy the warband could sell, one row per id with its count.
## Worn pieces are not here: the pool is what a keeper can take without
## stripping a body. Rows: `{item_id, name, count, price}`; `price` is what the
## keeper pays for one copy.
func stash_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if _warband == null:
		return rows
	var pooled: Dictionary = _warband.stash.pooled_map()
	for entry in pooled:
		var item_id := str(entry)
		var count := int(pooled[entry])
		if count <= 0:
			continue
		var item: Dictionary = State.ITEMS.get(item_id, {})
		rows.append({
			"item_id": item_id,
			"name": str(item.get("name", item_id)),
			"count": count,
			"price": _payout(int(item.get("price", 0))),
		})
	rows.sort_custom(_sort_rows)
	return rows

## Buy one piece of this keeper's stock. Refused before the purse is touched when
## the piece is not actually on the board, so a caller can never buy the whole
## catalogue through a keeper who does not carry it.
func buy(item_id: String) -> Dictionary:
	if _warband == null:
		return {"ok": false, "message": "The keeper is not here.", "item_id": item_id, "cost": 0}
	var stocked := false
	for row in stock_rows():
		if str(row["item_id"]) == item_id:
			stocked = true
			break
	if not stocked:
		var refusal := {"ok": false, "item_id": item_id, "cost": 0,
			"message": "%s does not stock that." % keeper_name()}
		_set_status(str(refusal["message"]))
		return refusal
	var result: Dictionary = _warband.buy_gear(item_id)
	_set_status(str(result.get("message", "")))
	refresh()
	if bool(result.get("ok", false)):
		purchased.emit(item_id)
	return result

## Sell one pooled copy at the keeper's rate (`SELL_SHARE` of the catalogue).
func sell(item_id: String) -> Dictionary:
	if _warband == null:
		return {"ok": false, "message": "The keeper is not here.", "item_id": item_id, "price": 0}
	var result: Dictionary = _warband.sell_gear(item_id, SELL_SHARE)
	_set_status(str(result.get("message", "")))
	refresh()
	return result

## Repaint the purse, the prices and both lists. The board is small enough that
## rebuilding the rows is cheaper to keep correct than patching every count.
func refresh() -> void:
	if not _built:
		return
	_purse.text = "%d G" % (_warband.gold() if _warband != null else 0)
	_fill_lists()
	changed.emit()

# --- construction ----------------------------------------------------------

func _vendor() -> Dictionary:
	if State.VENDORS.is_empty():
		return {}
	return State.VENDORS[_vendor_index] as Dictionary

func _payout(list_price: int) -> int:
	return int(floor(float(list_price) * SELL_SHARE))

func _apply_keeper() -> void:
	if not _built:
		return
	_keeper.text = keeper_name()
	_line.text = "%s  ·  %s" % [keeper_tag(), keeper_line()]

func _set_status(text: String) -> void:
	if _status != null and not text.is_empty():
		_status.text = text

func _build() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = LedgerThemeScript.get_theme()

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.015, 0.01, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var frame = LedgerFrameScript.new()
	frame.name = "Frame"
	frame.configure("The Keepers", "coin")
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.offset_left = -PANEL_SIZE.x * 0.5
	frame.offset_right = PANEL_SIZE.x * 0.5
	frame.offset_top = -PANEL_SIZE.y * 0.5
	frame.offset_bottom = PANEL_SIZE.y * 0.5
	add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.body.add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	column.add_child(head)
	_keeper = _label(head, "", 22, INK)
	_keeper.add_theme_font_override("font", LedgerThemeScript.FONT_DISPLAY)
	_keeper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_purse = _label(head, "", 22, INK)
	_purse.add_theme_font_override("font", LedgerThemeScript.FONT_DISPLAY)
	_purse.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_line = _label(column, "", 13, MUTED)
	_line.add_theme_font_override("font", LedgerThemeScript.FONT_ITALIC)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(columns)
	_stock_list = _column(columns, "STOCK  ·  BUY")
	_stash_list = _column(columns, "SHARED STASH  ·  SELL")

	_status = _label(column, "", 12, LedgerThemeScript.TEAL)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 34)

	_apply_keeper()

## One half of the board: a heading and a scrolling list, filling its side.
func _column(parent: Node, heading: String) -> VBoxContainer:
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(side)
	_label(side, heading, 10, MUTED)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list

func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	parent.add_child(result)
	return result

# --- rows ------------------------------------------------------------------

func _fill_lists() -> void:
	_clear(_stock_list)
	_clear(_stash_list)
	var stock := stock_rows()
	if stock.is_empty():
		_label(_stock_list, "The keeper holds nothing today.", 13, MUTED)
	for row in stock:
		_stock_row(row)
	var stash := stash_rows()
	if stash.is_empty():
		_label(_stash_list, "Nothing pooled to sell.", 13, MUTED)
	for row in stash:
		_stash_row(row)

func _stock_row(row: Dictionary) -> void:
	var item_id := str(row["item_id"])
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var name_label := _label(line, str(row["name"]), 16, INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var price_label := _label(line, "%d G" % int(row["price"]), 14, MUTED)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_label.custom_minimum_size = Vector2(64, 0)
	var buy_button := Button.new()
	buy_button.text = "BUY"
	buy_button.custom_minimum_size = Vector2(74, 30)
	buy_button.add_theme_font_size_override("font_size", 11)
	buy_button.disabled = not bool(row["affordable"])
	buy_button.pressed.connect(_on_buy.bind(item_id))
	line.add_child(buy_button)
	_stock_list.add_child(line)

func _stash_row(row: Dictionary) -> void:
	var item_id := str(row["item_id"])
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var name_label := _label(line, "%s  ×%d" % [str(row["name"]), int(row["count"])],
		16, INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var price_label := _label(line, "%d G" % int(row["price"]), 14, MUTED)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_label.custom_minimum_size = Vector2(64, 0)
	var sell_button := Button.new()
	sell_button.text = "SELL"
	sell_button.custom_minimum_size = Vector2(74, 30)
	sell_button.add_theme_font_size_override("font_size", 11)
	sell_button.pressed.connect(_on_sell.bind(item_id))
	line.add_child(sell_button)
	_stash_list.add_child(line)

func _clear(list: VBoxContainer) -> void:
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()

static func _sort_rows(a: Dictionary, b: Dictionary) -> bool:
	if int(a["price"]) != int(b["price"]):
		return int(a["price"]) > int(b["price"])
	var a_name := str(a["name"]).to_lower()
	var b_name := str(b["name"]).to_lower()
	if a_name != b_name:
		return a_name < b_name
	return str(a["item_id"]) < str(b["item_id"])

func _on_buy(item_id: String) -> void:
	buy(item_id)

func _on_sell(item_id: String) -> void:
	sell(item_id)
