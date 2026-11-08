class_name WarbandItemCard
extends PanelContainer
## The hover card for one catalog piece: its name, what it is, the words the
## catalogue authors for it, whatever numbers a table actually owns (an armor
## piece's guard, a trinket's modifiers, the bunch an ammunition row buys), the
## brand and anointing the ledger holds for that id, and its worth.
##
## The catalogue is the only source of the type line and the detail text, so a
## card can never disagree with the stash row that opened it. Everything else is
## read from the table that already owns it - `ArmorData`, `TrinketStats`,
## `WarbandStash` - rather than copied into a second list here.
##
## Built purely from Labels and a PanelContainer style: it renders in headless
## regressions and inside Godot's tooltip popup, which stretches its child unless
## both size flags say SHRINK (a short card must stay short).
##
## `compose()` is an instance method and the caller instantiates through the
## preloaded script: a headless run against a stale global class cache would not
## resolve this file's own `class_name`.

const State = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const TrinketStats = preload("res://scripts/trinket_stats.gd")
const ItemPassives = preload("res://scripts/item_passives.gd")
const StashScript = preload("res://scripts/warband/town_stash_model.gd")
const Ledger = preload("res://scripts/ui/ledger_theme.gd")

const WIDTH := 268.0
const PAD := 12.0
const CONTENT := WIDTH - PAD * 2.0

const CREAM := Color("e9e0c9")
const DIM := Color("b7ab93")
const FAINT := Color("8f8272")
const GOLD := Color("e9bf76")
const TEAL := Color("7fc8b4")
const BRASS := Color("7c6a45")
const RULE := Color("4a4232")

## Whether the catalogue knows this id. A row with no item draws no card.
static func has(item_id: String) -> bool:
	return not (State.ITEMS.get(item_id, {}) as Dictionary).is_empty()


## The one-line "what is this" every surface reads. The vocabulary is the
## catalogue's own `category`/`kind`/`slot`, so a new piece only needs its row.
static func type_line(item_id: String, item: Dictionary) -> String:
	var category := str(item.get("category", ""))
	var kind := str(item.get("kind", "")).to_upper()
	match category:
		"bow":
			return "BOW  /  MAIN HAND"
		"1h":
			return "%s  /  ONE-HAND" % kind
		"2h":
			return "%s  /  TWO-HAND" % kind
		"staff":
			return "STAFF  /  TWO-HAND"
		"shield":
			return "SHIELD  /  OFF-HAND"
		"focus":
			return "FOCUS  /  OFF-HAND"
		"armor":
			var set_index := clampi(int(item.get("set", 0)), 0, ArmorData.SET_IDS.size() - 1)
			var slot := str(item.get("slot", ""))
			if str(ArmorData.SET_IDS[set_index]) == "naked":
				return "NO COVER  /  %s" % ArmorData.slot_label(slot).to_upper()
			return "%s ARMOR  /  %s" % [str(ArmorData.SET_IDS[set_index]).to_upper(),
				ArmorData.slot_label(slot).to_upper()]
		"jewelry":
			return "JEWELRY  /  " + ("RING" if str(item.get("slot", "")) == "ring" else "NECK")
		"ammo":
			return "AMMO  /  THE SHARED QUIVER"
		"misc":
			if item.has("heal"):
				return "DRESSING  /  CARRIED"
			return "MATERIAL  /  %s" % str(item.get("material", "SALVAGE")).to_upper()
	return kind


## The numbers the catalogue's prose cannot carry: guard, trinket modifiers, the
## ammunition bundle, a dressing's wound, and the passive a swung piece carries
## (`ItemPassives` - the dagger's shank, the club's heavy overhand).
## One row per fact, label/value.
static func detail_rows(item_id: String, item: Dictionary) -> Array:
	var rows: Array = []
	var swung := ItemPassives.class_of(item)
	if not swung.is_empty():
		rows.append_array(ItemPassives.effect_rows(swung))
	match str(item.get("category", "")):
		"armor":
			var set_index := clampi(int(item.get("set", 0)), 0, ArmorData.SET_IDS.size() - 1)
			var slot := str(item.get("slot", ""))
			var guard := int(round(ArmorData.reduction_for(set_index, slot) * 100.0))
			if slot == "head":
				rows.append({"label":"HEAD GUARD", "value":"%d%%" % guard})
			else:
				rows.append({"label":"BODY GUARD", "value":"+%d%%" % guard})
		"jewelry", "focus":
			rows.append_array(TrinketStats.effect_rows(item_id))
			var grant := TrinketStats.grant_for(item_id)
			if not grant.is_empty():
				rows.append({"label":"SKILL", "value":
					grant.replace("_", " ").to_upper()})
		"ammo":
			rows.append({"label":"BUNCH", "value":"%d per purchase" % State.item_bundle(item_id)})
		"misc":
			if item.has("heal"):
				rows.append({"label":"WOUND", "value":"+%d%% health" % int(round(
					float(item.get("heal", 0.0)) * 100.0))})
			elif item.has("material"):
				rows.append({"label":"STOCK", "value":str(item.get("material", ""))})
	return rows


## The lines the altar's ledger owns: `{text, skill}`, where `skill` marks the
## anointing line (gold) rather than a brand (teal). A plain weapon still says
## what the altar would wake in it, which is the only place a player learns it
## before the piece enters a body.
static func wear_lines(item_id: String, cruor: Variant) -> Array:
	var lines: Array = []
	if cruor == null or not is_instance_valid(cruor):
		return lines
	if cruor.has_method("brand_line"):
		var brand_line := str(cruor.brand_line(item_id))
		if not brand_line.is_empty():
			lines.append({"text":brand_line, "skill":false})
	if not cruor.has_method("anoint_line"):
		return lines
	var anoint_line := str(cruor.anoint_line(item_id))
	if not anoint_line.is_empty():
		lines.append({"text":anoint_line, "skill":true})
		return lines
	var skill: Dictionary = WarbandCruor.anoint_skill(item_id)
	if not skill.is_empty():
		var ability := str(skill.get("id", ""))
		var recipe := WarbandCruor.recipe_text(WarbandCruor.anoint_recipe(ability))
		lines.append({"text":"Plain - anoint it to wake %s  ·  %s" % [
			str(skill.get("name", ability)), recipe], "skill":true})
	return lines


## Dress this panel as the card for `item_id`. `warband` (optional) supplies the
## brand/anointing ledger; `hint` is the row's own instruction, `count` how many
## copies the row stands for, `note` anything the caller's board adds (a keeper's
## price), `copy_ordinal` which copy the row shows (-1 resolves it). No-op for an
## id the catalogue does not know.
func compose(item_id: String, warband = null, hint: String = "",
		count: int = 1, note: String = "", copy_ordinal: int = -1) -> void:
	var item: Dictionary = State.ITEMS.get(item_id, {})
	if item.is_empty():
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	custom_minimum_size = Vector2(WIDTH, 0)
	theme = Ledger.get_theme()
	add_theme_stylebox_override("panel", _panel_style())
	var cruor: Variant = _cruor_of(warband)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", int(PAD))
	margin.add_theme_constant_override("margin_right", int(PAD))
	margin.add_theme_constant_override("margin_top", int(PAD) - 1)
	margin.add_theme_constant_override("margin_bottom", int(PAD) - 1)
	add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 3)
	column.custom_minimum_size.x = CONTENT
	margin.add_child(column)

	_text(column, str(item.get("name", item_id)), 21, GOLD,
		HORIZONTAL_ALIGNMENT_CENTER, Ledger.FONT_DISPLAY)
	_text(column, type_line(item_id, item), 10, FAINT, HORIZONTAL_ALIGNMENT_CENTER)
	var summary := str(item.get("summary", ""))
	if not summary.is_empty():
		var line := _text(column, summary, 12, DIM, HORIZONTAL_ALIGNMENT_CENTER,
			Ledger.FONT_ITALIC)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var detail := str(item.get("detail", ""))
	var rows := detail_rows(item_id, item)
	var wears := wear_lines(item_id, cruor)
	# The welded annointments sit under the ledger lines: one row per modifier,
	# read straight off the pool so a new entry needs no card change.
	for entry in annoint_entries(item_id, warband, copy_ordinal):
		rows.append({"label": "ANNOINT", "value": "%s - %s" % [
			str(entry.name), str(entry.line)]})
	if not detail.is_empty() or not rows.is_empty() or not wears.is_empty():
		_rule(column)
	if not detail.is_empty():
		var line := _text(column, detail, 12, CREAM)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for row in rows:
		_stat(column, str(row.get("label", "")), str(row.get("value", "")))
	for entry in wears:
		var line := _text(column, str(entry.get("text", "")), 11,
			GOLD if bool(entry.get("skill", false)) else TEAL)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var brand: Dictionary = cruor.brand_of(item_id) if cruor != null \
		and cruor.has_method("brand_of") else {}
	var worth := StashScript.value_of(item_id, brand)
	_rule(column)
	_stat(column, "WORTH", "%d G" % worth)
	if count > 1:
		_stat(column, "COPIES", "×%d  ·  %d G the lot" % [count, worth * count])
	if not note.is_empty():
		var line := _text(column, note, 11, DIM)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not hint.is_empty():
		var line := _text(column, hint, 10, TEAL)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## The annointments on the copy this card is showing. `ordinal` -1 is resolved by
## the warband (a worn piece answers its own copy); a pooled one answers the
## first copy, which is what a board without its own addresses presses. A row
## that stands for one copy of many passes its own.
static func annoint_entries(item_id: String, warband, ordinal: int = -1) -> Array:
	if warband == null or not is_instance_valid(warband):
		return []
	var ledger: Variant = (warband as Object).get("annoints")
	if ledger == null:
		return []
	var copy := ordinal
	if copy < 0:
		copy = 0
		if (warband as Object).has_method("annoint_copy_for_item"):
			copy = int((warband as Object).annoint_copy_for_item(item_id))
	return ledger.entries_of(item_id, copy)


static func _cruor_of(warband) -> Variant:
	if warband == null or not is_instance_valid(warband):
		return null
	return (warband as Object).get("cruor")


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.043, 0.032, 0.985)
	style.border_color = BRASS
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 10
	return style


func _text(parent: Node, text: String, font_size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, font: Font = null) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if font != null:
		label.add_theme_font_override("font", font)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _stat(parent: Node, label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var key := Label.new()
	key.text = label_text + ":"
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key.add_theme_font_size_override("font_size", 11)
	key.add_theme_color_override("font_color", DIM)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(key)
	var value := Label.new()
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", 12)
	value.add_theme_color_override("font_color", CREAM)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(value)


func _rule(parent: Node) -> void:
	var rule := ColorRect.new()
	rule.color = RULE
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)
