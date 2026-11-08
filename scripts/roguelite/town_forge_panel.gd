class_name TownForgePanel
extends Control
## The Town Hub's three roguelite fixtures, as one panel: the Unlock Totem, the
## Weapon Rack and the Start Run Portal.
##
## The square owns the props (a node each, in `town_hub.gd`); this is the page
## they open. It is deliberately plain - three doors on one board, driven by the
## `Roguelite` ledger and the run director - because the town is where a player
## decides what to carry, not where the run happens.

const Mods = preload("res://scripts/roguelite/mod_catalog.gd")
const Weapons = preload("res://scripts/roguelite/weapon_registry.gd")
const MetaScript = preload("res://scripts/roguelite/roguelite_meta.gd")

const INK := Color(0.94, 0.88, 0.72)
const MUTED := Color(0.70, 0.64, 0.52)
const BRASS := Color(0.88, 0.74, 0.44)
const GOOD := Color(0.66, 0.88, 0.70)
const BLOOD := Color(0.92, 0.38, 0.30)

var town = null
var mode := "totem"
var _title: Label
var _subtitle: Label
var _body: VBoxContainer
var _message: Label


func configure(town_node) -> void:
	town = town_node
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.03, 0.62)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(720, 520)
	panel.offset_left = -360
	panel.offset_right = 360
	panel.offset_top = -260
	panel.offset_bottom = 260
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.07, 0.062, 0.97)
	style.border_color = BRASS
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", BRASS)
	_title.add_theme_font_size_override("font_size", 28)
	column.add_child(_title)
	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_color_override("font_color", MUTED)
	_subtitle.add_theme_font_size_override("font_size", 16)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_subtitle)
	var rule := HSeparator.new()
	column.add_child(rule)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	scroll.add_child(_body)
	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_color_override("font_color", GOOD)
	_message.add_theme_font_size_override("font_size", 16)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_message)
	var close := Button.new()
	close.text = "CLOSE  (ESC)"
	close.pressed.connect(close_panel)
	column.add_child(close)


func open(next_mode: String = "totem") -> void:
	mode = next_mode
	visible = true
	_message.text = ""
	_refresh()


func close_panel() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _meta():
	return get_node_or_null("/root/Roguelite")


func _refresh() -> void:
	if not visible:
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var meta = _meta()
	if meta == null:
		_title.text = "THE ARENA LEDGER IS MISSING"
		return
	match mode:
		"rack":
			_title.text = "THE WEAPON RACK"
			_subtitle.text = "Every weapon your keys have opened. Bind a ranged and a melee piece; the run dresses your body in exactly these two."
			_rack_rows(meta)
		"portal":
			_title.text = "THE START RUN PORTAL"
			_subtitle.text = "Six islands, three factions, one life per wave. Downed bodies rise when the survivors open the reward chest."
			_portal_rows(meta)
		_:
			_title.text = "THE UNLOCK TOTEM"
			_subtitle.text = "Keys open the armory. Elites, bosses and every cleared island pay them; the totem rolls a locked weapon into the pool."
			_totem_rows(meta)


func _row(text: String, colour: Color, height: float = 28.0) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", colour)
	label.add_theme_font_size_override("font_size", 17)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(0, height)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(label)
	return label


func _button(text: String, colour: Color, callback: Callable, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_color_override("font_color", colour)
	button.add_theme_font_size_override("font_size", 17)
	button.custom_minimum_size = Vector2(0, 44)
	button.disabled = disabled
	button.pressed.connect(callback)
	_body.add_child(button)
	return button


func _totem_rows(meta) -> void:
	_row("KEYS  %d" % int(meta.keys), BRASS, 26)
	_row(meta.describe(), MUTED, 24)
	var locked: Array = meta.locked_ids()
	if locked.is_empty():
		_row("Every weapon in the armory stands on the rack. Nothing is locked.", GOOD, 30)
		return
	var preview: String = meta.unlock_preview()
	var preview_def: Dictionary = Weapons.get_weapon(preview)
	_row("THE TOTEM WOULD OPEN:  %s  ·  %d keys" % [
		str(preview_def.get("name", preview)), int(MetaScript.UNLOCK_COST)], INK, 28)
	_row(str(preview_def.get("description", "")), MUTED, 40)
	_button("ROLL THE TOTEM  ·  spend %d keys" % int(MetaScript.UNLOCK_COST), BRASS,
		_roll_totem, int(meta.keys) < int(MetaScript.UNLOCK_COST))
	_row("LOCKED  ·  %d" % locked.size(), MUTED, 24)
	for index in mini(8, locked.size()):
		var weapon: Dictionary = Weapons.get_weapon(str(locked[index]))
		_row("  %s  ·  %s  ·  %d keys" % [str(weapon.get("name", "?")),
			str(weapon.get("rarity", "")), int(weapon.get("unlock_cost", 3))], MUTED, 22)


func _roll_totem() -> void:
	var meta = _meta()
	if meta == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var result: Dictionary = meta.roll_unlock(rng)
	_message.text = str(result.get("message", ""))
	_message.add_theme_color_override("font_color",
		GOOD if bool(result.get("ok", false)) else BLOOD)
	_refresh()


func _rack_rows(meta) -> void:
	var ranged_id: String = meta.loadout_for(MetaScript.RANGED_SLOT)
	var melee_id: String = meta.loadout_for(MetaScript.MELEE_SLOT)
	var ranged_def: Dictionary = Weapons.get_weapon(ranged_id)
	var melee_def: Dictionary = Weapons.get_weapon(melee_id)
	_row("RANGED  ·  %s" % str(ranged_def.get("name", ranged_id)), BRASS, 26)
	_row(str(ranged_def.get("description", "")), MUTED, 38)
	_row("MELEE  ·  %s" % str(melee_def.get("name", melee_id)), BRASS, 26)
	_row(str(melee_def.get("description", "")), MUTED, 38)
	_row("THE RANGED RACK", MUTED, 24)
	for id in meta.pool_for(MetaScript.RANGED_SLOT):
		if id == ranged_id:
			continue
		var weapon: Dictionary = Weapons.get_weapon(id)
		_button("  %s  ·  %s" % [str(weapon.get("name", id)),
			str(weapon.get("archetype", ""))], INK, _equip.bind(MetaScript.RANGED_SLOT, id))
	_row("THE MELEE RACK", MUTED, 24)
	for id in meta.pool_for(MetaScript.MELEE_SLOT):
		if id == melee_id:
			continue
		var weapon: Dictionary = Weapons.get_weapon(id)
		_button("  %s  ·  %s" % [str(weapon.get("name", id)),
			str(weapon.get("archetype", ""))], INK, _equip.bind(MetaScript.MELEE_SLOT, id))
	# What the totem still holds back: named, priced and dead to the press, so a
	# rack is a board to aim at rather than a list of what happens to be open.
	var locked_ranged: Array[String] = []
	var locked_melee: Array[String] = []
	for id in Weapons.ids_for_slot(MetaScript.RANGED_SLOT):
		if not meta.is_unlocked(id):
			locked_ranged.append(id)
	for id in Weapons.ids_for_slot(MetaScript.MELEE_SLOT):
		if not meta.is_unlocked(id):
			locked_melee.append(id)
	if not locked_ranged.is_empty() or not locked_melee.is_empty():
		_row("LOCKED  ·  open at the Unlock Totem", MUTED, 26)
		for id in locked_ranged + locked_melee:
			var weapon: Dictionary = Weapons.get_weapon(id)
			_row("  %s  ·  %s  ·  %d keys" % [str(weapon.get("name", id)),
				str(weapon.get("archetype", "")), int(weapon.get("unlock_cost", 3))],
				Color(0.46, 0.42, 0.36), 22)


func _equip(slot: String, weapon_id: String) -> void:
	var meta = _meta()
	if meta == null:
		return
	var result: Dictionary = meta.set_loadout_slot(slot, weapon_id)
	_message.text = str(result.get("message", ""))
	_message.add_theme_color_override("font_color",
		GOOD if bool(result.get("ok", false)) else BLOOD)
	if bool(result.get("ok", false)) and town != null:
		var world = town.get("host")
		if world != null and world.has_method("refresh_town_dress"):
			world.refresh_town_dress()
	_refresh()


func _portal_rows(meta) -> void:
	var ranged_def: Dictionary = Weapons.get_weapon(meta.loadout_for(MetaScript.RANGED_SLOT))
	var melee_def: Dictionary = Weapons.get_weapon(meta.loadout_for(MetaScript.MELEE_SLOT))
	_row("CARRYING  ·  %s  |  %s" % [str(ranged_def.get("name", "")),
		str(melee_def.get("name", ""))], INK, 26)
	_row("Co-op scales every wave by +50% per connected player. A downed body " +
"spectates until the survivors open the island's reward chest.", MUTED, 44)
	_row("Keys banked this ledger: %d  ·  runs fought: %d  ·  deepest island: %d" % [
		int(meta.lifetime_keys), int(meta.runs), int(meta.best_stage)], MUTED, 24)
	var world = town.get("host") if town != null else null
	var director = world.get("roguelite") if world != null else null
	var busy := director != null and bool(director.is_running())
	_button("STEP INTO THE PORTAL  ·  BEGIN THE RUN", BRASS, _start_run, busy)
	if busy:
		_row("A run is already live.", BLOOD, 24)


func _start_run() -> void:
	var world = town.get("host") if town != null else null
	if world == null:
		return
	var director = world.get("roguelite")
	if director == null:
		return
	var result: Dictionary = director.start_run()
	_message.text = str(result.get("message", ""))
	_message.add_theme_color_override("font_color",
		GOOD if bool(result.get("ok", false)) else BLOOD)
	if bool(result.get("ok", false)):
		close_panel()
