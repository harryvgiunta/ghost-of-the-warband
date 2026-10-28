class_name QuartermasterMenu
extends CanvasLayer
## The keeper who sells plain steel. Gold is the town's sink for hiring and for
## base gear; this panel is the second half of that, and it is deliberately
## separate from the ranger's old keeper counters: what you buy here lands in the
## warband's collective stash, where the paperdoll can put it on any mercenary.

signal changed

const State = preload("res://scripts/player_state.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const LedgerFrameScript = preload("res://scripts/ui/ledger_frame.gd")
const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")

const INK := LedgerThemeScript.INK
const MUTED := LedgerThemeScript.INK_MUTED
const BLOOD := LedgerThemeScript.BLOOD

## Base stock: the makeshift tier a prisoner actually carries, the naked set a
## body starts in, then one legal piece for every kind of hand plus the cheapest
## armour and rings, so a fresh warband can be armed without a single lucky drop.
const STOCK := [
	"dagger_ironwood", "club_makeshift", "bow_twig", "branch_heavy", "shield_wood",
	"armor_naked_head", "armor_naked_chest", "armor_naked_hands",
	"armor_naked_legs", "armor_naked_feet",
	"sword_short", "dagger_iron", "bow_short", "shield_buckler",
	"armor_leather_head", "armor_leather_chest", "armor_mail_chest",
	"ring_copper", "ring_health", "focus_tome", "torch_hand",
]

const PANEL_SIZE := Vector2(640, 680)

var _warband = null
var _open := false
var _built := false
var _list: VBoxContainer
var _purse: Label
var _status: Label
var _rows: Dictionary = {}   # item_id -> {root, button, price_label}

func _ready() -> void:
	layer = 9
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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
	_purse.text = "%d G" % gold
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
	root_control.theme = LedgerThemeScript.get_theme()
	add_child(root_control)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.015, 0.01, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root_control.add_child(dim)

	var frame = LedgerFrameScript.new()
	frame.name = "Frame"
	frame.configure("Quartermaster", "coin")
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.offset_left = -PANEL_SIZE.x * 0.5
	frame.offset_right = PANEL_SIZE.x * 0.5
	frame.offset_top = -PANEL_SIZE.y * 0.5
	frame.offset_bottom = PANEL_SIZE.y * 0.5
	root_control.add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	frame.body.add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	column.add_child(head)
	_label(head, "THE TOWN  \u00b7  SHARED STASH", 10, MUTED)
	_purse = _label(column, "", 22, INK)
	_purse.add_theme_font_override("font", LedgerThemeScript.FONT_DISPLAY)
	_purse.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_purse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var blurb := _label(column, "Plain steel, bought into the shared stash.", 13, MUTED)
	blurb.add_theme_font_override("font", LedgerThemeScript.FONT_ITALIC)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 330)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_status = _label(column, "", 12, LedgerThemeScript.TEAL)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 34)

	_rows.clear()
	for row in stock_rows():
		var item_id := str(row["item_id"])
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var name_label := _label(line, str(row["name"]), 17, INK)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var buy_button := Button.new()
		buy_button.custom_minimum_size = Vector2(120, 30)
		buy_button.add_theme_font_size_override("font_size", 11)
		buy_button.pressed.connect(_on_buy.bind(item_id))
		line.add_child(buy_button)
		_list.add_child(line)
		_rows[item_id] = {"root": line, "button": buy_button, "price": int(row["price"])}

func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	parent.add_child(result)
	return result


func _on_buy(item_id: String) -> void:
	buy(item_id)
