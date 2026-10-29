class_name IchorBench
extends CanvasLayer
## The quartermaster's bench, and the one thing in the campaign that turns a drop
## into a permanent change to a weapon.
##
## A warden's ichor is a carried reagent, not a wallet: it is spent here on one
## spare weapon out of the shared stash, and the piece comes back carrying a
## sigil. That sigil is the altar's own brand ledger (`WarbandCruor.brands`), so
## the `BrandedRunner` on the body that holds the piece and the sigil tile on the
## HUD light up without knowing the ichor exists - `R` is what looses it.
##
## The bench is two halves and either can be used alone:
##  * `build_prop()` - the furniture. Nine tenths of the town's readability is
##    this: a stone slab, a vial rack and a brazier that is the only green light
##    in a warm square, which is how a player finds it without a sign.
##  * the panel - what the slab does. One row per spare weapon that could take a
##    sigil, the vial count above them, one button each.

signal changed
## A piece actually took a sigil this press.
signal bound(item_id: String, ability: String)

const State = preload("res://scripts/player_state.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Catalog = preload("res://scripts/warband/cruor_catalog.gd")
const Branded = preload("res://scripts/warband/branded_skills.gd")
const LedgerFrameScript = preload("res://scripts/ui/ledger_frame.gd")
const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")
const Geo = preload("res://scripts/geo.gd")

const INK := LedgerThemeScript.INK
const MUTED := LedgerThemeScript.INK_MUTED

## The reagent and the tier one vial is worth. One vial, one blade: the tier is
## the altar's first, so an ichor-bound piece reads as the cheapest sigil until
## essence is spent to deepen it.
const ICHOR := "ichor_vial"
const TIER := Contracts.CruorTier.T1_RITUAL_TALLOW
const PANEL_SIZE := Vector2(660, 620)
## Where the bench stands, in the town's own space: at the quartermaster's side,
## just clear of his 3 m counter ring.
const PROP_POINT := Vector3(2.6, 0.0, -12.6)

var _warband = null
var _hud = null
var _open := false
var _built := false
var _list: VBoxContainer
var _count: Label
var _status: Label
var _rows: Dictionary = {}   # item_id -> {root, button, line}


func _ready() -> void:
	layer = 9
	visible = false


func configure(warband, hud = null) -> void:
	_warband = warband
	_hud = hud
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


## How many vials the shared stash holds.
func vial_count() -> int:
	return _warband.stash.pooled_count(ICHOR) if _warband != null else 0


## One row per spare weapon that could take a sigil: the pooled pieces that are
## brandable and not already branded, with the ability the bench would give.
func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _warband == null:
		return out
	for item_id in _warband.stash.pooled_ids():
		var id := str(item_id)
		if not _warband.cruor.brandable_item(id) or _warband.cruor.is_branded(id):
			continue
		var item: Dictionary = State.ITEMS.get(id, {})
		var ability := Branded.for_subtype(Contracts.weapon_subtype(item))
		if ability.is_empty():
			continue
		out.append({
			"item_id": id,
			"name": str(item.get("name", id)),
			"count": _warband.stash.pooled_count(id),
			"ability": ability,
			"ability_name": Branded.ability_name(ability),
			"line": Branded.tier_line(ability, TIER),
		})
	out.sort_custom(func(a, b): return str(a["name"]) < str(b["name"]))
	return out


## Lay one vial to one pooled weapon. The vial leaves the stash, the piece takes
## a sigil, and the campaign's ichor order hears about it.
func apply(item_id: String) -> Dictionary:
	if _warband == null:
		return {"ok": false, "message": "The bench is cold.", "item_id": item_id}
	if vial_count() <= 0:
		return _say({"ok": false, "item_id": item_id,
			"message": "No ichor. The watchers carry it; nothing else does."})
	if _warband.stash.pooled_count(item_id) <= 0:
		return _say({"ok": false, "item_id": item_id,
			"message": "That piece is not in the shared stash."})
	var result: Dictionary = _warband.cruor.bind(item_id, TIER)
	if not bool(result.get("ok", false)):
		return _say({"ok": false, "item_id": item_id, "message": str(result.get("message", ""))})
	_warband.stash.remove(ICHOR, 1)
	var moved: Array = _warband.quests.note_applied(ICHOR)
	var ability := str(result.get("ability", ""))
	var message := str(result.get("message", ""))
	if not moved.is_empty() and _warband.quests.is_complete(str(moved[0])):
		message += "  ·  Tell the quartermaster what the steel can do now."
	if _hud != null:
		_hud.set_status(message, 4.5)
	_say({"ok": true, "item_id": item_id, "ability": ability, "message": message})
	bound.emit(item_id, ability)
	return {"ok": true, "item_id": item_id, "ability": ability, "message": message}


func refresh() -> void:
	if not _built:
		return
	_count.text = "%d VIAL%s  ·  ONE VIAL BINDS ONE BLADE" % [vial_count(),
		"" if vial_count() == 1 else "S"]
	var have := vial_count()
	for item_id in _rows:
		var row: Dictionary = _rows[item_id]
		var button: Button = row["button"]
		button.disabled = have <= 0
		button.text = "BIND  1 ICHOR" if have > 0 else "NO ICHOR"
	changed.emit()


func _say(result: Dictionary) -> Dictionary:
	if _status != null:
		_status.text = str(result.get("message", ""))
	refresh()
	return result


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
	frame.configure("The Ichor Bench", "scroll")
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.offset_left = -PANEL_SIZE.x * 0.5
	frame.offset_right = PANEL_SIZE.x * 0.5
	frame.offset_top = -PANEL_SIZE.y * 0.5
	frame.offset_bottom = PANEL_SIZE.y * 0.5
	root_control.add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	frame.body.add_child(column)
	_label(column, "WATCHER'S ICHOR  \u00b7  STEEL THAT ANSWERS", 10, MUTED)
	_count = _label(column, "", 22, INK)
	_count.add_theme_font_override("font", LedgerThemeScript.FONT_DISPLAY)
	var blurb := _label(column,
		"One vial to one spare blade out of the shared stash. The piece takes a"
			+ " sigil and keeps it: press R with it in your hands.", 13, MUTED)
	blurb.add_theme_font_override("font", LedgerThemeScript.FONT_ITALIC)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

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
	_fill_list()


## One row per pooled weapon. The list is a snapshot: a piece leaves the pool when
## it is bound, so it is repainted from `rows()` after every press.
func _fill_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	for row in rows():
		var item_id := str(row["item_id"])
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var name_label := _label(line, "%s%s" % [str(row["name"]),
			"" if int(row["count"]) <= 1 else "  x%d" % int(row["count"])], 17, INK)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sigil := _label(line, str(row["ability_name"]), 12, LedgerThemeScript.BLOOD)
		sigil.custom_minimum_size = Vector2(150, 0)
		sigil.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var button := Button.new()
		button.custom_minimum_size = Vector2(150, 30)
		button.add_theme_font_size_override("font_size", 11)
		button.pressed.connect(_on_bind.bind(item_id))
		line.add_child(button)
		_list.add_child(line)
		_rows[item_id] = {"root": line, "button": button}


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	parent.add_child(result)
	return result


func _on_bind(item_id: String) -> void:
	apply(item_id)
	_fill_list()
	refresh()


# --- the furniture ---------------------------------------------------------

## The bench itself, standing in the square. Returns the prop node.
##
## Deliberately unlit from above and lit from inside: the brazier carries a small
## cold-green light that no other light in the town has, so the one place a
## dropped reagent is used is findable at a glance in a warm dusk square.
static func build_prop(host: Node3D, at: Vector3 = PROP_POINT) -> Node3D:
	var prop := Node3D.new()
	prop.name = "IchorBench"
	prop.position = at
	host.add_child(prop)
	var stone := Geo.material(Color(0.26, 0.25, 0.24), 0.0, 0.94)
	var timber := Geo.material(Color(0.20, 0.14, 0.09), 0.0, 0.85)
	var iron := Geo.material(Color(0.30, 0.29, 0.28), 0.6, 0.55)
	var ichor := StandardMaterial3D.new()
	ichor.albedo_color = Color(0.16, 0.42, 0.26)
	ichor.emission_enabled = true
	ichor.emission = Color(0.24, 0.86, 0.42)
	ichor.emission_energy_multiplier = 2.2
	# Slab on two trestles: a working bench, not a table.
	Geo.box(prop, Vector3(1.7, 0.16, 0.85), Vector3(0.0, 0.92, 0.0), stone)
	for x in [-0.66, 0.66]:
		Geo.box(prop, Vector3(0.14, 0.86, 0.7), Vector3(x, 0.43, 0.0), timber)
	# The vial rack: three standing vials, one of them live.
	for index in 3:
		var x := -0.52 + float(index) * 0.24
		Geo.cylinder(prop, 0.055, 0.05, 0.19, Vector3(x, 1.09, -0.24), timber, 8)
		var glass := ichor if index == 2 else Geo.material(Color(0.22, 0.24, 0.22), 0.1, 0.35)
		Geo.cylinder(prop, 0.042, 0.04, 0.13, Vector3(x, 1.22, -0.24), glass, 8)
	# The bowl: where the vial is poured and the blade is laid.
	Geo.cylinder(prop, 0.17, 0.21, 0.10, Vector3(0.42, 1.03, 0.12), iron, 12)
	Geo.cylinder(prop, 0.15, 0.15, 0.03, Vector3(0.42, 1.08, 0.12), ichor, 12)
	# A hammer laid across the corner, and a blade waiting on the slab.
	Geo.beam(prop, Vector3(-0.2, 0.94, 0.3), Vector3(-0.02, 1.02, 0.22), 0.028, timber, 6)
	Geo.box(prop, Vector3(0.09, 0.09, 0.15), Vector3(-0.02, 1.03, 0.2), iron)
	Geo.box(prop, Vector3(0.62, 0.024, 0.06), Vector3(0.02, 1.01, -0.04), iron)
	var light := OmniLight3D.new()
	light.name = "IchorLight"
	light.light_color = Color(0.42, 0.95, 0.62)
	light.light_energy = 1.15
	light.omni_range = 4.6
	light.omni_attenuation = 1.3
	light.position = Vector3(0.42, 1.24, 0.12)
	prop.add_child(light)
	var label := Label3D.new()
	label.name = "BenchLabel"
	label.text = "ICHOR BENCH"
	label.font_size = 56
	label.pixel_size = 0.0052
	label.modulate = Color(0.62, 0.95, 0.72)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 1.62, 0.0)
	prop.add_child(label)
	return prop
