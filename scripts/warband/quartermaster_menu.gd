class_name QuartermasterMenu
extends CanvasLayer
## The keeper who sells plain steel. Gold is the town's sink for hiring and for
## base gear; this panel is the second half of that, and it is deliberately
## separate from the ranger's old keeper counters: what you buy here lands in the
## warband's collective stash, where the paperdoll can put it on any mercenary.

signal changed

const State = preload("res://scripts/player_state.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")

## Base stock: one legal piece for every kind of hand plus the cheapest armor
## and rings, so a fresh warband can be armed without a single lucky drop.
const STOCK := [
	"sword_short", "dagger_iron", "bow_short", "shield_buckler",
	"armor_leather_head", "armor_leather_chest", "armor_mail_chest",
	"ring_copper", "ring_health", "focus_tome", "torch_hand",
]

const PANEL_SIZE := Vector2(440, 560)

var _warband = null
var _open := false
var _built := false
var _list: VBoxContainer
var _purse: Label
var _status: Label
var _rows: Dictionary = {}   # item_id -> {root, button, price_label}

func _ready() -> void:
	layer = 5
	visible = false

func configure(warband) -> void:
	_warband = warband
	if not _built:
		_build()
	refresh()

func open() -> void:
	if not _built:
		_build()
	_open = true
	visible = true
	refresh()

func close() -> void:
	_open = false
	visible = false

func is_open() -> bool:
	return _open

func status_text() -> String:
	return str(_status.text) if _status != null else ""

## The stock with the price the shop will charge and whether the purse covers it.
func stock_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if _warband == null:
		return rows
	var gold: int = _warband.gold()
	for item_id in STOCK:
		var item: Dictionary = State.ITEMS.get(str(item_id), {})
		if item.is_empty():
			continue
		var price := int(item.get("price", 0))
		rows.append({"item_id": str(item_id), "name": str(item.get("name", item_id)),
			"price": price, "affordable": gold >= price})
	return rows

## Buy one piece into the shared stash. Everything about the transaction -
## the price, the purse, the stash row - belongs to `Warband.buy_gear`.
func buy(item_id: String) -> Dictionary:
	if _warband == null:
		return {"ok": false, "message": "The keeper is not here.", "item_id": item_id, "cost": 0}
	var result: Dictionary = _warband.buy_gear(item_id)
	if _status != null:
		_status.text = str(result.get("message", ""))
	refresh()
	return result

func refresh() -> void:
	if not _built:
		return
	var gold: int = _warband.gold() if _warband != null else 0
	_purse.text = "%d gold" % gold
	for item_id in _rows:
		var row: Dictionary = _rows[item_id]
		var price := int(row.get("price", 0))
		var button: Button = row["button"]
		button.disabled = gold < price
		button.text = "BUY  %d" % price
	changed.emit()

# --- construction ----------------------------------------------------------

func _build() -> void:
	if _built:
		return
	_built = true
	var root_control := Control.new()
	root_control.name = "Root"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -PANEL_SIZE.x * 0.5
	panel.offset_right = PANEL_SIZE.x * 0.5
	panel.offset_top = -PANEL_SIZE.y * 0.5
	panel.offset_bottom = PANEL_SIZE.y * 0.5
	root_control.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var title := Label.new()
	title.text = "QUARTERMASTER"
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)
	var blurb := Label.new()
	blurb.text = "Plain steel, bought into the shared stash."
	blurb.add_theme_font_size_override("font_size", 12)
	blurb.modulate = Color(0.75, 0.75, 0.75)
	column.add_child(blurb)
	_purse = Label.new()
	_purse.add_theme_font_size_override("font_size", 14)
	column.add_child(_purse)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_SIZE.x - 32, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(PANEL_SIZE.x - 32, 40)
	column.add_child(_status)

	_rows.clear()
	for row in stock_rows():
		var item_id := str(row["item_id"])
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var name_label := Label.new()
		name_label.text = str(row["name"])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var buy_button := Button.new()
		buy_button.custom_minimum_size = Vector2(120, 28)
		buy_button.pressed.connect(_on_buy.bind(item_id))
		line.add_child(buy_button)
		_list.add_child(line)
		_rows[item_id] = {"root": line, "button": buy_button, "price": int(row["price"])}

func _on_buy(item_id: String) -> void:
	buy(item_id)
