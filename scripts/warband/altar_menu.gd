class_name AltarMenu
extends CanvasLayer
## The Sacrificial Altar's ritual panel, two pages in one frame. The first is the
## reagent rite, drawn as a rack beside a bench: the rack is one card per **copy**
## the warband carries, each wearing its own welded annointments (ten greatswords
## with ten different sets are ten cards), the bench is the square the picked copy
## is laid in, the well of the reagent it is worked with and the one brass ANOINT
## under them. Behind it are the essence rites: unbind spare steel, distil the
## five tiers 5:1, and burn brands onto the vessels a mercenary can actually hold.
##
## The panel owns no arithmetic and no wallet. `Warband.cruor` is the ledger,
## `Warband.annoint` the reagent verb and `CruorCatalog`/`BrandedSkills`/
## `WarbandStash` are the tables, so every number the player reads here is the
## number the save file and combat use; the menu only reads that state, calls one
## of four verbs and repaints. It is built entirely from `Label`s, `Button`s and
## icons with the fallback font because it has to construct, open and be driven
## inside a headless regression.

signal changed

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Catalog = preload("res://scripts/warband/cruor_catalog.gd")
const Branded = preload("res://scripts/warband/branded_skills.gd")
const State = preload("res://scripts/player_state.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const LedgerFrameScript = preload("res://scripts/ui/ledger_frame.gd")
const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")
const ItemHover = preload("res://scripts/warband/item_hover.gd")

const CREAM := LedgerThemeScript.INK
const MUTED := LedgerThemeScript.INK_MUTED
const GOLD := LedgerThemeScript.BLOOD
const BLOOD := LedgerThemeScript.BLOOD
const INK := Color(0.07, 0.05, 0.05, 1.0)
const FRAME_TINT := Color(0.10, 0.07, 0.07, 0.97)
## The bench's own palette: the dark wells a piece and its reagent are laid in,
## and the note the rite's words sit on - all of it cut into the vellum page.
const WELL_INK := Color(0.11, 0.085, 0.065, 0.95)
const WELL_EDGE := Color(0.53, 0.42, 0.24, 1.0)
const WELL_EDGE_LIT := Color(0.78, 0.64, 0.38, 1.0)
const BONE_DIM := Color(0.80, 0.74, 0.63, 1.0)
## The frame's two pages: the reagent rite, which is what a player walks up to the
## altar for, and the essence rites behind it.
const PAGE_ANOINT := "anoint"
const PAGE_ESSENCE := "essence"
## The rack's two lists: every copy the warband carries, or only the copies a
## body is wearing right now.
const RACK_ALL := "all"
const RACK_WORN := "worn"

## The square the piece is laid in, and the height of one card in the rack: a
## copy's glyph, its name, what is welded to it and its count on one line.
const SOCKET := 176.0
const RACK_ROW := 70.0
## The inks a card in the rack reads in: the wells are dark, so the name is bone,
## what is welded to it is dimmer bone, and a plain copy is quieter still.
const CARD_TEXT := Color(0.86, 0.82, 0.72, 1.0)
const CARD_DIM := Color(0.66, 0.60, 0.49, 1.0)
const CARD_FAINT := Color(0.47, 0.42, 0.34, 1.0)
## The glyph the socket draws for a piece, by the catalogue's own vocabulary: a
## piece has no art of its own, so the altar shows what class of thing it is.
const PIECE_ICON := {
	"bow": "bow", "staff": "staff", "shield": "shield", "focus": "chalice",
	"1h": "blade", "2h": "blade", "ammo": "spear",
	"head": "helm", "chest": "cuirass", "hands": "gauntlet", "legs": "greaves",
	"feet": "boot", "neck": "amulet", "ring": "ring",
}

## The warband this panel renders. Assigned by `configure()`; every read goes
## through `_cruor()`/`_stash()` so a half-initialised panel cannot crash.
var warband: Node = null
## The body the soul is inside, or -1 when the soul is between bodies or the
## scene has not said. The rack and the brand's vessel list lead with the copies
## this body wears: the steel a player walks to the altar with is the steel in
## his own hands, so it is the first card he reads and the square he works, and
## every other body's kit and every spare waits behind it.
var controlled_merc := -1

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
var _anoint_socket: Button
var _anoint_socket_icon: TextureRect
var _anoint_socket_name: Label
var _anoint_socket_state: Label
var _anoint_reagent_count: Label
var _anoint_reagent_name: Label
var _anoint_button: Button
var _anoint_report: Label
var _anoint_doctrine: Label
var _anoint_wakes: Label
var _anoint_carries: VBoxContainer
var _anoint_rack_count: Label
var _rack_filter_button: Button
var _rack_only_worn := false
var _rack_box: VBoxContainer
var _rack_note: Label
var _rack_rows: Dictionary = {}      # copy key -> {row, icon, name, welded, count}
var _socket_item := ""
var _socket_ordinal := 0
var _page := PAGE_ANOINT
var _pages: Dictionary = {}          # page -> Control
var _page_buttons: Dictionary = {}   # page -> Button
var _built := false
var _opened := false

var _tier_rows: Array[Dictionary] = []
var _unbind_rows: Array[Dictionary] = []
var _distill_rows: Array[Dictionary] = []
var _brand_rows: Array[Dictionary] = []
var _anoint_rows: Array[Dictionary] = []
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

## The body the soul is inside. Every route that opens the panel sets this before
## `open()` - `SacrificialAltar.interact` reads it off the warband's soul map -
## so the rack leads with the gear the player is wearing. -1 for a soul between
## bodies: nobody is being dressed, so worn copies lead as they always did.
func set_controlled(merc_id: int) -> void:
	if merc_id == controlled_merc:
		return
	controlled_merc = merc_id
	refresh()

## The altar always opens on the reagent rite: it is the verb a player is sent to
## the altar for. The square takes the rack's first card, which is the body's
## own gear whenever this process knows which body the soul is in.
func open() -> void:
	_build()
	_opened = true
	_page = PAGE_ANOINT
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_socket_item = ""
	_socket_ordinal = 0
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
	_refresh_anoint()
	_refresh_unbind()
	_refresh_distill()
	_refresh_brand()
	_apply_page()
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

## One row per **copy** the warband carries that the pool can mark (pooled or
## worn), so ten greatswords are ten rows: `{item_id, ordinal, copy_key, name,
## value, ability, key, count, max, pool, odds, full, entries, welded, worn,
## holder, mine, slot_rank, recipe, recipe_text, ok, message, button}`. `holder`
## is the mercenary wearing that copy (-1 for a spare), `mine` says it is worn by
## `controlled_merc`, and `slot_rank` is its place in `Contracts.SLOT_ORDER`. A
## row's `button` is the card that lays that copy in the square; the one ANOINT
## button under the square works whatever is laid there.
func anoint_rows() -> Array[Dictionary]:
	return _anoint_rows

## Which copies the rack lists: `RACK_ALL` or `RACK_WORN` (currently equipped).
func rack_filter() -> String:
	return RACK_WORN if _rack_only_worn else RACK_ALL

## Turn the rack's filter. False for a filter it does not have; the square then
## holds the first copy the new list shows, so ANOINT never works something the
## player cannot see.
func set_rack_filter(filter_name: String) -> bool:
	if filter_name != RACK_ALL and filter_name != RACK_WORN:
		return false
	_rack_only_worn = filter_name == RACK_WORN
	if _rack_filter_button != null:
		_rack_filter_button.set_pressed_no_signal(_rack_only_worn)
		_rack_filter_button.theme_type_variation = "PrimaryButton" if _rack_only_worn else ""
	refresh()
	return true

## The piece laid in the square, or "" when the altar holds none.
func selected_anoint_item() -> String:
	return _socket_item

## Which copy of `selected_anoint_item()` is laid in the square.
func selected_anoint_ordinal() -> int:
	return _socket_ordinal

## Lay a copy in the square. `ordinal` -1 takes the first copy of `item_id` the
## rack offers. False for a piece the altar is not offering; a piece it offers
## but cannot pay for still lands in the square and says why.
func select_anoint_item(item_id: String, ordinal: int = -1) -> bool:
	if item_id.is_empty():
		_lay_in_socket("")
		return false
	# A press is the moment to read the stash, not the last refresh's snapshot:
	# a vial spent since the panel was painted must refuse on this press.
	refresh()
	var row := _anoint_row_for(item_id, ordinal)
	if row.is_empty():
		return false
	_lay_in_socket(item_id, int(row["ordinal"]))
	return true

## The one brass ANOINT: it works the piece in the square, never a row's.
func anoint_button() -> Button:
	return _anoint_button

## `PAGE_ANOINT` or `PAGE_ESSENCE`.
func page() -> String:
	return _page

## Turn the frame to one of its two pages. False for a page it does not have.
func show_page(page_name: String) -> bool:
	if not _pages.has(page_name):
		return false
	_page = page_name
	_apply_page()
	return true

func brand_button() -> Button:
	return _brand_button

func status_text() -> String:
	return _status.text if _status != null else ""

## What the bench says about the piece in the square: the rite's spend, or the
## altar's refusal in its own words. "" while nothing is laid.
func doctrine_text() -> String:
	return _anoint_doctrine.text if _anoint_doctrine != null else ""

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

# --- the four verbs --------------------------------------------------------

## The one brass button: work whatever copy the square holds. A button nobody
## can pay for still presses, so the refusal is read rather than guessed at.
func press_anoint_selected() -> void:
	if _socket_item.is_empty():
		_set_status("Lay a piece on the altar first.", false)
		return
	press_anoint(_socket_item, _socket_ordinal)

## Lay the altar's reagents on one copy of a piece. The spend, the ledger and the
## orders are the warband's (`Warband.anoint`); a refusal is printed, never
## swallowed.
func press_anoint(item_id: String, ordinal: int = -1) -> void:
	if warband == null or not warband.has_method("anoint"):
		_set_status("No warband to anoint for.", false)
		return
	# The square keeps the copy it just worked, whether or not it committed.
	if ordinal < 0:
		var wanted := _socket_ordinal if item_id == _socket_item else -1
		ordinal = int(_anoint_row_for(item_id, wanted).get("ordinal", 0))
	_socket_item = item_id
	_socket_ordinal = ordinal
	var result: Dictionary = warband.anoint(item_id, ordinal)
	var completed: Variant = result.get("completed", [])
	if bool(result.get("ok", false)) and completed is Array and not (completed as Array).is_empty():
		result["message"] = str(result.get("message", "")) \
			+ "  ·  Tell the quartermaster what the steel can do now."
	_report(result, true)

## Say what the rite did, under the button that did it.
func _bench_report(text: String, ok: bool) -> void:
	if _anoint_report == null:
		return
	_anoint_report.text = text
	# Success and refusal must read apart on vellum; the altar's gold and its
	# rubric are the same ink, so the bench reports good news in the ledger's
	# teal and a refusal in blood.
	_anoint_report.add_theme_color_override("font_color",
		LedgerThemeScript.TEAL if ok else BLOOD)

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

## Say what a verb did. A rite is reported at its own bench (`bench` true); the
## essence verbs share the line at the foot of the frame.
func _report(result: Dictionary, bench: bool = false) -> void:
	var ok := bool(result.get("ok", false))
	var message := str(result.get("message", ""))
	if bench:
		_bench_report(message, ok)
	else:
		_set_status(message, ok)
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

## Build the rack: one card per **copy** the warband carries, so ten greatswords
## are ten cards, each with the annointments welded to it and its own count,
## rather than one chip standing for all of them. A copy is the ledger's own unit
## - catalog id plus ordinal - which is exactly what the altar works.
func _refresh_anoint() -> void:
	_anoint_rows.clear()
	var stash := _stash()
	if warband == null or stash == null:
		_sync_anoint_rows()
		_paint_anoint()
		return
	var roster: Variant = _roster()
	var rows: Array[Dictionary] = []
	for item_id in stash.available_ids(roster):
		# Eligibility is the pool, not a fixed recipe: anything the pool can
		# weld to - steel, a bow, a board, a helm - is offered.
		var preview: Dictionary = warband.annoint_preview(item_id)
		if int(preview.get("pool", 0)) <= 0:
			continue
		var item: Dictionary = State.ITEMS.get(item_id, {})
		var worn := _worn_tags(item_id)
		for ordinal in _copy_ordinals(item_id, _copy_total(item_id)):
			var tag: Dictionary = worn.get(ordinal, {})
			var copy: Dictionary = warband.annoint_preview(item_id, ordinal)
			var entries: Array = warband.annoints.entries_of(item_id, ordinal)
			var names: Array[String] = []
			for entry in entries:
				names.append(str(entry.name))
			var recipe := {str(copy.get("reagent", WarbandCruor.BASIC_REAGENT)): 1}
			rows.append({
				"item_id": item_id,
				"ordinal": ordinal,
				"copy_key": "%s#%d" % [item_id, ordinal],
				"name": _item_name(item_id),
				"value": _item_price(item_id),
				"ability": warband.annoints.ability_of(item_id, ordinal),
				"key": str(AbilityRules.hand_slot(item) + 1),
				"count": int(copy.get("count", 0)),
				"max": int(copy.get("max", 6)),
				"pool": int(copy.get("pool", 0)),
				"odds": copy.get("odds", {}),
				"full": bool(copy.get("full", false)),
				"entries": entries,
				"welded": "  ·  ".join(PackedStringArray(names)),
				"worn": str(tag.get("label", "")),
				"holder": int(tag.get("merc", -1)),
				"mine": _controlled_holds(tag),
				"slot_rank": _slot_rank(str(tag.get("slot", ""))),
				"recipe": recipe,
				"recipe_text": WarbandCruor.recipe_text(recipe),
				"ok": bool(copy.get("ok", false)),
				"message": str(copy.get("message", "")),
				"button": null,
			})
	# The copies on the body the soul is inside come first, in the order a body
	# is worn in - main hand, off hand, then the armour and the trinkets - because
	# that is the steel a player carried to the altar and the steel he came to
	# work. Then every other body's kit, then the spares: inside each group the
	# dearest piece leads, and inside one piece the copies that already carry
	# something, so the one a player came to look at sits at the top of its group.
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_mine := bool(a["mine"])
		var b_mine := bool(b["mine"])
		if a_mine != b_mine:
			return a_mine
		if a_mine and int(a["slot_rank"]) != int(b["slot_rank"]):
			return int(a["slot_rank"]) < int(b["slot_rank"])
		var a_worn := not str(a["worn"]).is_empty()
		var b_worn := not str(b["worn"]).is_empty()
		if a_worn != b_worn:
			return a_worn
		if int(a["value"]) != int(b["value"]):
			return int(a["value"]) > int(b["value"])
		if str(a["name"]) != str(b["name"]):
			return str(a["name"]) < str(b["name"])
		if int(a["count"]) != int(b["count"]):
			return int(a["count"]) > int(b["count"])
		return int(a["ordinal"]) < int(b["ordinal"]))
	for row in rows:
		# The rack's filter: a player hunting the sword a body is already wearing
		# does not want the seventeen spares standing between him and it.
		if _rack_only_worn and str(row["worn"]).is_empty():
			continue
		_anoint_rows.append(row)
	if _anoint_row_for(_socket_item, _socket_ordinal).is_empty():
		_socket_item = ""
		_socket_ordinal = 0
		if not _anoint_rows.is_empty():
			_socket_item = str(_anoint_rows[0]["item_id"])
			_socket_ordinal = int(_anoint_rows[0]["ordinal"])
	_sync_anoint_rows()
	_paint_anoint()

## How many copies of `item_id` the warband owns: the pool plus every worn one.
func _copy_total(item_id: String) -> int:
	var stash := _stash()
	var total := stash.pooled_count(item_id) if stash != null else 0
	var roster: Variant = _roster()
	if roster == null:
		return total
	for merc in roster.records():
		for wear in roster.worn_entries(int(merc.get("id", 0))):
			if str(wear.get("item", "")) == item_id:
				total += 1
	return total

## The ordinals the rack offers for `item_id`: every copy the ledger already
## carries annointments on, then plain copies up to the number the warband owns.
func _copy_ordinals(item_id: String, total: int) -> Array[int]:
	var out: Array[int] = []
	if warband != null:
		for ordinal in warband.annoints.ordinals_of(item_id):
			if out.size() >= total:
				break
			out.append(ordinal)
	var next := 0
	while out.size() < total:
		while out.has(next):
			next += 1
		out.append(next)
	out.sort()
	return out

## Which copies of `item_id` are worn, `ordinal -> {label, merc, slot}`. The copy
## a body wears is the warband's own answer (`annoint_copy`), so the rack and the
## field agree on which sword carries which annointments. When two bodies are
## somehow filed under one copy the body the soul is inside wins the label, since
## that is the one the rack is leading with.
func _worn_tags(item_id: String) -> Dictionary:
	var out := {}
	var roster: Variant = _roster()
	if roster == null or warband == null or not warband.has_method("annoint_copy"):
		return out
	for merc in roster.records():
		var merc_id := int(merc.get("id", 0))
		for wear in roster.worn_entries(merc_id):
			var slot := str(wear.get("slot", ""))
			if str(wear.get("item", "")) != item_id:
				continue
			var ordinal := int(warband.annoint_copy(merc_id, slot))
			if out.has(ordinal) and merc_id != controlled_merc:
				continue
			out[ordinal] = {
				"label": "%s %s" % [str(merc.get("name", "Mercenary")),
					Contracts.slot_id_label(slot)],
				"merc": merc_id,
				"slot": slot,
			}
	return out

## Whether a worn tag belongs to the body the soul is inside - the copies the
## rack leads with.
func _controlled_holds(tag: Dictionary) -> bool:
	return controlled_merc > 0 and int(tag.get("merc", -1)) == controlled_merc

## Where a slot sits in the order a body is worn in (`Contracts.SLOT_ORDER`):
## main hand, off hand, then the armour, then the trinkets. A spare, or a slot
## the table does not name, sits at the end.
func _slot_rank(slot_id: String) -> int:
	for index in Contracts.SLOT_ORDER.size():
		if str(Contracts.SLOT_IDS[Contracts.SLOT_ORDER[index]]) == slot_id:
			return index
	return Contracts.SLOT_ORDER.size()

## The row for the piece in the square: `ordinal` -1 takes the first copy of
## `item_id`, `{}` when the altar offers none.
func _anoint_row_for(item_id: String, ordinal: int = -1) -> Dictionary:
	for row in _anoint_rows:
		if str(row["item_id"]) != item_id:
			continue
		if ordinal < 0 or int(row["ordinal"]) == ordinal:
			return row
	return {}

## Lay a copy in the square (or lift the last one off) and repaint what the
## altar says about it. The one place the square's address moves on a press; a
## piece the altar cannot pay for still lands, and the refusal is printed.
func _lay_in_socket(item_id: String, ordinal: int = 0) -> void:
	_socket_item = item_id
	_socket_ordinal = ordinal if not item_id.is_empty() else 0
	_sync_anoint_rows()
	_paint_anoint()
	_bench_report("", true)

## One card per copy, cached by `item_id#ordinal` and painted in place: a repaint
## keeps the scroll where the player left it and never frees the card whose press
## led here.
func _sync_anoint_rows() -> void:
	if _rack_box == null:
		return
	for key in _rack_rows.keys():
		if _anoint_row_for_key(str(key)).is_empty():
			var parts: Dictionary = _rack_rows[key]
			var stale: Control = parts["row"]
			_rack_box.remove_child(stale)
			stale.queue_free()
			_rack_rows.erase(key)
	for index in _anoint_rows.size():
		var row := _anoint_rows[index]
		var key := str(row["copy_key"])
		var parts: Variant = _rack_rows.get(key)
		if parts == null:
			parts = _build_rack_row(row)
			_rack_rows[key] = parts
		_rack_box.move_child(parts["row"], index)
		_paint_rack_row(parts, row)
	if _rack_note != null:
		_rack_note.visible = _anoint_rows.is_empty()
		_rack_note.text = "No worn piece takes anointings." if _rack_only_worn \
			else "Nothing the warband carries takes anointings."
	if _anoint_rack_count != null:
		var count := _anoint_rows.size()
		_anoint_rack_count.text = "%d %s" % [count, "copy" if count == 1 else "copies"]

func _anoint_row_for_key(key: String) -> Dictionary:
	for row in _anoint_rows:
		if str(row["copy_key"]) == key:
			return row
	return {}

## A rack card: the piece's glyph, its name, what is welded to that copy and its
## count. The button under it only lays the copy in the square.
func _build_rack_row(row: Dictionary) -> Dictionary:
	var item_id := str(row["item_id"])
	var ordinal := int(row["ordinal"])
	var button: Button = ItemHover.Row.new()
	button.name = "Rack_%d" % ordinal
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, RACK_ROW)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void: select_anoint_item(item_id, ordinal))
	_rack_box.add_child(button)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_bottom", 6)
	button.add_child(pad)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 12)
	pad.add_child(line)

	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(icon)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", 0)
	line.add_child(column)
	var name_label := _make_label(column, "", 14, CARD_TEXT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var welded := _make_label(column, "", 12, CARD_DIM)
	welded.mouse_filter = Control.MOUSE_FILTER_IGNORE
	welded.clip_text = true
	welded.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	var count_label := _make_label(line, "", 13, CARD_DIM)
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.custom_minimum_size = Vector2(52, 0)
	return {"row": button, "icon": icon, "name": name_label, "welded": welded,
		"count": count_label}

## Paint one card from its row: the piece, the annointments on that copy and how
## full it is. Selection is the same brass the one ANOINT button wears.
func _paint_rack_row(parts: Dictionary, row: Dictionary) -> void:
	var button: Button = parts["row"]
	var item_id := str(row["item_id"])
	var selected := item_id == _socket_item and int(row["ordinal"]) == _socket_ordinal
	var fill := Color(0.25, 0.19, 0.11) if selected else WELL_INK
	var edge := WELL_EDGE_LIT if selected else Color(WELL_EDGE, 0.45)
	var rest := _style(fill, edge, 4, 0, 1)
	if selected:
		# A brass spine down the card a player has laid in the square, readable at
		# a glance in a rack of ten near-identical pieces.
		rest.border_width_left = 4
	button.add_theme_stylebox_override("normal", rest)
	button.add_theme_stylebox_override("hover",
		_style(Color(0.17, 0.13, 0.09), WELL_EDGE, 4, 0, 1))
	button.add_theme_stylebox_override("pressed", rest)
	button.add_theme_stylebox_override("hover_pressed", rest)
	button.set_pressed_no_signal(selected)
	(parts["icon"] as TextureRect).texture = LedgerThemeScript.icon_small(
		_piece_icon_key(State.ITEMS.get(item_id, {})))
	(parts["name"] as Label).text = str(row["name"]).to_upper()
	var welded := str(row["welded"])
	var worn := str(row["worn"])
	var line := welded if not welded.is_empty() else "Nothing welded"
	if not worn.is_empty():
		line = "%s   ·   Worn %s" % [line, worn]
	var line_label: Label = parts["welded"]
	line_label.text = line
	line_label.add_theme_color_override("font_color",
		CARD_DIM if not welded.is_empty() else CARD_FAINT)
	var count := int(row["count"])
	var cap := int(row["max"])
	var count_label: Label = parts["count"]
	count_label.text = "%d / %d" % [count, cap]
	count_label.add_theme_color_override("font_color",
		WELL_EDGE_LIT if count >= cap else CARD_DIM)
	button.show_item(item_id, warband, "Lay this copy on the altar.", 1, "", int(row["ordinal"]))
	row["button"] = button

## What the square, the reagent well, the one button and the words under them
## say right now. Reads `_anoint_rows` and the stash only, so the picture and
## the refusal can never disagree.
func _paint_anoint() -> void:
	if _anoint_socket == null or _anoint_button == null:
		return
	var row := _anoint_row_for(_socket_item, _socket_ordinal)
	var stash := _stash()
	var reagent := WarbandCruor.BASIC_REAGENT
	var held := stash.pooled_count(reagent) if stash != null else 0
	if _anoint_reagent_count != null:
		_anoint_reagent_count.text = "%d" % held
	if _anoint_reagent_name != null:
		_anoint_reagent_name.text = _item_name(reagent).to_upper()
	_anoint_button.disabled = row.is_empty()
	if row.is_empty():
		var carried := not _anoint_rows.is_empty()
		_anoint_socket.show_item("", warband, "")
		_anoint_socket_icon.texture = LedgerThemeScript.icon_large("altar")
		_anoint_socket_icon.modulate = Color(1.0, 1.0, 1.0, 0.16)
		_anoint_socket_name.text = "NOTHING LAID"
		_anoint_socket_state.text = "take a copy from the rack" if carried \
			else "nothing can be marked"
		_anoint_doctrine.text = "Nothing is laid on the altar." if carried \
			else "The warband carries nothing the altar can mark."
		_anoint_doctrine.add_theme_color_override("font_color", MUTED)
		_anoint_wakes.text = ""
		_anoint_wakes.visible = false
		_paint_carries("", 0)
		_anoint_button.tooltip_text = ""
		return
	var item_id := str(row["item_id"])
	var ordinal := int(row["ordinal"])
	var item: Dictionary = State.ITEMS.get(item_id, {})
	var count := int(row.get("count", 0))
	var cap := int(row.get("max", 6))
	_anoint_socket_icon.texture = LedgerThemeScript.icon_large(_piece_icon_key(item))
	_anoint_socket_icon.modulate = Color.WHITE
	_anoint_socket_name.text = str(row["name"]).to_upper()
	var worn := str(row.get("worn", ""))
	var state := ("%d / %d WELDED" % [count, cap]) if count > 0 else "NOTHING WELDED"
	_anoint_socket_state.text = ("%s  ·  WORN %s" % [state, worn.to_upper()]) \
		if not worn.is_empty() else state
	_anoint_socket.show_item(item_id, warband, "Click to lift it off the altar.", 1, "", ordinal)
	if bool(row.get("ok", false)):
		_anoint_doctrine.text = "Spend %s." % str(row["recipe_text"])
		_anoint_doctrine.add_theme_color_override("font_color", INK)
	else:
		_anoint_doctrine.text = str(row.get("message", "The altar refuses."))
		_anoint_doctrine.add_theme_color_override("font_color", BLOOD)
	_anoint_wakes.text = _wakes_text(row, item_id)
	_anoint_wakes.visible = not _anoint_wakes.text.is_empty()
	_paint_carries(item_id, ordinal)
	var odds := _odds_text(row.get("odds", {}))
	_anoint_button.tooltip_text = ("The die  ·  %s" % odds) if not odds.is_empty() else ""

## The copy's welded annointments, one row each: the ledger's own name and line.
## Nothing is printed for a copy that carries none.
func _paint_carries(item_id: String, ordinal: int) -> void:
	if _anoint_carries == null:
		return
	_clear(_anoint_carries)
	if item_id.is_empty() or warband == null:
		return
	for entry in warband.annoints.entries_of(item_id, ordinal):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_anoint_carries.add_child(row)
		var name_label := _make_label(row, str(entry.name), 11, INK)
		name_label.custom_minimum_size = Vector2(132, 0)
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var line := _make_label(row, str(entry.line), 11, MUTED)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL

## What the piece's hand will carry: the skill the altar already welded on, or
## the one the stock piece would wake into, and the hand that performs it. The
## hotbar number is not promised here - it depends on the rest of the worn kit.
func _wakes_text(row: Dictionary, item_id: String) -> String:
	var hand := "OFF HAND" if str(row.get("key", "1")) == "2" else "MAIN HAND"
	var welded := str(row.get("ability", ""))
	if not welded.is_empty():
		var name := str(AbilityRules.by_id(welded).get("name", welded))
		return "CARRIES %s  ·  %s" % [name.to_upper(), hand]
	var stock: Dictionary = WarbandCruor.anoint_skill(item_id)
	if stock.is_empty():
		return ""
	return "WOULD WAKE %s  ·  %s" % [
		str(stock.get("name", "")).to_upper(), hand]

## The four bands the altar's die is cut into, in the order they are cut.
func _odds_text(odds: Dictionary) -> String:
	var words := {
		"add_ability": "add an ability",
		"add_passive": "add a passive",
		"remove": "strip one",
		"replace": "swap one",
	}
	var parts: Array[String] = []
	for band in words:
		if not odds.has(band):
			continue
		parts.append("%d%% %s" % [int(round(float(odds[band]) * 100.0)), str(words[band])])
	return "  ·  ".join(PackedStringArray(parts))

## The glyph the altar shows for a piece: the catalogue has no art of its own,
## so a piece is drawn as the class of thing it is.
func _piece_icon_key(item: Dictionary) -> String:
	var category := str(item.get("category", ""))
	var slot := str(item.get("slot", ""))
	match category:
		"jewelry":
			return "amulet" if slot == "neck" else "ring"
		"armor":
			return str(PIECE_ICON.get(slot, "cuirass"))
		"misc":
			return "chalice"
	return str(PIECE_ICON.get(category, "blade"))

func _apply_page() -> void:
	for page_name in _pages:
		(_pages[page_name] as Control).visible = page_name == _page
	for page_name in _page_buttons:
		(_page_buttons[page_name] as Button).set_pressed_no_signal(page_name == _page)

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
		var button := ItemHover.Row.new()
		button.name = "Unbind_%s" % str(row["item_id"])
		button.text = "%s  |  %d c  |  %s" % [str(row["name"]), int(row["value"]),
			str(row["yield_text"])]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 11)
		button.show_item(str(row["item_id"]), warband,
			"Click to unbind it into %s." % str(row["yield_text"]))
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
	# A vessel the body the soul is inside is wearing leads, then any other
	# body's, for the rack's own reason: the sigil a player came to burn goes on
	# the piece in his own hands before anyone else's kit and before a spare.
	# Inside each group the dearest vessel leads.
	var mine := {}
	var worn := {}
	for item_id in candidates:
		var tags := _worn_tags(item_id)
		if tags.is_empty():
			continue
		worn[item_id] = true
		for ordinal in tags:
			if _controlled_holds(tags[ordinal]):
				mine[item_id] = true
				break
	candidates.sort_custom(func(a: String, b: String) -> bool:
		var a_mine := mine.has(a)
		var b_mine := mine.has(b)
		if a_mine != b_mine:
			return a_mine
		var a_worn := worn.has(a)
		var b_worn := worn.has(b)
		if a_worn != b_worn:
			return a_worn
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
	_root.theme = LedgerThemeScript.get_theme()
	add_child(_root)

	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0.02, 0.01, 0.01, 0.78)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)

	var frame = LedgerFrameScript.new()
	frame.name = "AltarFrame"
	frame.configure("The Altar", "flame")
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 70.0
	frame.offset_top = 36.0
	frame.offset_right = -70.0
	frame.offset_bottom = -36.0
	_root.add_child(frame)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	frame.body.add_child(column)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	column.add_child(title_row)
	_make_label(title_row, "THE SACRIFICE", 11, BLOOD)
	# The two rites the altar keeps: reagents on steel first, essence behind it.
	var pages := ButtonGroup.new()
	for entry in [[PAGE_ANOINT, "ANOINT"], [PAGE_ESSENCE, "ESSENCE"]]:
		var tab := Button.new()
		tab.name = "Page_%s" % str(entry[0])
		tab.text = str(entry[1])
		tab.toggle_mode = true
		tab.button_group = pages
		tab.add_theme_font_size_override("font_size", 11)
		tab.pressed.connect(show_page.bind(str(entry[0])))
		title_row.add_child(tab)
		_page_buttons[str(entry[0])] = tab
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

	# The reagent rite is a rack beside a bench: every copy the warband carries is
	# a card of its own on the left, and the card picked is laid in the square on
	# the right under the one brass ANOINT.
	var anoint_page := VBoxContainer.new()
	anoint_page.name = "AnointPage"
	anoint_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	anoint_page.add_theme_constant_override("separation", 8)
	column.add_child(anoint_page)
	_pages[PAGE_ANOINT] = anoint_page

	var spread := HBoxContainer.new()
	spread.name = "Spread"
	spread.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spread.add_theme_constant_override("separation", 20)
	anoint_page.add_child(spread)

	# The rack: one card per copy, so ten of a piece are ten rows to look through.
	var rack := VBoxContainer.new()
	rack.name = "Rack"
	rack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rack.add_theme_constant_override("separation", 8)
	spread.add_child(rack)
	var rack_head := HBoxContainer.new()
	rack_head.name = "RackHead"
	rack_head.add_theme_constant_override("separation", 10)
	rack.add_child(rack_head)
	_make_label(rack_head, "THE RACK", 12, GOLD)
	var rack_spacer := Control.new()
	rack_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rack_head.add_child(rack_spacer)
	_rack_filter_button = Button.new()
	_rack_filter_button.name = "RackFilter"
	_rack_filter_button.text = "WORN ONLY"
	_rack_filter_button.toggle_mode = true
	_rack_filter_button.focus_mode = Control.FOCUS_NONE
	_rack_filter_button.add_theme_font_size_override("font_size", int(round(10 * 1.18)))
	_rack_filter_button.pressed.connect(_on_rack_filter_pressed)
	rack_head.add_child(_rack_filter_button)
	_anoint_rack_count = _make_label(rack_head, "", 10, MUTED)
	_anoint_rack_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var rack_scroll := ScrollContainer.new()
	rack_scroll.name = "RackScroll"
	rack_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rack_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rack.add_child(rack_scroll)
	_style_scroll(rack_scroll)
	_rack_box = VBoxContainer.new()
	_rack_box.name = "RackRows"
	_rack_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rack_box.add_theme_constant_override("separation", 4)
	rack_scroll.add_child(_rack_box)
	_rack_note = _make_label(_rack_box, "Nothing the warband carries takes anointings.", 12, MUTED)
	_rack_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rack_note.visible = false

	# The bench: the square, what the rite would spend, the one brass ANOINT, and
	# what the copy in the square already carries.
	var bench_scroll := ScrollContainer.new()
	bench_scroll.name = "BenchScroll"
	bench_scroll.custom_minimum_size = Vector2(368, 0)
	bench_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	spread.add_child(bench_scroll)
	_style_scroll(bench_scroll)
	var bench := VBoxContainer.new()
	bench.name = "Bench"
	bench.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bench.add_theme_constant_override("separation", 8)
	bench_scroll.add_child(bench)
	_make_label(bench, "THE BENCH", 12, GOLD)

	_anoint_socket = ItemHover.Row.new()
	_anoint_socket.name = "AnointSocket"
	_anoint_socket.custom_minimum_size = Vector2(SOCKET, SOCKET)
	_anoint_socket.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_anoint_socket.focus_mode = Control.FOCUS_NONE
	_anoint_socket.add_theme_stylebox_override("normal", _style(WELL_INK, WELL_EDGE, 5, 0))
	_anoint_socket.add_theme_stylebox_override("hover", _style(WELL_INK, WELL_EDGE_LIT, 5, 0))
	_anoint_socket.add_theme_stylebox_override("pressed",
		_style(WELL_INK.lightened(0.06), WELL_EDGE_LIT, 5, 0))
	_anoint_socket.add_theme_stylebox_override("disabled", _style(WELL_INK, WELL_EDGE, 5, 0))
	_anoint_socket.pressed.connect(_on_anoint_socket_pressed)
	bench.add_child(_anoint_socket)

	var well := VBoxContainer.new()
	well.name = "Well"
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well.offset_left = 14.0
	well.offset_top = 14.0
	well.offset_right = -14.0
	well.offset_bottom = -14.0
	well.alignment = BoxContainer.ALIGNMENT_CENTER
	well.add_theme_constant_override("separation", 4)
	_anoint_socket.add_child(well)

	_anoint_socket_icon = TextureRect.new()
	_anoint_socket_icon.name = "Piece"
	_anoint_socket_icon.custom_minimum_size = Vector2(0, SOCKET - 84.0)
	_anoint_socket_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_anoint_socket_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_anoint_socket_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(_anoint_socket_icon)

	_anoint_socket_name = _make_label(well, "", 15, LedgerThemeScript.BONE)
	_anoint_socket_name.name = "PieceName"
	_anoint_socket_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anoint_socket_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_anoint_socket_name.add_theme_font_override("font", LedgerThemeScript.FONT_DISPLAY)
	_anoint_socket_state = _make_label(well, "", 10, BONE_DIM)
	_anoint_socket_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anoint_socket_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# What the rite would spend, in the altar's own words, or why it will not.
	_anoint_doctrine = _make_label(bench, "", 13, INK)
	_anoint_doctrine.name = "DoctrineLine"
	_anoint_doctrine.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anoint_doctrine.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_anoint_wakes = _make_label(bench, "", 12, LedgerThemeScript.EMBER)
	_anoint_wakes.name = "Wakes"
	_anoint_wakes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anoint_wakes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# The reagent and the count held, on one line.
	var reagent_row := HBoxContainer.new()
	reagent_row.name = "Reagent"
	reagent_row.alignment = BoxContainer.ALIGNMENT_CENTER
	reagent_row.add_theme_constant_override("separation", 12)
	bench.add_child(reagent_row)

	var reagent_well := PanelContainer.new()
	reagent_well.name = "ReagentWell"
	reagent_well.custom_minimum_size = Vector2(52, 52)
	reagent_well.add_theme_stylebox_override("panel", _style(WELL_INK, WELL_EDGE, 4, 6))
	reagent_row.add_child(reagent_well)
	var reagent_icon := TextureRect.new()
	reagent_icon.texture = LedgerThemeScript.icon_large("chalice")
	reagent_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	reagent_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	reagent_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reagent_well.add_child(reagent_icon)

	_anoint_reagent_count = _make_label(reagent_row, "0", 24, LedgerThemeScript.BONE)
	_anoint_reagent_count.name = "HeldCount"
	_anoint_reagent_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_anoint_reagent_count.add_theme_font_override("font", LedgerThemeScript.FONT_DISPLAY)
	_anoint_reagent_name = _make_label(reagent_row, "", 11, MUTED)
	_anoint_reagent_name.name = "HeldName"
	_anoint_reagent_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_anoint_button = Button.new()
	_anoint_button.name = "AnointButton"
	_anoint_button.text = "ANOINT"
	_anoint_button.custom_minimum_size = Vector2(0, 52)
	_anoint_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_anoint_button.add_theme_font_size_override("font_size", int(round(18 * 1.18)))
	_anoint_button.theme_type_variation = "PrimaryButton"
	_anoint_button.pressed.connect(press_anoint_selected)
	bench.add_child(_anoint_button)

	# What the last press did, at the press: the bench reports itself instead of
	# sending the player to a line at the foot of the frame.
	_anoint_report = _make_label(bench, "", 12, MUTED)
	_anoint_report.name = "RiteReport"
	_anoint_report.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anoint_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# What the copy already carries: one row per welded annointment, read off the
	# ledger rather than recomposed here.
	_make_label(bench, "WELDED", 10, MUTED)
	_anoint_carries = VBoxContainer.new()
	_anoint_carries.name = "Carries"
	_anoint_carries.add_theme_constant_override("separation", 2)
	bench.add_child(_anoint_carries)

	# The essence rites: the five-tier rail over unbind, distil and brand.
	var essence_page := VBoxContainer.new()
	essence_page.name = "EssencePage"
	essence_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	essence_page.add_theme_constant_override("separation", 8)
	column.add_child(essence_page)
	_pages[PAGE_ESSENCE] = essence_page

	var rail := HBoxContainer.new()
	rail.name = "TierRail"
	rail.add_theme_constant_override("separation", 6)
	essence_page.add_child(rail)
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
	essence_page.add_child(body)

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
	_brand_button.add_theme_font_size_override("font_size", 15)
	_brand_button.theme_type_variation = "PrimaryButton"
	_brand_button.pressed.connect(press_brand)
	brand_column.add_child(_brand_button)

	_status = _make_label(column, "", 12, MUTED)
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 22)
	_apply_page()

func _make_label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", int(round(font_size * 1.18)))
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _add_note(parent: Node, text: String) -> void:
	var note := _make_label(parent, text, 10, MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

## A scroll's bar wears the altar's own ink instead of the desktop default: a
## hairline brass grabber on a well that is nearly the vellum underneath.
func _style_scroll(host: ScrollContainer) -> void:
	var bar := host.get_v_scroll_bar()
	bar.custom_minimum_size = Vector2(7, 0)
	bar.add_theme_stylebox_override("scroll", _style(Color(0.16, 0.12, 0.09, 0.10),
		Color(0, 0, 0, 0), 3, 0))
	bar.add_theme_stylebox_override("grabber", _style(Color(WELL_EDGE, 0.65), Color(0, 0, 0, 0), 3, 0))
	bar.add_theme_stylebox_override("grabber_highlight", _style(WELL_EDGE, Color(0, 0, 0, 0), 3, 0))
	bar.add_theme_stylebox_override("grabber_pressed", _style(WELL_EDGE_LIT, Color(0, 0, 0, 0), 3, 0))

func _style(tint: Color, border: Color, radius: int, pad: int, width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = tint
	box.border_color = border
	box.set_border_width_all(width)
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

func _on_anoint_socket_pressed() -> void:
	if _socket_item.is_empty():
		return
	_lay_in_socket("")

func _on_rack_filter_pressed() -> void:
	set_rack_filter(RACK_WORN if _rack_filter_button.button_pressed else RACK_ALL)

func _on_brand_item_selected(index: int) -> void:
	if index < 0 or index >= _brand_rows.size():
		return
	select_brand_item(str(_brand_rows[index]["item_id"]))

func _on_brand_tier_selected(index: int) -> void:
	if index < 0 or index >= Catalog.TIER_ORDER.size():
		return
	select_brand_tier(Catalog.TIER_ORDER[index])
