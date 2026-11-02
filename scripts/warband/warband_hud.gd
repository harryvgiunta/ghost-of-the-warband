class_name WarbandHud
extends CanvasLayer
## The in-battle readout for a possession game: the soul you are inside, the band
## you can jump into, the purse, and the one prompt that matters right now.
##
## It owns no gameplay state: `set_body()` is called by the scene whenever the
## soul moves and every value is re-read each frame, so a revive, a loot or a
## downed body is never a stale label. The tactical screen (O) is
## `WarbandScreen`; this is the thin layer you read while fighting.
##
## ## Where it sits
##
## The corners are the readout, and each one is one object:
##
##   * **Bottom left - the soul.** A bust of the body you are inside, framed by
##     the ledger's own iron clamp, with his name and state, health over stamina
##     and the skill row in the same plate. Every fact about the body you are
##     driving is in that one plate and nowhere else.
##   * **Top right - the band.** Headed by the purse (gold and the quiver, which
##     is what a bow runs out of), then one row per mercenary in the field: the
##     badge for how he fights, his name, his health and his state. The campaign
##     ledger hangs under it.
##   * **Centre.** The crosshair, the contextual prompt at the bottom and the two
##     banners at the top. There is no standing key legend: the controls are
##     taught by the lesson cards and the tips, not repeated over the fight.
##
## The top left and the bottom right belong to the world: `WarbandTips` and the
## branded sigil tile.

const Ledger = preload("res://scripts/ui/ledger_theme.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const AbilitySlotScript = preload("res://scripts/ability_slot.gd")
const CharacterPreview = preload("res://scripts/character_preview.gd")
const Looks = preload("res://scripts/warband/warband_looks.gd")
const State = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const Perf = preload("res://scripts/perf_probe.gd")

const LAYER := 6
## The two corner plates are the same width, and that width is the skill row:
## three 72 px tiles, the two gaps between them and the plate's own padding. It
## was 336 px around 96 px tiles - a quarter of a 1440 px screen for each corner,
## over the fight it is meant to sit beside.
const PANEL_WIDTH := 244.0
const MARGIN := 14.0
const PANEL_PAD := 10
## The bust: portrait proportions, framed by `clamp.png` nine-sliced at 14 px. It
## is a face for a corner, not a character sheet.
const PORTRAIT_SIZE := Vector2(66, 82)
const METER_HEIGHT := 7.0
## The colours the Blood Ledger already uses, read from the one theme so the HUD
## and the screens cannot drift apart.
const BONE := Ledger.BONE
const BONE_DIM := Ledger.BONE_DIM
const BRASS := Color("d9b877")
const MUTED := Color("9c8a6a")
## The disposition word under a band row: brass, but quiet enough to sit under a
## name it is not competing with.
const DISPOSITION_INK := Color("b79a68")
const ALIVE_INK := Color("7fd7c4")
const DOWNED_INK := Color("e08a3c")
const DEAD_INK := Color("8a827a")
const HEALTH_FILL := Color("77241c")
const STAMINA_FILL := Color("2f6f63")
const METER_BACK := Color("14181a")
const METER_EDGE := Color("46443f")
## How a disposition reads on the band rows: the small medallion of the ledger's
## icon set, and the word under the name.
const DISPOSITION_BADGE := {
	Contracts.DISPOSITION_TANK: "shield",
	Contracts.DISPOSITION_MELEE: "blade",
	Contracts.DISPOSITION_BOW: "bow",
}
## How long a break-off (or an ally coming back) is said in the banner, and how
## long that merc is kept quiet after it: the standing line carries the state, the
## banner is only the moment.
const AGGRO_BANNER_SECONDS := 3.5
const AGGRO_REPEAT_SECONDS := 6.0
## The skill row: three tiles and the two gaps between them are what the plates
## are wide, so the corners and the row share one measure. The tile is
## `AbilitySlot.TILE`, which the warband asks for at 72 px instead of the arena's
## 96: three of them plus these gaps and the plate padding is `PANEL_WIDTH`.
const TILE_GAP := 4
const TILE_SIZE := 72.0
## Nothing in the warband is clicked while the pointer is captured, so the
## reticle is the only thing that says where the soul is aiming. It is drawn by
## `Reticle` below, which carries its own measurements.

var _warband = null
var _body = null
var _merc_id := -1
var _merc_name := ""
## Who the soul is watching while it has no body of its own (see `set_watching`).
var _watching_name := ""
var _watching_holder := ""

var _name_label: Label
var _state_label: Label
var _health_label: Label
var _health_bar: ProgressBar
var _stamina_label: Label
var _stamina_bar: ProgressBar
## The bust: a second rig on its own SubViewport, drawn only when the body or its
## kit changes. `_portrait_sig` is what it is currently dressed in.
var _portrait = null
var _portrait_eye: TextureRect
var _portrait_sig := ""
## The health state the bust was last tinted for (`_tint_portrait`).
var _portrait_state := -2
var _ability_tiles: Array = []
var _squad_box: VBoxContainer
## One row per mercenary on the field, keyed by id and kept across frames: the
## rows carry textures now, so a repaint updates them where they stand instead of
## freeing and rebuilding the band every time somebody takes a hit.
var _rows: Dictionary = {}
var _party_label: Label
## The band's own fights: a standing line under the roster while an AI ally is in
## one (`set_aggro`), and the ids it named last frame so a break-off is announced
## once. `_aggro_mute` holds a merc's cooldown after that line, because a body
## pacing in and out of `engage_radius` is one break-off, not five.
var _aggro_box: VBoxContainer
var _aggro_label: Label
var _aggro_ids: Array[int] = []
var _aggro_names: Dictionary = {}   # merc_id -> the name last reported
var _aggro_mute: Dictionary = {}    # merc_id -> seconds of quiet left
var _purse_label: Label
## The campaign ledger block (see `set_quests`) and the signature of what it
## currently shows, so a repaint only happens when the objectives actually move.
var _quest_box: VBoxContainer
var _quest_sig := ""
var _prompt_label: Label
var _status_label: Label
var _status_seconds := 0.0
## The wrong-way banner: the one line in the warband that is a warning rather
## than an objective. It stays up until the world says the body turned around.
var _warning_label: Label
## The aim reticle, drawn at the screen centre while the mouse is captured.
var _reticle: Control

func _ready() -> void:
	layer = LAYER
	_build()
	set_process(true)

func configure(warband) -> void:
	_warband = warband
	if _warband != null and not _warband.changed.is_connected(_on_warband_changed):
		_warband.changed.connect(_on_warband_changed)
	_refresh_purse()
	_refresh_squad()
	_refresh_portrait()


## The purse moved or a piece of kit did: the rail and the bust both read the
## warband, and the bust re-dresses only if what it shows actually changed.
func _on_warband_changed() -> void:
	_refresh_purse()
	_refresh_portrait()

## The body the local soul is inside. `merc_name` is the roster name; a null
## body means the soul is between bodies (spectating a wipe).
func set_body(body, merc_name: String = "", merc_id: int = -1) -> void:
	_body = body
	_merc_id = merc_id
	_merc_name = merc_name
	if body != null and merc_id < 0:
		_merc_id = _roster_id_for(body)
	if _merc_id >= 0 and merc_name.is_empty() and _warband != null:
		_merc_name = _warband.roster.name_of(_merc_id)
	# Paint now: a tutorial card pauses the tree before `_process` ever runs, and
	# a body panel that reads "No body" behind it is a lie.
	_refresh_body()
	_refresh_squad()
	_refresh_portrait()

## The body the soul watches while every living body is taken: `merc_name` is
## the mercenary, `holder` the player inside him ("" for none). The body panel
## says so instead of "No body", so a player whose last body fell knows they are
## watching a friend, not looking at a frozen camera. `""` puts it away.
func set_watching(merc_name: String, holder: String = "") -> void:
	_watching_name = merc_name
	_watching_holder = holder
	_refresh_body()

## The two body-panel lines, for tests that must not read a private label.
func body_lines() -> Array[String]:
	var out: Array[String] = []
	if _name_label != null:
		out.append(_name_label.text)
	if _state_label != null:
		out.append(_state_label.text)
	return out

## One line under the crosshair: "HOLD G - PICK UP DORN", "K - loot Shortsword".
func set_prompt(text: String) -> void:
	if _prompt_label != null:
		_prompt_label.text = text
		_prompt_label.visible = not text.is_empty()

## The wrong-way banner: one loud line across the top of the screen, or "" to put
## it away. Unlike the status line it has no clock - the trail's own distance
## decides how long it is up, so it cannot lie about a body that is still walking
## the wrong way.
func set_warning(text: String) -> void:
	if _warning_label == null:
		return
	_warning_label.text = text
	_warning_label.visible = not text.is_empty()

## The banner itself, for the world and for a test that must not read a private
## label.
func warning_label() -> Label:
	return _warning_label


## The purse strip's text: gold and the party's quiver on one line, because a bow
## with no shafts is the one number a player has to be able to see at a glance.
func purse_line() -> String:
	return str(_purse_label.text) if _purse_label != null else ""


## The temporary banner's current text, for the same reason as `warning_label()`:
## a test reads the line instead of a private label.
func status_line() -> String:
	return str(_status_label.text) if _status_label != null else ""


## A temporary banner ("Reviving...", "Dorn is down").
func set_status(text: String, seconds: float = 2.5) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.visible = not text.is_empty()
	_status_seconds = maxf(0.0, seconds)

## The campaign ledger: one row per objective (`WarbandQuests.rows()`), repainted
## only when the signature moves. An empty list puts the block away.
func set_quests(rows: Array) -> void:
	if _quest_box == null:
		return
	var signature := ""
	for row in rows:
		if not (row is Dictionary):
			continue
		signature += "%s|%s|%s|%s;" % [str(row.get("title", "")), str(row.get("line", "")),
			str(row.get("detail", "")), str(row.get("done", false))]
	if signature == _quest_sig:
		return
	_quest_sig = signature
	for child in _quest_box.get_children():
		# Detached before it is freed: a queued free leaves the old rows in the
		# tree for the rest of the frame, and a reader (or a test) would still see
		# objectives the ledger no longer holds.
		_quest_box.remove_child(child)
		child.queue_free()
	var panel := _quest_box.get_parent() as Control
	if panel != null:
		panel.visible = not signature.is_empty()
	if signature.is_empty():
		return
	for row in rows:
		if not (row is Dictionary):
			continue
		var entry: Dictionary = row
		var title := Label.new()
		title.text = str(entry.get("title", ""))
		title.add_theme_font_size_override("font_size", 11)
		title.add_theme_color_override("font_color",
			Color(0.96, 0.83, 0.55) if not bool(entry.get("done", false)) else Color(0.62, 0.86, 0.60))
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_quest_box.add_child(title)
		var detail := Label.new()
		detail.text = "%s   ·   %s" % [str(entry.get("line", "")), str(entry.get("detail", ""))]
		detail.add_theme_font_size_override("font_size", 10)
		detail.add_theme_color_override("font_color", Color(0.82, 0.79, 0.68))
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_quest_box.add_child(detail)

## The ledger block itself, and the text it currently carries, for a test that
## must not read a private label.
func quest_panel() -> Control:
	if _quest_box == null:
		return null
	return _quest_box.get_parent() as Control

func quest_lines() -> Array[String]:
	var out: Array[String] = []
	if _quest_box == null:
		return out
	for child in _quest_box.get_children():
		if child is Label:
			out.append(str((child as Label).text))
	return out

func _process(delta: float) -> void:
	Perf.begin("hud")
	# The reticle belongs to the aiming body, so it is up exactly while the pointer
	# is captured: a panel opens, the cursor comes back, the crosshair goes away.
	if _reticle != null:
		_reticle.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and _body != null
	if _status_seconds > 0.0:
		_status_seconds -= delta
		if _status_seconds <= 0.0:
			_status_label.visible = false
	# A merc's quiet window after its break-off line. Counted here rather than in
	# `set_aggro` so it runs on the HUD's own clock whatever the world does.
	for merc_id in _aggro_mute.keys():
		var left := float(_aggro_mute[merc_id]) - delta
		if left <= 0.0:
			_aggro_mute.erase(merc_id)
		else:
			_aggro_mute[merc_id] = left
	_refresh_body()
	_refresh_squad()
	Perf.end()

func _build() -> void:
	var root_control := Control.new()
	root_control.name = "Root"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)

	_reticle = Reticle.new()
	_reticle.name = "Crosshair"
	_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(_reticle)

	_build_soul_plate(root_control)
	_build_band_plate(root_control)

	_prompt_label = Label.new()
	_prompt_label.name = "Prompt"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.position = Vector2(-160, -96)
	_prompt_label.custom_minimum_size = Vector2(320, 0)
	_prompt_label.add_theme_font_size_override("font_size", 17)
	_prompt_label.visible = false
	root_control.add_child(_prompt_label)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status_label.position = Vector2(-180, 74)
	_status_label.custom_minimum_size = Vector2(360, 0)
	_status_label.add_theme_font_size_override("font_size", 17)
	_status_label.visible = false
	root_control.add_child(_status_label)

	# The warning sits above the status line, in gold on a blood outline: it is
	# the only banner that must be read from the corner of an eye while a squad
	# is being walked the wrong way up a dark trail.
	_warning_label = Label.new()
	_warning_label.name = "Warning"
	_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_warning_label.position = Vector2(-360, 16)
	_warning_label.custom_minimum_size = Vector2(720, 0)
	_warning_label.add_theme_font_size_override("font_size", 26)
	_warning_label.add_theme_color_override("font_color", Color(1.0, 0.79, 0.26))
	_warning_label.add_theme_color_override("font_outline_color", Color(0.52, 0.03, 0.02))
	_warning_label.add_theme_constant_override("outline_size", 7)
	_warning_label.visible = false
	root_control.add_child(_warning_label)


# --- the soul's plate ------------------------------------------------------

## The bottom left: the body the soul is inside, as one plate. The bust in the
## ledger's iron clamp, the name and its state, health over stamina and the skill
## row those two pay for - all of it in the same object, so the eye never has to
## cross the screen to read the body it is driving.
func _build_soul_plate(parent: Control) -> void:
	var column := VBoxContainer.new()
	column.name = "SoulColumn"
	column.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.offset_left = MARGIN
	column.offset_right = MARGIN + PANEL_WIDTH
	column.offset_top = -MARGIN
	column.offset_bottom = -MARGIN
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(column)

	var plate := PanelContainer.new()
	plate.name = "SoulPanel"
	plate.add_theme_stylebox_override("panel", _plate_style())
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(plate)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 6)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(body)

	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(head)
	head.add_child(_build_portrait())

	var vitals := VBoxContainer.new()
	vitals.name = "Vitals"
	vitals.add_theme_constant_override("separation", 2)
	vitals.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vitals.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(vitals)

	_name_label = Label.new()
	_name_label.name = "Name"
	_name_label.text = "No body"
	_name_label.add_theme_font_override("font", Ledger.FONT_DISPLAY)
	_name_label.add_theme_font_size_override("font_size", 17)
	_name_label.add_theme_color_override("font_color", BONE)
	_name_label.clip_text = true
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vitals.add_child(_name_label)

	# The state line carries two different things: the one word a living, downed
	# or dead body is (on the ledger's own chip), or the sentence a soul with no
	# body has to say. Same label, no chip in the second case.
	_state_label = Label.new()
	_state_label.name = "State"
	_state_label.add_theme_font_size_override("font_size", 9)
	_state_label.add_theme_color_override("font_color", ALIVE_INK)
	_state_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vitals.add_child(_state_label)

	# Health over stamina, both paid into the skill row underneath: the two bars
	# are the same widget in two colours, each with the number it is spent down to.
	var health := _meter_row(vitals, "HEALTH", HEALTH_FILL)
	_health_bar = health[0]
	_health_label = health[1]
	_health_bar.name = "Health"
	var stamina := _meter_row(vitals, "STAMINA", STAMINA_FILL)
	_stamina_bar = stamina[0]
	_stamina_label = stamina[1]
	_stamina_bar.name = "Stamina"

	# The hairline that ties the bars to the skill row: one rule, then the tiles.
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = Color(0.86, 0.72, 0.42, 0.22)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(rule)

	var ability_row := HBoxContainer.new()
	ability_row.name = "Abilities"
	ability_row.add_theme_constant_override("separation", TILE_GAP)
	ability_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ability_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(ability_row)
	_ability_tiles.clear()
	for index in AbilityRules.SLOT_COUNT:
		var tile = AbilitySlotScript.new()
		tile.name = "Ability%d" % (index + 1)
		tile.configure(index, TILE_SIZE)
		ability_row.add_child(tile)
		_ability_tiles.append(tile)


## The bust: the body in the iron clamp the menus are built out of. It renders
## only when the body or its kit changes (`_refresh_portrait`), so a static
## portrait costs nothing a frame.
func _build_portrait() -> Control:
	var frame := Panel.new()
	frame.name = "Portrait"
	frame.custom_minimum_size = PORTRAIT_SIZE
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.052, 0.060, 0.062, 0.97)
	back.set_corner_radius_all(3)
	frame.add_theme_stylebox_override("panel", back)

	_portrait = CharacterPreview.new()
	_portrait.name = "Bust"
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait.offset_left = 4
	_portrait.offset_top = 4
	_portrait.offset_right = -4
	_portrait.offset_bottom = -4
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.visible = false
	_portrait.built.connect(_refresh_portrait)
	frame.add_child(_portrait)

	# No body to show: the theme's own eye, since a soul watching a friend is
	# the one state that is not a portrait of anybody.
	_portrait_eye = TextureRect.new()
	_portrait_eye.name = "NoBody"
	_portrait_eye.texture = Ledger.icon_large("eye")
	_portrait_eye.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_eye.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_eye.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait_eye.offset_left = 14
	_portrait_eye.offset_top = 20
	_portrait_eye.offset_right = -14
	_portrait_eye.offset_bottom = -20
	_portrait_eye.modulate = Color(1.0, 1.0, 1.0, 0.5)
	_portrait_eye.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_portrait_eye)

	var clamp := NinePatchRect.new()
	clamp.name = "Clamp"
	clamp.texture = load(Ledger.DIR + "clamp.png")
	clamp.patch_margin_left = 14
	clamp.patch_margin_right = 14
	clamp.patch_margin_top = 14
	clamp.patch_margin_bottom = 14
	clamp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(clamp)
	return frame


## One labelled meter: a caps caption, the bar and the number, so health and
## stamina read apart at a glance instead of by colour alone. The three columns
## are as narrow as the widest string each carries ("STAMINA", "1000 / 1000").
func _meter_row(parent: Node, caption: String, fill: Color) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var cap := _text(row, caption, 8, MUTED)
	cap.custom_minimum_size = Vector2(32, 0)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(36, METER_HEIGHT)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.value = 1.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _meter_trough())
	bar.add_theme_stylebox_override("fill", _meter_fill(fill))
	row.add_child(bar)
	var value := _text(row, "", 9, BONE_DIM)
	value.custom_minimum_size = Vector2(48, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return [bar, value]


# --- the band's plate ------------------------------------------------------

## The top right: the purse on a rail, then a row per mercenary on the field and
## how he fights. The campaign ledger is its own smaller plate under it.
func _build_band_plate(parent: Control) -> void:
	var column := VBoxContainer.new()
	column.name = "BandColumn"
	column.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	column.offset_left = -MARGIN - PANEL_WIDTH
	column.offset_right = -MARGIN
	column.offset_top = MARGIN
	column.offset_bottom = MARGIN
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(column)

	var plate := PanelContainer.new()
	plate.name = "BandPanel"
	plate.add_theme_stylebox_override("panel", _plate_style())
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(plate)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 4)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(body)

	# The purse rides the header rail: a bow with no shafts is as raw a number as
	# the gold, and both are the band's.
	var rail := PanelContainer.new()
	rail.name = "PurseRail"
	rail.add_theme_stylebox_override("panel", _rail_style())
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(rail)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.add_child(head)
	var title := _text(head, "THE BAND", 9, BRASS)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_purse_label = _text(head, "", 12, BONE)
	_purse_label.name = "Purse"
	_purse_label.add_theme_font_override("font", Ledger.FONT_DISPLAY)
	_purse_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# One row per mercenary on the field. `_refresh_squad` keeps these nodes and
	# updates them in place: the rows carry textures, and a body taking a hit must
	# not rebuild the band.
	_squad_box = VBoxContainer.new()
	_squad_box.name = "Squad"
	_squad_box.add_theme_constant_override("separation", 3)
	_squad_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_squad_box)

	# How the band picks its fights. It is a state, not a key line: the O screen
	# is where it is changed.
	_party_label = _text(body, "", 8, MUTED)
	_party_label.name = "PartyMode"
	_party_label.visible = false

	# The band's fights, outside the roster's own repaint, written by `set_aggro`
	# alone and hidden while the band is whole.
	_aggro_box = VBoxContainer.new()
	_aggro_box.name = "Aggro"
	_aggro_box.add_theme_constant_override("separation", 1)
	_aggro_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_aggro_box)
	_aggro_label = Label.new()
	_aggro_label.name = "AggroLine"
	_aggro_label.add_theme_font_size_override("font_size", 9)
	_aggro_label.add_theme_color_override("font_color", Color(0.96, 0.71, 0.34))
	_aggro_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_aggro_label.custom_minimum_size = Vector2(PANEL_WIDTH - 2 * PANEL_PAD, 0)
	_aggro_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aggro_label.visible = false
	_aggro_box.add_child(_aggro_label)

	# The campaign ledger: one block per objective the quartermaster has handed
	# over, read from `WarbandQuests`. It is a tracker, not a menu - nothing here
	# is clicked while the pointer is captured - and it stays hidden until there
	# is an order to show.
	var quest_panel := PanelContainer.new()
	quest_panel.name = "QuestPanel"
	quest_panel.add_theme_stylebox_override("panel", _plate_style())
	quest_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quest_panel.visible = false
	column.add_child(quest_panel)
	_quest_box = VBoxContainer.new()
	_quest_box.name = "Quests"
	_quest_box.add_theme_constant_override("separation", 2)
	_quest_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quest_panel.add_child(_quest_box)


# --- the ledger's materials ------------------------------------------------

## A plate: the menus' planished iron slab, with its nine-slice margins turned
## into the padding the HUD's content sits inside.
func _plate_style() -> StyleBoxTexture:
	var box := Ledger.iron_panel()
	box.content_margin_left = PANEL_PAD
	box.content_margin_right = PANEL_PAD
	box.content_margin_top = PANEL_PAD - 2
	box.content_margin_bottom = PANEL_PAD - 2
	return box


## The header band: the same rail every window is titled on.
func _rail_style() -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = load(Ledger.DIR + "rail.png")
	box.texture_margin_left = 12
	box.texture_margin_right = 12
	box.texture_margin_top = 0
	box.texture_margin_bottom = 0
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 1
	box.content_margin_bottom = 2
	return box


func _meter_trough() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = METER_BACK
	box.border_color = METER_EDGE
	box.set_border_width_all(1)
	box.set_corner_radius_all(2)
	return box


func _meter_fill(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(2)
	return box


func _text(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

## The stamina bar, for tests and for any scene that wants to highlight it.
func stamina_bar() -> ProgressBar:
	return _stamina_bar

## One tile per `AbilityRules.SLOT_COUNT`, in key order (1, 2, 3).
func ability_tiles() -> Array:
	return _ability_tiles.duplicate()

func _refresh_body() -> void:
	if _name_label == null:
		return
	if _body == null or not is_instance_valid(_body):
		if not _watching_name.is_empty():
			_name_label.text = "WATCHING  %s" % _watching_name
			_state_label.text = ("%s is inside  ·  no body is free" % _watching_holder) \
				if not _watching_holder.is_empty() else "No body is free"
			_paint_state(-1)
		else:
			_name_label.text = _merc_name if not _merc_name.is_empty() else "No body"
			if _warband != null and _merc_id >= 0:
				var last := int(_warband.roster.state_of(_merc_id))
				_state_label.text = Contracts.state_name(last).to_upper()
				_paint_state(last)
			else:
				_state_label.text = "The warband is down"
				_paint_state(-1)
		_health_bar.value = 0.0
		_health_label.text = ""
		_stamina_bar.value = 0.0
		_stamina_label.text = ""
		# No body, no skills: hide every tile rather than leave the pool's last
		# grants up over a spectator.
		for tile in _ability_tiles:
			tile.update_state({})
		_tint_portrait(-1)
		return
	var health: float = float(_body.get("health"))
	var max_health: float = maxf(1.0, float(_body.get("max_health")))
	var downed: bool = bool(_body.get("downed"))
	var state := Contracts.HealthState.DOWNED if downed else (
		Contracts.HealthState.ALIVE if bool(_body.get("alive")) else Contracts.HealthState.DEAD)
	_name_label.text = _merc_name if not _merc_name.is_empty() else str(_body.get("display_name"))
	_state_label.text = Contracts.state_name(state).to_upper()
	_paint_state(state)
	_health_bar.max_value = max_health
	_health_bar.value = health
	_health_label.text = "%d / %d" % [int(round(health)), int(round(max_health))]
	var stamina: float = float(_body.get("stamina"))
	var max_stamina: float = maxf(1.0, float(_body.get("max_stamina")))
	_stamina_bar.max_value = max_stamina
	_stamina_bar.value = stamina
	_stamina_label.text = "%d / %d" % [int(round(stamina)), int(round(max_stamina))]
	_refresh_skills()
	_tint_portrait(state)


## The state line: the ledger's own chip for a body that is alive, downed or
## dead, and plain type for the sentence a soul with no body has to read.
## `-1` is neither: "no body" is not a health state.
func _paint_state(state: int) -> void:
	if _state_label == null:
		return
	if state < 0:
		_state_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		_state_label.add_theme_color_override("font_color", MUTED)
		return
	var ink := ALIVE_INK
	var chip := "alive"
	match state:
		Contracts.HealthState.DOWNED:
			ink = DOWNED_INK
			chip = "downed"
		Contracts.HealthState.DEAD:
			ink = DEAD_INK
			chip = "dead"
	_state_label.add_theme_color_override("font_color", ink)
	_state_label.add_theme_stylebox_override("normal", _chip_style(chip))

## The three skill tiles, read from the body's own runner every frame. A body
## with no grant in a slot hides that tile instead of advertising a key that
## would do nothing.
func _refresh_skills() -> void:
	if _ability_tiles.is_empty():
		return
	var runner = _body.get("ability") if _body != null and is_instance_valid(_body) else null
	for index in _ability_tiles.size():
		var state := {}
		if runner != null and is_instance_valid(runner) and runner.has_method("hud_state"):
			state = runner.hud_state(index)
		var tile = _ability_tiles[index]
		tile.update_state(state)
		# The tile is the shared arena widget, which advertises the arena's
		# `SHIFT + n`. The warband fires the same slots from the number row, so
		# only the key line is rewritten here - one tile design, two bindings.
		var key_label = tile.get("_key")
		if key_label != null:
			key_label.text = str(index + 1)

func _refresh_squad() -> void:
	if _squad_box == null or _warband == null:
		return
	# The squad is the field: a name waiting in the reserve has no body to show.
	var ids: Array[int] = []
	for merc_id in _warband.roster.ids():
		if not _warband.roster.is_reserve(merc_id):
			ids.append(merc_id)
	# A body that left the field (or was finished) loses its row at once; the
	# rest are kept and painted where they stand. The rows carry textures now, so
	# a band taking hits must not rebuild them frame after frame.
	for merc_id in _rows.keys():
		if ids.has(int(merc_id)):
			continue
		var stale: Dictionary = _rows[merc_id]
		_squad_box.remove_child(stale["root"])
		(stale["root"] as Node).queue_free()
		_rows.erase(merc_id)
	for index in ids.size():
		var merc_id := ids[index]
		if not _rows.has(merc_id):
			_rows[merc_id] = _make_row(merc_id)
		_squad_box.move_child(_rows[merc_id]["root"], index)
		_apply_row(merc_id)
	# How the band picks its fights - the state, not the key: O is where it moves.
	var mode := str(_warband.get("party_mode")) if _warband.get("party_mode") != null else ""
	if _party_label != null:
		_party_label.text = ("PARTY  %s" % mode.to_upper()) if not mode.is_empty() else ""
		_party_label.visible = not mode.is_empty()


## One mercenary's row: the badge for how he fights, his name over that word, his
## health and his state. Built once per body, then updated in place.
func _make_row(merc_id: int) -> Dictionary:
	var root := HBoxContainer.new()
	root.name = "Mercenary%d" % merc_id
	root.add_theme_constant_override("separation", 5)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_squad_box.add_child(root)

	var badge := TextureRect.new()
	badge.name = "Badge"
	badge.custom_minimum_size = Vector2(18, 18)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(badge)

	var cell := VBoxContainer.new()
	cell.name = "Identity"
	cell.add_theme_constant_override("separation", 0)
	cell.custom_minimum_size = Vector2(54, 0)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cell)
	var name_label := _text(cell, "", 12, BONE)
	name_label.name = "Title"
	name_label.add_theme_font_override("font", Ledger.FONT_DISPLAY)
	var style_label := _text(cell, "", 8, DISPOSITION_INK)
	style_label.name = "Disposition"

	var bar := ProgressBar.new()
	bar.name = "Health"
	bar.custom_minimum_size = Vector2(28, 6)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.value = 1.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _meter_trough())
	bar.add_theme_stylebox_override("fill", _meter_fill(HEALTH_FILL))
	root.add_child(bar)

	var state := _text(root, "", 8, BONE_DIM)
	state.name = "State"
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state.custom_minimum_size = Vector2(38, 0)
	return {"root": root, "badge": badge, "name": name_label, "style": style_label,
		"bar": bar, "state": state, "signature": ""}


## Paint one row from the record. Everything is read off the roster, so the row
## and the squad's own brain cannot disagree about how a body fights or what it
## has left; the strings are only rewritten when the fact behind them moves.
func _apply_row(merc_id: int) -> void:
	var row: Dictionary = _rows.get(merc_id, {})
	if row.is_empty():
		return
	var record: Dictionary = _warband.roster.find(merc_id)
	if record.is_empty():
		return
	var state := int(record.get("state", Contracts.HealthState.DEAD))
	var max_hp := maxf(1.0, float(record.get("max_health", 1.0)))
	var health := clampf(float(record.get("health", 0.0)), 0.0, max_hp)
	var percent := int(round(health / max_hp * 100.0))
	var style := str(_warband.roster.disposition_of(merc_id))
	var active := merc_id == _merc_id
	var signature := "%d|%d|%s|%s" % [state, percent, style, active]
	if signature != str(row.get("signature", "")):
		row["signature"] = signature
		var name_label: Label = row["name"]
		name_label.text = str(record.get("name", "?"))
		name_label.add_theme_color_override("font_color", BRASS if active else BONE)
		(row["style"] as Label).text = Contracts.disposition_label(style)
		var badge: TextureRect = row["badge"]
		badge.texture = Ledger.icon_small(str(DISPOSITION_BADGE.get(style, "blade")))
		# The body the soul is inside is the one row that is lit.
		badge.modulate = Color.WHITE if active else Color(0.86, 0.84, 0.80, 0.86)
		var state_label: Label = row["state"]
		match state:
			Contracts.HealthState.DOWNED:
				state_label.text = "DOWNED"
				state_label.add_theme_color_override("font_color", DOWNED_INK)
			Contracts.HealthState.DEAD:
				state_label.text = "DEAD"
				state_label.add_theme_color_override("font_color", DEAD_INK)
			_:
				state_label.text = "%d%%" % percent
				state_label.add_theme_color_override("font_color", BONE_DIM)
	var bar: ProgressBar = row["bar"]
	bar.max_value = max_hp
	bar.value = health


# --- the bust --------------------------------------------------------------

## Dress the bust, or put it away when the soul has no body to show.
##
## The portrait is a second `Archer` in its own SubViewport, so it is built for
## the body currently inside the soul and re-dressed only when that body or its
## kit changes: `set_body` and `Warband.changed` are the only callers, and the
## signature below makes the second of those free for a purse or an arrow.
func _refresh_portrait() -> void:
	if _portrait == null:
		return
	var dress: bool = _body != null and is_instance_valid(_body) and _merc_id > 0 \
		and _warband != null and _warband.roster.has(_merc_id) \
		and DisplayServer.get_name() != "headless"
	if not dress:
		_portrait.visible = false
		_portrait_sig = ""
		_portrait_state = -2
		if _portrait_eye != null:
			_portrait_eye.visible = true
		return
	_portrait.visible = true
	if _portrait_eye != null:
		_portrait_eye.visible = false
	var gear: Dictionary = _warband.roster.equipped_of(_merc_id)
	var signature := "%d|" % _merc_id
	for slot in Contracts.SLOT_ORDER:
		signature += "%s," % str(gear.get(slot, ""))
	if signature == _portrait_sig:
		return
	_portrait_sig = signature
	var armor := {}
	for slot in ArmorData.SLOTS:
		armor[slot] = ArmorData.set_of_item(str(gear.get(slot, "")))
	# The trinkets ride the same three ids the gear page hands the live stage, so
	# the man in the HUD wears what the man on the page wears.
	var worn := {
		"neck": str(gear.get("neck", "")),
		"ring1": str(gear.get("ring1", "")),
		"ring2": str(gear.get("ring2", "")),
		"off": str(gear.get("off", "")),
	}
	var loadout := State.build_loadout(str(gear.get("main", "")), str(gear.get("off", "")),
		armor, worn)
	_portrait.set_appearance(Looks.profile_for(_merc_id))
	_portrait.set_bust(true)
	_portrait.apply_kit(loadout, worn)
	_portrait.flash()


## The bust goes grey with the body it shows: a downed man is not a portrait of
## an able one. Cheap enough for the frame because it only writes on a change.
##
## The lit tint is over white: the preview's own lights are set for a stage, and a
## face at 96 px on an iron plate needs a little more of it to read.
func _tint_portrait(state: int) -> void:
	if _portrait == null or state == _portrait_state:
		return
	_portrait_state = state
	_portrait.modulate = Color(1.16, 1.13, 1.08) if state == Contracts.HealthState.ALIVE \
		else Color(0.58, 0.56, 0.54)


func _chip_style(key: String) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = load(Ledger.DIR + "chip_%s.png" % key)
	box.texture_margin_left = 12
	box.texture_margin_right = 12
	box.texture_margin_top = 8
	box.texture_margin_bottom = 8
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	return box


# --- the band's fights ------------------------------------------------------

## The band's own fights, as `SquadDrive.engaged_allies()` reports them.
##
## An AI ally that broke off used to be something the player found out by turning
## round: the squad's only cue was `voice_aggro()`, and that row rolls its line at
## one engagement in a hundred, so most break-offs were silent and the rest were a
## voice heard once at the body. Now the break-off is said in the banner once, and
## the state of it stands under the roster while the fight lasts -
## `IN THE FIGHT  ·  Sorn, Dorn  ·  34 m back-left` - so a squad left behind is a
## fact on the screen, not a thing to walk into.
##
## Called every frame by the world. Only the *set* of engaged allies is compared,
## so the standing line follows a walking distance without re-announcing it, and a
## merc's own quiet window keeps a body pacing in and out of `engage_radius` from
## spamming the banner.
func set_aggro(entries: Array) -> void:
	if _aggro_label == null:
		return
	# The common case, every frame of a walk with nothing fighting: nothing to
	# paint and nothing was painted. Skipped before any string is built.
	if entries.is_empty() and _aggro_ids.is_empty() and _aggro_label.text.is_empty():
		return
	var engaged: Array[int] = []
	var named: Dictionary = {}
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var merc_id := int((entry as Dictionary).get("merc_id", 0))
		if merc_id <= 0 or engaged.has(merc_id):
			continue
		engaged.append(merc_id)
		named[merc_id] = str((entry as Dictionary).get("name", "a body"))
	var entered: Array[int] = []
	for merc_id in engaged:
		if _aggro_ids.has(merc_id):
			continue
		# Still inside its quiet window: this body was just announced, and a
		# fight that flickers at the edge of reach is one break-off, not five.
		if float(_aggro_mute.get(merc_id, 0.0)) > 0.0:
			continue
		entered.append(merc_id)
	var left: Array[int] = []
	for merc_id in _aggro_ids:
		if not engaged.has(merc_id):
			left.append(merc_id)
	var was_named := _aggro_names.duplicate()
	_aggro_ids = engaged
	_aggro_names = named
	_aggro_label.text = _aggro_text(entries, engaged, named)
	_aggro_label.visible = not _aggro_label.text.is_empty()
	if not entered.is_empty():
		for merc_id in entered:
			_aggro_mute[merc_id] = AGGRO_REPEAT_SECONDS
		var nearest := _nearest_engaged(entries, entered)
		var back := _bearing_suffix(nearest)
		if entered.size() == 1:
			var who := str(named.get(entered[0], "A squadmate"))
			var what := str(nearest.get("threat", ""))
			set_status("%s breaks off%s." % [who, back] if what.is_empty() else
				"%s breaks off: %s%s." % [who, what, back], AGGRO_BANNER_SECONDS)
		else:
			var what := str(nearest.get("threat", ""))
			var line := "%d of the warband break off" % entered.size()
			if not what.is_empty():
				line += ": " + what
			set_status(line + back + ".", AGGRO_BANNER_SECONDS)
		return
	if not left.is_empty():
		# The other half of the notifier: a fight that ended has to end on the
		# screen too, or the last thing the player read is a band under attack.
		if left.size() == 1:
			set_status("%s is back with the band." % str(was_named.get(left[0], "A squadmate")),
				AGGRO_BANNER_SECONDS)
		else:
			set_status("%d are back with the band." % left.size(), AGGRO_BANNER_SECONDS)


## The standing line, for the world and for a test that must not read a private
## label.
func aggro_line() -> String:
	return str(_aggro_label.text) if _aggro_label != null else ""


## `IN THE FIGHT  ·  who  ·  what  ·  how far and which way`. The threat is named
## only when one ally is in it: a scrum of three is three fights, and the line is
## about where the band is, not what it found.
func _aggro_text(entries: Array, engaged: Array[int], named: Dictionary) -> String:
	if engaged.is_empty():
		return ""
	var nearest := _nearest_engaged(entries, engaged)
	var back := _bearing_suffix(nearest)
	if engaged.size() == 1:
		var what := str(nearest.get("threat", ""))
		if what.is_empty():
			return "IN THE FIGHT  ·  %s%s" % [str(named.get(engaged[0], "a body")), back]
		return "IN THE FIGHT  ·  %s  ·  %s%s" % [str(named.get(engaged[0], "a body")), what, back]
	var shown: Array[String] = []
	for index in mini(engaged.size(), 2):
		shown.append(str(named.get(engaged[index], "a body")))
	var more := "" if engaged.size() <= 2 else " +%d" % (engaged.size() - 2)
	return "IN THE FIGHT  ·  %s%s%s" % [", ".join(shown), more, back]


## `  ·  34 m back-left`, or nothing when the report carried no distance. The
## separator is the HUD's own, so the line reads as one strip.
func _bearing_suffix(entry: Dictionary) -> String:
	if entry.is_empty():
		return ""
	return "  ·  %d m %s" % [int(entry.get("distance", 0)),
		str(entry.get("bearing", "away"))]


## The closest of `ids` in a report: the banner quotes the nearest fight, because
## that is the one a body would turn round for.
func _nearest_engaged(entries: Array, ids: Array) -> Dictionary:
	var best := {}
	for entry in entries:
		if not (entry is Dictionary):
			continue
		if not ids.has(int((entry as Dictionary).get("merc_id", 0))):
			continue
		if best.is_empty() \
				or int((entry as Dictionary).get("distance", 0)) < int(best.get("distance", 0)):
			best = entry
	return best

## The purse on the band's header rail: gold and the party's quiver on one line,
## because a bow with no shafts is the one number a player has to be able to see at
## a glance. The ritual essence has its own ledger on the altar screen; it is not a
## number a fight turns on.
func _refresh_purse() -> void:
	if _purse_label == null:
		return
	if _warband == null:
		_purse_label.text = ""
		return
	_purse_label.text = "%d gold  ·  %d arrows" % [_warband.gold(), _warband.arrows()]

func _roster_id_for(body) -> int:
	if _warband == null or body == null:
		return -1
	for body_id in _warband.souls.body_ids():
		if _warband.souls.body_node(body_id) == body:
			return int(body_id)
	return -1


## The crosshair itself: four arms around a dot, drawn at the centre of whatever
## the control covers. It is a plain `Control` with its own `_draw`, so it costs a
## handful of lines a frame and never touches the panels above it.
class Reticle extends Control:
	const RETICLE_ARM := 9.0
	const RETICLE_GAP := 4.0
	const RETICLE_WIDTH := 2.0
	const RETICLE_COLOR := Color(0.93, 0.89, 0.82, 0.92)
	const RETICLE_DOT := 1.6

	func _draw() -> void:
		var centre: Vector2 = size * 0.5
		var arm := RETICLE_ARM
		var gap := RETICLE_GAP
		for axis in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(centre + axis * gap, centre + axis * (gap + arm),
				RETICLE_COLOR, RETICLE_WIDTH, true)
		draw_circle(centre, RETICLE_DOT, RETICLE_COLOR)
