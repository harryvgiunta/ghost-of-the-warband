class_name WarbandHud
extends CanvasLayer
## The in-battle readout for a possession game: the body you are inside, the
## squad you can jump into, and the one prompt that matters right now.
##
## It owns no gameplay state: `set_body()` is called by the scene whenever the
## soul moves and every value is re-read each frame, so a revive, a loot or a
## downed body is never a stale label. The tactical screen (O) is
## `WarbandScreen`; this is the thin layer you read while fighting.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Catalog = preload("res://scripts/warband/cruor_catalog.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const AbilitySlotScript = preload("res://scripts/ability_slot.gd")

const LAYER := 6
const BAR_SIZE := Vector2(260, 10)
## How long a break-off (or an ally coming back) is said in the banner, and how
## long that merc is kept quiet after it: the standing line carries the state, the
## banner is only the moment.
const AGGRO_BANNER_SECONDS := 3.5
const AGGRO_REPEAT_SECONDS := 6.0
## The skill row under the crosshair: three 96 px tiles, so the HUD shows what
## the number row will do before the player presses it.
const TILE_SIZE := Vector2(96, 96)
const TILE_GAP := 6
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
var _ability_tiles: Array = []
var _squad_box: VBoxContainer
var _squad_sig := ""
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
var _essence_label: Label
## The campaign ledger block (see `set_quests`) and the signature of what it
## currently shows, so a repaint only happens when the objectives actually move.
var _quest_box: VBoxContainer
var _quest_sig := ""
var _prompt_label: Label
var _hint_label: Label
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
	if _warband != null and not _warband.changed.is_connected(_refresh_purse):
		_warband.changed.connect(_refresh_purse)
	_refresh_purse()

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

## The standing key line: what to press on this beat ("G - cut the latch",
## "R - Rending Strike"). Unlike the prompt it does not vanish on its own, so a
## player who looks away for a second can find the controls again.
func set_hint(text: String) -> void:
	if _hint_label == null:
		return
	_hint_label.text = text
	_hint_label.visible = not text.is_empty()

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
		title.add_theme_font_size_override("font_size", 13)
		title.add_theme_color_override("font_color",
			Color(0.96, 0.83, 0.55) if not bool(entry.get("done", false)) else Color(0.62, 0.86, 0.60))
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_quest_box.add_child(title)
		var detail := Label.new()
		detail.text = "%s   ·   %s" % [str(entry.get("line", "")), str(entry.get("detail", ""))]
		detail.add_theme_font_size_override("font_size", 12)
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

	var frame := PanelContainer.new()
	frame.name = "BodyPanel"
	frame.position = Vector2(18, 16)
	frame.custom_minimum_size = Vector2(BAR_SIZE.x + 28, 0)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	frame.add_child(column)

	_name_label = Label.new()
	_name_label.text = "No body"
	column.add_child(_name_label)
	_state_label = Label.new()
	_state_label.add_theme_font_size_override("font_size", 12)
	column.add_child(_state_label)
	_health_bar = ProgressBar.new()
	_health_bar.custom_minimum_size = BAR_SIZE
	_health_bar.show_percentage = false
	_health_bar.max_value = 100.0
	_health_bar.value = 100.0
	column.add_child(_health_bar)
	_health_label = Label.new()
	_health_label.add_theme_font_size_override("font_size", 11)
	column.add_child(_health_label)
	# Stamina sits under health in the same panel: every skill and every sprint
	# is paid from it, so it belongs next to the number it is spent beside.
	_stamina_bar = ProgressBar.new()
	_stamina_bar.name = "Stamina"
	_stamina_bar.custom_minimum_size = BAR_SIZE
	_stamina_bar.show_percentage = false
	_stamina_bar.max_value = 100.0
	_stamina_bar.value = 100.0
	column.add_child(_stamina_bar)
	_stamina_label = Label.new()
	_stamina_label.add_theme_font_size_override("font_size", 11)
	column.add_child(_stamina_label)

	var squad_panel := PanelContainer.new()
	squad_panel.name = "SquadPanel"
	squad_panel.position = Vector2(18, 128)
	squad_panel.custom_minimum_size = Vector2(300, 0)
	squad_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(squad_panel)
	_squad_box = VBoxContainer.new()
	_squad_box.name = "Squad"
	_squad_box.add_theme_constant_override("separation", 1)
	_squad_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	squad_panel.add_child(_squad_box)

	# The band's fights, under the roster and outside its repaint: `_refresh_squad`
	# frees every row it owns, so this line lives in its own box and is written by
	# `set_aggro` alone. Hidden while the band is whole.
	_aggro_box = VBoxContainer.new()
	_aggro_box.name = "Aggro"
	_aggro_box.add_theme_constant_override("separation", 1)
	_aggro_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	squad_panel.add_child(_aggro_box)
	_aggro_label = Label.new()
	_aggro_label.name = "AggroLine"
	_aggro_label.add_theme_font_size_override("font_size", 11)
	_aggro_label.add_theme_color_override("font_color", Color(0.96, 0.71, 0.34))
	_aggro_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_aggro_label.custom_minimum_size = Vector2(282, 0)
	_aggro_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aggro_label.visible = false
	_aggro_box.add_child(_aggro_label)

	_purse_label = Label.new()
	_purse_label.name = "Purse"
	_purse_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_purse_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_purse_label.position = Vector2(-20, 16)
	_purse_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root_control.add_child(_purse_label)

	_essence_label = Label.new()
	_essence_label.name = "Essence"
	_essence_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_essence_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_essence_label.position = Vector2(-20, 38)
	_essence_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_essence_label.add_theme_font_size_override("font_size", 12)
	root_control.add_child(_essence_label)

	# The campaign ledger, under the purse: one block per objective the
	# quartermaster has handed over, read from `WarbandQuests`. It is a tracker,
	# not a menu - nothing here is clicked while the pointer is captured - and it
	# stays hidden until there is an order to show.
	var quest_panel := PanelContainer.new()
	quest_panel.name = "QuestPanel"
	quest_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	quest_panel.position = Vector2(-20, 62)
	quest_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	quest_panel.custom_minimum_size = Vector2(300, 0)
	quest_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quest_panel.visible = false
	root_control.add_child(quest_panel)
	_quest_box = VBoxContainer.new()
	_quest_box.name = "Quests"
	_quest_box.add_theme_constant_override("separation", 2)
	_quest_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quest_panel.add_child(_quest_box)

	_hint_label = Label.new()
	_hint_label.name = "Hint"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_label.position = Vector2(-310, -154)
	_hint_label.custom_minimum_size = Vector2(620, 0)
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.add_theme_color_override("font_color", Color(0.82, 0.78, 0.62))
	_hint_label.visible = false
	root_control.add_child(_hint_label)

	_prompt_label = Label.new()
	_prompt_label.name = "Prompt"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.position = Vector2(-180, -120)
	_prompt_label.custom_minimum_size = Vector2(360, 0)
	_prompt_label.add_theme_font_size_override("font_size", 20)
	_prompt_label.visible = false
	root_control.add_child(_prompt_label)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status_label.position = Vector2(-200, 90)
	_status_label.custom_minimum_size = Vector2(400, 0)
	_status_label.add_theme_font_size_override("font_size", 20)
	_status_label.visible = false
	root_control.add_child(_status_label)

	# The warning sits above the status line, in gold on a blood outline: it is
	# the only banner that must be read from the corner of an eye while a squad
	# is being walked the wrong way up a dark trail.
	_warning_label = Label.new()
	_warning_label.name = "Warning"
	_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_warning_label.position = Vector2(-460, 22)
	_warning_label.custom_minimum_size = Vector2(920, 0)
	_warning_label.add_theme_font_size_override("font_size", 34)
	_warning_label.add_theme_color_override("font_color", Color(1.0, 0.79, 0.26))
	_warning_label.add_theme_color_override("font_outline_color", Color(0.52, 0.03, 0.02))
	_warning_label.add_theme_constant_override("outline_size", 9)
	_warning_label.visible = false
	root_control.add_child(_warning_label)

	# The skill row. Bottom left keeps the crosshair, the centred prompt and the
	# branded sigil's bottom-right tile clear, and each tile reads its grant,
	# cost and cooldown from the possessed body's runner every frame - a looted
	# weapon changes it without a reload.
	var ability_row := HBoxContainer.new()
	ability_row.name = "Abilities"
	ability_row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ability_row.position = Vector2(24, -TILE_SIZE.y - 20)
	ability_row.add_theme_constant_override("separation", TILE_GAP)
	ability_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(ability_row)
	_ability_tiles.clear()
	for index in AbilityRules.SLOT_COUNT:
		var tile = AbilitySlotScript.new()
		tile.name = "Ability%d" % (index + 1)
		tile.configure(index)
		ability_row.add_child(tile)
		_ability_tiles.append(tile)

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
		else:
			_name_label.text = _merc_name if not _merc_name.is_empty() else "No body"
			if _warband != null and _merc_id >= 0:
				_state_label.text = "%s  (F1..F8 to take another)" % Contracts.state_name(
					_warband.roster.state_of(_merc_id))
			else:
				_state_label.text = "The warband is down"
		_health_bar.value = 0.0
		_health_label.text = ""
		_stamina_bar.value = 0.0
		_stamina_label.text = ""
		# No body, no skills: hide every tile rather than leave the pool's last
		# grants up over a spectator.
		for tile in _ability_tiles:
			tile.update_state({})
		return
	var health: float = float(_body.get("health"))
	var max_health: float = maxf(1.0, float(_body.get("max_health")))
	var downed: bool = bool(_body.get("downed"))
	var state := Contracts.HealthState.DOWNED if downed else (
		Contracts.HealthState.ALIVE if bool(_body.get("alive")) else Contracts.HealthState.DEAD)
	_name_label.text = _merc_name if not _merc_name.is_empty() else str(_body.get("display_name"))
	_state_label.text = Contracts.state_name(state)
	_health_bar.max_value = max_health
	_health_bar.value = health
	_health_label.text = "%d / %d" % [int(round(health)), int(round(max_health))]
	var stamina: float = float(_body.get("stamina"))
	var max_stamina: float = maxf(1.0, float(_body.get("max_stamina")))
	_stamina_bar.max_value = max_stamina
	_stamina_bar.value = stamina
	_stamina_label.text = "%d / %d stamina" % [int(round(stamina)), int(round(max_stamina))]
	_refresh_skills()

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
	var signature := "%d|%d" % [ids.size(), _merc_id]
	for merc_id in ids:
		var record: Dictionary = _warband.roster.find(merc_id)
		signature += "|%d:%d:%d" % [merc_id,
			int(round(float(record.get("health", 0.0)))), int(record.get("state", 0))]
	if signature == _squad_sig:
		return
	_squad_sig = signature
	for child in _squad_box.get_children():
		child.queue_free()
	for index in ids.size():
		var merc_id := ids[index]
		var record: Dictionary = _warband.roster.find(merc_id)
		if record.is_empty():
			continue
		var state := int(record.get("state", Contracts.HealthState.DEAD))
		var max_hp := maxf(1.0, float(record.get("max_health", 1.0)))
		var percent := int(round(float(record.get("health", 0.0)) / max_hp * 100.0))
		var key := "F%d" % (index + 1) if index < 8 else "--"
		var marker := ">" if merc_id == _merc_id else " "
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 12)
		var suffix := ""
		match state:
			Contracts.HealthState.DOWNED:
				suffix = "  DOWNED"
				row.modulate = Color(0.92, 0.62, 0.30)
			Contracts.HealthState.DEAD:
				suffix = "  DEAD"
				row.modulate = Color(0.55, 0.55, 0.55)
			_:
				row.modulate = Color(0.95, 0.95, 0.95)
		row.text = "%s %s  %-10s %3d%%%s" % [marker, key, str(record.get("name", "?")), percent, suffix]
		_squad_box.add_child(row)
	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 10)
	hint.modulate = Color(0.72, 0.72, 0.72)
	hint.text = "[ / ] swap body   O warband   TAB weapon set   G altar/stash"
	_squad_box.add_child(hint)


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


func _refresh_purse() -> void:
	if _purse_label == null:
		return
	if _warband == null:
		_purse_label.text = ""
		_essence_label.text = ""
		return
	_purse_label.text = "%d gold  ·  %d arrows" % [_warband.gold(), _warband.arrows()]
	var total: int = _warband.cruor.total()
	var parts: PackedStringArray = []
	for tier in Catalog.TIER_ORDER:
		var count: int = _warband.cruor.tier_count(tier)
		if count > 0:
			parts.append("%d %s" % [count, Catalog.tier_short(tier)])
	_essence_label.text = ("Cruor: " + ", ".join(parts)) if not parts.is_empty() else (
		"Cruor: none" if total == 0 else "Cruor: %d" % total)

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
