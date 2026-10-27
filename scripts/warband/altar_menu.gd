class_name AltarMenu
extends CanvasLayer
## The Sacrificial Altar's ritual panel: unbind spare steel, distil the five
## tiers 5:1, and burn brands onto the vessels a mercenary can actually hold.
##
## The panel owns no arithmetic and no wallet. `Warband.cruor` is the ledger and
## `CruorCatalog`/`BrandedSkills`/`WarbandStash` are the tables, so every number
## the player reads here is the number the save file and combat use; the menu only
## reads that state, calls one of three verbs and repaints. It is built entirely
## from `Label`s and `Button`s with the fallback font because it has to construct,
## open and be driven inside a headless regression.

signal changed

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Catalog = preload("res://scripts/warband/cruor_catalog.gd")
const Branded = preload("res://scripts/warband/branded_skills.gd")
const State = preload("res://scripts/player_state.gd")

const CREAM := Color("eee9db")
const MUTED := Color("a5b6b7")
const GOLD := Color("e9bf76")
const BLOOD := Color("c4706a")
const INK := Color(0.07, 0.05, 0.05, 1.0)
const FRAME_TINT := Color(0.10, 0.07, 0.07, 0.97)

## The warband this panel renders. Assigned by `configure()`; every read goes
## through `_cruor()`/`_stash()` so a half-initialised panel cannot crash.
var warband: Node = null

var _root: Control
var _gold_label: Label
var _status: Label
var _tier_chips: Dictionary = {}      # tier -> Label
var _unbind_list: VBoxContainer
var _distill_list: VBoxContainer
var _brand_pick: OptionButton
var _brand_tier_pick: OptionButton
var _brand_current: Label
var _brand_ability: Label
var _brand_cost: Label
var _brand_line: Label
var _brand_note: Label
var _brand_button: Button
var _built := false
var _opened := false

var _tier_rows: Array[Dictionary] = []
var _unbind_rows: Array[Dictionary] = []
var _distill_rows: Array[Dictionary] = []
var _brand_rows: Array[Dictionary] = []
var _brand_item := ""
var _brand_tier: int = Contracts.CruorTier.T1_RITUAL_TALLOW

func _ready() -> void:
	_build()
	visible = _opened

func _unhandled_input(event: InputEvent) -> void:
	if _opened and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# --- lifecycle -------------------------------------------------------------

## Point the panel at a warband. Safe to call again after a save is loaded: it
## rebuilds from whatever the roster, stash and wallet say now.
func configure(source: Node) -> void:
	warband = source
	_build()
	refresh()

func is_open() -> bool:
	return _opened

func open() -> void:
	_build()
	_opened = true
	visible = true
	refresh()
	_free_pointer()

func close() -> void:
	if not _opened:
		return
	_opened = false
	visible = false

## Repaint from the wallet and the stash. Every verb calls this, and the town hub
## calls it when a battle has just poured loot into the stash behind the panel.
func refresh() -> void:
	_build()
	_refresh_header()
	_refresh_unbind()
	_refresh_distill()
	_refresh_brand()
	visible = _opened

# --- public state (the regression and the town hub read these) -------------

func tier_rows() -> Array[Dictionary]:
	return _tier_rows

func unbind_rows() -> Array[Dictionary]:
	return _unbind_rows

func distill_rows() -> Array[Dictionary]:
	return _distill_rows

func brand_rows() -> Array[Dictionary]:
	return _brand_rows

func brand_button() -> Button:
	return _brand_button

func status_text() -> String:
	return _status.text if _status != null else ""

func gold_text() -> String:
	return _gold_label.text if _gold_label != null else ""

func selected_brand_item() -> String:
	return _brand_item

func selected_brand_tier() -> int:
	return _brand_tier

## What the brand button would do right now, including why it cannot.
func brand_preview() -> Dictionary:
	var cruor := _cruor()
	if cruor == null or _brand_item.is_empty():
		return {"ok": false, "item_id": _brand_item, "tier": _brand_tier, "ability": "",
			"ability_name": "", "cost": 0, "line": "", "message": "No vessel in the warband.",
			"branded": false}
	var item: Dictionary = State.ITEMS.get(_brand_item, {})
	var ability := Branded.for_subtype(Contracts.weapon_subtype(item))
	var check: Dictionary = cruor.can_brand(_brand_item, _brand_tier)
	return {
		"ok": bool(check.get("ok", false)),
		"item_id": _brand_item,
		"tier": _brand_tier,
		"ability": ability,
		"ability_name": Branded.ability_name(ability),
		"cost": cruor.brand_cost(_brand_tier),
		"line": Branded.tier_line(ability, _brand_tier),
		"message": str(check.get("message", "")),
		"branded": cruor.is_branded(_brand_item),
	}

## Choose a vessel for the brand column. False when the piece is not wearable
## magic the altar accepts (a shield, a ring, junk).
func select_brand_item(item_id: String) -> bool:
	for row in _brand_rows:
		if str(row["item_id"]) == item_id:
			_brand_item = item_id
			_sync_brand_pick()
			_refresh_brand_preview()
			return true
	return false

## Choose the essence that pays for the brand.
func select_brand_tier(tier: int) -> bool:
	if not Catalog.is_tier(tier):
		return false
	_brand_tier = tier
	_sync_tier_pick()
	_refresh_brand_preview()
	return true

# --- the three verbs -------------------------------------------------------

## Render one pooled copy down. The yield and the destruction are the manager's.
func press_unbind(item_id: String) -> void:
	var cruor := _cruor()
	var stash := _stash()
	if cruor == null or stash == null:
		_set_status("No warband to render for.", false)
		return
	_report(cruor.unbind(stash, item_id))

func press_distill(tier: int) -> void:
	var cruor := _cruor()
	if cruor == null:
		_set_status("No warband to distil for.", false)
		return
	_report(cruor.distill(tier))

func press_distill_all(tier: int) -> void:
	var cruor := _cruor()
	if cruor == null:
		_set_status("No warband to distil for.", false)
		return
	_report(cruor.distill_all(tier))

## Burn the selected essence onto the selected vessel. A refusal (short wallet,
## a shield, no tier) is printed, not swallowed: the button stays pressable so
## the player learns why the altar said no.
func press_brand() -> void:
	var cruor := _cruor()
	if cruor == null:
		_set_status("No warband to brand for.", false)
		return
	if _brand_item.is_empty():
		_set_status("Choose a vessel first.", false)
		return
	_report(cruor.brand(_brand_item, _brand_tier))

func _report(result: Dictionary) -> void:
	var ok := bool(result.get("ok", false))
	_set_status(str(result.get("message", "")), ok)
	refresh()
	if ok:
		changed.emit()

# --- reading the ledger ----------------------------------------------------

func _cruor() -> WarbandCruor:
	if warband == null:
		return null
	var value: Variant = warband.get("cruor")
	return value if value is WarbandCruor else null

func _stash() -> WarbandStash:
	if warband == null:
		return null
	var value: Variant = warband.get("stash")
	return value if value is WarbandStash else null

func _roster() -> Variant:
	return warband.get("roster") if warband != null else null

func _gold() -> int:
	if warband == null or not warband.has_method("gold"):
		return 0
	return int(warband.gold())

func _item_price(item_id: String) -> int:
	return int(State.ITEMS.get(item_id, {}).get("price", 0))

func _item_name(item_id: String) -> String:
	return str(State.ITEMS.get(item_id, {}).get("name", item_id))

# --- the header ------------------------------------------------------------

func _refresh_header() -> void:
	if _gold_label != null:
		_gold_label.text = "Purse  %d c" % _gold()
	var cruor := _cruor()
	_tier_rows.clear()
	for tier in Catalog.TIER_ORDER:
		var count := cruor.tier_count(tier) if cruor != null else 0
		var label: Label = _tier_chips.get(tier)
		if label == null:
			continue
		label.text = "%s\n%d" % [Catalog.tier_name(tier), count]
		_tier_rows.append({"tier": tier, "name": Catalog.tier_name(tier), "count": count,
			"color": Catalog.tier_color(tier), "label": label})

func _refresh_unbind() -> void:
	_clear(_unbind_list)
	_unbind_rows.clear()
	var cruor := _cruor()
	var stash := _stash()
	if cruor == null or stash == null or _unbind_list == null:
		return
	var rows: Array[Dictionary] = []
	for item_id in stash.pooled_ids():
		# can_unbind already refuses worn pieces and anything under the magic
		# floor, so the list is exactly "spare gear worth rendering".
		if not cruor.can_unbind(stash, item_id):
			continue
		var price := _item_price(item_id)
		rows.append({
			"item_id": item_id,
			"name": _item_name(item_id),
			"value": price,
			"pooled": stash.pooled_count(item_id),
			"yield_text": Catalog.yield_text(Catalog.unbind_yield(price)),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["value"]) != int(b["value"]):
			return int(a["value"]) > int(b["value"])
		return str(a["name"]) < str(b["name"]))
	for row in rows:
		var button := Button.new()
		button.name = "Unbind_%s" % str(row["item_id"])
		button.text = "%s  |  %d c  |  %s" % [str(row["name"]), int(row["value"]),
			str(row["yield_text"])]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 11)
		button.tooltip_text = "Unbind %s into %s" % [str(row["name"]), str(row["yield_text"])]
		button.pressed.connect(press_unbind.bind(str(row["item_id"])))
		_unbind_list.add_child(button)
		row["button"] = button
		_unbind_rows.append(row)
	if rows.is_empty():
		_add_note(_unbind_list, "No spare magic gear. Only blank steel sitting in the stash can be rendered down.")

func _refresh_distill() -> void:
	_clear(_distill_list)
	_distill_rows.clear()
	var cruor := _cruor()
	if cruor == null or _distill_list == null:
		return
	var ratio := Contracts.CRUOR_DISTILL_RATIO
	var top := Contracts.CruorTier.T5_CRYSTALLIZED_SIN
	for tier in Catalog.TIER_ORDER:
		var count := cruor.tier_count(tier)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var label := _make_label(row, "", 11, CREAM)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var batch := Button.new()
		batch.text = "DISTIL %d" % ratio
		batch.add_theme_font_size_override("font_size", 11)
		var everything := Button.new()
		everything.text = "ALL"
		everything.add_theme_font_size_override("font_size", 11)
		row.add_child(batch)
		row.add_child(everything)
		_distill_list.add_child(row)
		var reason := ""
		if tier == top:
			reason = "%s is the last tier. It does not distil." % Catalog.tier_name(tier)
			label.text = "%s  %d  -  %s" % [Catalog.tier_name(tier), count, reason]
		else:
			label.text = "%s  %d -> %d %s" % [Catalog.tier_name(tier), count, count / ratio,
				Catalog.tier_name(tier + 1)]
			if count < ratio:
				reason = "Distilling %s needs %d." % [Catalog.tier_name(tier), ratio]
		var ready := reason.is_empty()
		batch.disabled = not ready
		everything.disabled = not ready
		if not reason.is_empty():
			label.tooltip_text = reason
			batch.tooltip_text = reason
			everything.tooltip_text = reason
		batch.pressed.connect(press_distill.bind(tier))
		everything.pressed.connect(press_distill_all.bind(tier))
		_distill_rows.append({"tier": tier, "name": Catalog.tier_name(tier), "count": count,
			"text": label.text, "reason": reason, "label": label,
			"batch_button": batch, "all_button": everything})

func _refresh_brand() -> void:
	_brand_rows.clear()
	if _brand_pick != null:
		_brand_pick.clear()
	var cruor := _cruor()
	var stash := _stash()
	if cruor == null or stash == null:
		_refresh_brand_preview()
		return
	# Pooled and worn pieces alike: a brand lives on the item, not on the body.
	var candidates: Array[String] = []
	for item_id in stash.available_ids(_roster()):
		if WarbandCruor.brandable_item(item_id):
			candidates.append(item_id)
	if candidates.is_empty():
		_brand_item = ""
		_refresh_brand_preview()
		return
	candidates.sort_custom(func(a: String, b: String) -> bool:
		var a_value := WarbandStash.value_of(a, cruor.brand_of(a))
		var b_value := WarbandStash.value_of(b, cruor.brand_of(b))
		if a_value != b_value:
			return a_value > b_value
		return a < b)
	if not _brand_item in candidates:
		_brand_item = candidates[0]
	for item_id in candidates:
		var line := cruor.brand_line(item_id)
		var branded := not line.is_empty()
		_brand_rows.append({"item_id": item_id, "name": _item_name(item_id),
			"line": line, "branded": branded})
		if _brand_pick != null:
			_brand_pick.add_item("%s  (%s)" % [_item_name(item_id),
				"branded" if branded else "%d c" % _item_price(item_id)])
	_sync_brand_pick()
	_sync_tier_pick()
	_refresh_brand_preview()

func _refresh_brand_preview() -> void:
	if _brand_ability == null:
		return
	var cruor := _cruor()
	if cruor == null or _brand_item.is_empty():
		_brand_current.text = ""
		_brand_ability.text = "No steel, bow, staff, skull or tome in the warband."
		_brand_cost.text = ""
		_brand_line.text = ""
		_brand_note.text = "Nothing here can hold a sigil."
		_brand_note.add_theme_color_override("font_color", MUTED)
		_brand_button.disabled = true
		return
	var item: Dictionary = State.ITEMS.get(_brand_item, {})
	var ability := Branded.for_subtype(Contracts.weapon_subtype(item))
	var cost := cruor.brand_cost(_brand_tier)
	var check: Dictionary = cruor.can_brand(_brand_item, _brand_tier)
	var current := cruor.brand_line(_brand_item)
	_brand_current.text = "Current:  %s" % (current if not current.is_empty() else "Unbranded")
	_brand_ability.text = "%s  -  %s" % [Branded.ability_name(ability), Branded.summary(ability)]
	_brand_cost.text = "Cost:  %d x %s  (%d held)" % [cost, Catalog.tier_name(_brand_tier),
		cruor.tier_count(_brand_tier)]
	_brand_line.text = ("Reroll ->  %s" if not current.is_empty() else "Brand ->  %s") % \
		Branded.tier_line(ability, _brand_tier)
	if bool(check.get("ok", false)):
		_brand_note.text = "The altar is willing."
		_brand_note.add_theme_color_override("font_color", MUTED)
	else:
		_brand_note.text = str(check.get("message", "The altar refuses."))
		_brand_note.add_theme_color_override("font_color", BLOOD)
	_brand_button.disabled = false

func _sync_brand_pick() -> void:
	if _brand_pick == null:
		return
	for index in _brand_rows.size():
		if str(_brand_rows[index]["item_id"]) == _brand_item:
			_brand_pick.select(index)
			return

func _sync_tier_pick() -> void:
	if _brand_tier_pick == null:
		return
	var index := Catalog.TIER_ORDER.find(_brand_tier)
	if index >= 0:
		_brand_tier_pick.select(index)

func _set_status(text: String, ok: bool) -> void:
	if _status == null:
		return
	_status.text = text
	_status.add_theme_color_override("font_color", GOLD if ok else BLOOD)

# --- construction ----------------------------------------------------------

func _build() -> void:
	if _built:
		return
	_built = true
	layer = 12

	_root = Control.new()
	_root.name = "AltarRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0.02, 0.01, 0.01, 0.78)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)

	var frame := PanelContainer.new()
	frame.name = "AltarFrame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 90.0
	frame.offset_top = 50.0
	frame.offset_right = -90.0
	frame.offset_bottom = -50.0
	frame.add_theme_stylebox_override("panel", _style(FRAME_TINT, BLOOD.darkened(0.45), 6, 18))
	_root.add_child(frame)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 10)
	frame.add_child(column)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	column.add_child(title_row)
	_make_label(title_row, "SACRIFICIAL ALTAR", 18, GOLD)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(spacer)
	_gold_label = _make_label(title_row, "", 13, CREAM)
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "CLOSE"
	close_button.add_theme_font_size_override("font_size", 11)
	close_button.pressed.connect(close)
	title_row.add_child(close_button)

	var rail := HBoxContainer.new()
	rail.name = "TierRail"
	rail.add_theme_constant_override("separation", 6)
	column.add_child(rail)
	_tier_chips.clear()
	for tier in Catalog.TIER_ORDER:
		var chip := PanelContainer.new()
		chip.name = "Tier_%s" % Catalog.tier_short(tier)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.add_theme_stylebox_override("panel",
			_style(INK, Catalog.tier_color(tier).darkened(0.35), 4, 4))
		var label := _make_label(chip, "", 11, Catalog.tier_color(tier))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rail.add_child(chip)
		_tier_chips[tier] = label

	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	column.add_child(body)

	# Unbinding: one button per spare magic piece, the yield printed on it.
	var unbind_column := VBoxContainer.new()
	unbind_column.name = "UnbindColumn"
	unbind_column.custom_minimum_size = Vector2(330, 0)
	unbind_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(unbind_column)
	_make_label(unbind_column, "UNBIND SPARE STEEL", 12, GOLD)
	_make_label(unbind_column, "Spare pieces only; worn gear stays on the body.", 10, MUTED)
	var scroll := ScrollContainer.new()
	scroll.name = "UnbindScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	unbind_column.add_child(scroll)
	_unbind_list = VBoxContainer.new()
	_unbind_list.name = "UnbindList"
	_unbind_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unbind_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_unbind_list)

	# Distilling: five rows, 5 -> 1 with one button per batch and one for all.
	var distill_column := VBoxContainer.new()
	distill_column.name = "DistillColumn"
	distill_column.custom_minimum_size = Vector2(280, 0)
	distill_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(distill_column)
	_make_label(distill_column, "DISTIL 5 : 1", 12, GOLD)
	_distill_list = VBoxContainer.new()
	_distill_list.name = "DistillList"
	_distill_list.add_theme_constant_override("separation", 6)
	distill_column.add_child(_distill_list)

	# Branding: a vessel, a tier, the ability it buys and the line it prints.
	var brand_column := VBoxContainer.new()
	brand_column.name = "BrandColumn"
	brand_column.custom_minimum_size = Vector2(310, 0)
	brand_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand_column.add_theme_constant_override("separation", 6)
	body.add_child(brand_column)
	_make_label(brand_column, "BRAND A VESSEL", 12, GOLD)
	_brand_pick = OptionButton.new()
	_brand_pick.name = "VesselPick"
	_brand_pick.add_theme_font_size_override("font_size", 11)
	_brand_pick.item_selected.connect(_on_brand_item_selected)
	brand_column.add_child(_brand_pick)
	_brand_tier_pick = OptionButton.new()
	_brand_tier_pick.name = "EssencePick"
	_brand_tier_pick.add_theme_font_size_override("font_size", 11)
	for tier in Catalog.TIER_ORDER:
		_brand_tier_pick.add_item(Catalog.tier_name(tier))
	_brand_tier_pick.item_selected.connect(_on_brand_tier_selected)
	brand_column.add_child(_brand_tier_pick)
	_brand_current = _make_label(brand_column, "", 11, CREAM)
	_brand_ability = _make_label(brand_column, "", 11, CREAM)
	_brand_ability.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_brand_cost = _make_label(brand_column, "", 11, CREAM)
	_brand_line = _make_label(brand_column, "", 12, GOLD)
	_brand_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_brand_note = _make_label(brand_column, "", 10, MUTED)
	_brand_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_brand_button = Button.new()
	_brand_button.name = "BrandButton"
	_brand_button.text = "BURN THE SIGIL"
	_brand_button.add_theme_font_size_override("font_size", 12)
	_brand_button.pressed.connect(press_brand)
	brand_column.add_child(_brand_button)

	_status = _make_label(column, "", 11, MUTED)
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 22)

func _make_label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _add_note(parent: Node, text: String) -> void:
	var note := _make_label(parent, text, 10, MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _style(tint: Color, border: Color, radius: int, pad: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = tint
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(pad)
	return box

## Repaint away the previous rows without touching the node that may have just
## emitted the press that led here.
func _clear(host: Node) -> void:
	if host == null:
		return
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()

func _free_pointer() -> void:
	# Headless runs have no pointer to free, and asking the dummy display server
	# to change mouse mode only produces noise in the regression output.
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_brand_item_selected(index: int) -> void:
	if index < 0 or index >= _brand_rows.size():
		return
	select_brand_item(str(_brand_rows[index]["item_id"]))

func _on_brand_tier_selected(index: int) -> void:
	if index < 0 or index >= Catalog.TIER_ORDER.size():
		return
	select_brand_tier(Catalog.TIER_ORDER[index])
