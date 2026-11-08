class_name RogueliteHud
extends CanvasLayer
## The arena's own plate: island, wave and party on the top line, the run's mod
## stack down the right, the draft and the shop as the only modal windows.
##
## It reads the director's `state()` and the local player's engine every frame
## rather than being pushed events, because a HUD that misses one signal is a HUD
## that lies; the state it reads is the same dictionary the host broadcasts, so a
## guest's plate is the host's truth.
##
## The two panels are the only places this node takes the mouse. When either is
## open, `open_panels()` is true and the world keeps the cursor visible.

const Ledger = preload("res://scripts/ui/ledger_theme.gd")
const Mods = preload("res://scripts/roguelite/mod_catalog.gd")
const Weapons = preload("res://scripts/roguelite/weapon_registry.gd")

const LAYER := 7
const INK := Color(0.94, 0.88, 0.72)
const MUTED := Color(0.70, 0.64, 0.52)
const BRASS := Color(0.85, 0.72, 0.42)
const BLOOD := Color(0.92, 0.36, 0.28)
const GOOD := Color(0.66, 0.86, 0.70)

var world = null
var director = null
var _root: Control
var _top: HBoxContainer
var _island_label: Label
var _wave_label: Label
var _party_label: Label
var _purse_label: Label
var _boss_label: Label
var _mod_box: VBoxContainer
var _mod_title: Label
var _downed_label: Label
var _overlay: Control
var _overlay_title: Label
var _overlay_body: VBoxContainer
var _overlay_hint: Label
var _overlay_serial := 0
var _draft_buttons: Array[Button] = []
var _shop_buttons: Array[Button] = []
var _last_mods := ""


func setup(world_node: Node3D, director_node) -> void:
	world = world_node
	director = director_node
	layer = LAYER
	_build()


func _build() -> void:
	_root = Control.new()
	_root.name = "RoguelitePlate"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_top = HBoxContainer.new()
	_top.name = "TopLine"
	# The band's own plate already owns the top centre and the top right; the
	# run's line sits at the top left, where nothing else is written during a
	# fight, and never covers the warband's name or its purse.
	_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_top.alignment = BoxContainer.ALIGNMENT_BEGIN
	_top.add_theme_constant_override("separation", 18)
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.offset_left = 16
	_top.offset_top = 10
	_root.add_child(_top)
	_island_label = _top_label("", 19, INK)
	_wave_label = _top_label("", 19, BRASS)
	_party_label = _top_label("", 16, MUTED)
	_purse_label = _top_label("", 17, GOOD)
	_boss_label = _top_label("", 17, BLOOD)

	_mod_box = VBoxContainer.new()
	_mod_box.name = "Mods"
	_mod_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mod_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_mod_box.offset_left = -300
	_mod_box.offset_right = -14
	# Below the band's own purse panel, never on top of it.
	_mod_box.offset_top = 118
	_mod_box.add_theme_constant_override("separation", 2)
	_root.add_child(_mod_box)
	_mod_title = Label.new()
	_mod_title.text = "MODS"
	_mod_title.add_theme_color_override("font_color", MUTED)
	_mod_title.add_theme_font_size_override("font_size", 16)
	_mod_box.add_child(_mod_title)

	_downed_label = Label.new()
	_downed_label.name = "Downed"
	_downed_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_downed_label.offset_left = -300
	_downed_label.offset_right = 300
	_downed_label.offset_top = -196
	_downed_label.offset_bottom = -160
	_downed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_downed_label.add_theme_color_override("font_color", BLOOD)
	_downed_label.add_theme_font_size_override("font_size", 22)
	_downed_label.visible = false
	_root.add_child(_downed_label)

	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	_root.add_child(_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.03, 0.68)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(shade)
	var panel := PanelContainer.new()
	panel.name = "DraftPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(620, 340)
	panel.offset_left = -310
	panel.offset_right = 310
	panel.offset_top = -170
	panel.offset_bottom = 170
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.065, 0.06, 1.0)
	style.border_color = Color(0.55, 0.45, 0.28)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	_overlay.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	_overlay_title = Label.new()
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_title.add_theme_color_override("font_color", BRASS)
	_overlay_title.add_theme_font_size_override("font_size", 24)
	column.add_child(_overlay_title)
	_overlay_body = VBoxContainer.new()
	_overlay_body.add_theme_constant_override("separation", 8)
	column.add_child(_overlay_body)
	_overlay_hint = Label.new()
	_overlay_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_hint.add_theme_color_override("font_color", MUTED)
	_overlay_hint.add_theme_font_size_override("font_size", 15)
	column.add_child(_overlay_hint)


func _top_label(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", colour)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(label)
	return label


func _process(_delta: float) -> void:
	_refresh()
	var wanted := Input.MOUSE_MODE_VISIBLE if open_panels() else Input.MOUSE_MODE_CAPTURED
	if open_panels() and Input.mouse_mode != wanted:
		Input.mouse_mode = wanted


func _refresh() -> void:
	if director == null or not is_instance_valid(director):
		return
	var running := bool(director.is_running())
	_top.visible = running
	_mod_box.visible = running
	_downed_label.visible = false
	if not running:
		return
	var state: Dictionary = director.state()
	_island_label.text = str(state.get("biome_name", ""))
	_wave_label.text = "ISLAND %d / %d   ·   WAVE %d / %d" % [
		int(state.get("stage", 1)), int(state.get("stages", 6)),
		int(state.get("wave", 0)), int(state.get("waves", 3))]
	_party_label.text = "ALIVE %d  ·  HOSTILES %d" % [
		int(state.get("party", 1)) - _downed_count(), int(state.get("living", 0))]
	_purse_label.text = "%d CRYSTALS   ·   %d KEYS" % [
		int(state.get("crystals", 0)), int(state.get("keys", 0))]
	if bool(state.get("boss_wave", false)) and bool(state.get("wave_active", false)):
		_boss_label.text = "BOSS WAVE"
		_boss_label.visible = true
	else:
		_boss_label.text = ""
	var local = _local_player()
	if local != null and is_instance_valid(local):
		var line := _mods_line(local)
		if line != _last_mods:
			_last_mods = line
			_write_mods(local)
		if local.is_downed() and bool(state.get("wave_active", false)):
			_downed_label.text = "DOWNED  ·  SPECTATING  ·  the living clear the island to raise you"
			_downed_label.visible = true
		else:
			_downed_label.visible = false


func _downed_count() -> int:
	if director == null:
		return 0
	var count := 0
	for peer in director.players:
		var run = director.players[peer]
		if run != null and is_instance_valid(run) and run.is_downed():
			count += 1
	return count


func _local_player():
	if director == null:
		return null
	if world != null and world.get("controller") != null:
		return director.players.get(int(world.controller.local_peer_id))
	return director.players.get(1)


func _mods_line(run) -> String:
	var parts: PackedStringArray = []
	for row in run.engine.mod_list():
		parts.append("%s x%d" % [str(row.get("name", row.get("id", ""))), int(row.get("stacks", 1))])
	return "|".join(parts)


func _write_mods(run) -> void:
	for child in _mod_box.get_children():
		if child != _mod_title:
			_mod_box.remove_child(child)
			child.queue_free()
	var count := 0
	for row in run.engine.mod_list():
		if count >= 12:
			var more := Label.new()
			more.text = "…and more"
			more.add_theme_color_override("font_color", MUTED)
			more.add_theme_font_size_override("font_size", 15)
			_mod_box.add_child(more)
			break
		var label := Label.new()
		label.text = "%s  ×%d" % [str(row.get("name", row.get("id", ""))),
			int(row.get("stacks", 1))]
		label.add_theme_color_override("font_color",
			Mods.RARITY_COLOUR.get(str(row.get("rarity", "common")), INK))
		label.add_theme_font_size_override("font_size", 17)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mod_box.add_child(label)
		count += 1
	if count == 0:
		var empty := Label.new()
		empty.text = "no mods yet"
		empty.add_theme_color_override("font_color", MUTED)
		empty.add_theme_font_size_override("font_size", 15)
		_mod_box.add_child(empty)


# --- the draft and the shop -------------------------------------------------

func open_draft(serial: int, offers: Array) -> void:
	_clear_overlay()
	_overlay_serial = serial
	_overlay_title.text = "CHOOSE A MOD"
	for index in offers.size():
		var mod_id := str(offers[index])
		var row: Dictionary = Mods.get_mod(mod_id)
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%s\n%s" % [str(row.get("name", mod_id)),
			str(row.get("description", ""))]
		button.add_theme_color_override("font_color",
			Mods.RARITY_COLOUR.get(str(row.get("rarity", "common")), INK))
		button.add_theme_font_size_override("font_size", 17)
		button.custom_minimum_size = Vector2(0, 64)
		button.pressed.connect(_on_draft_pressed.bind(index))
		_overlay_body.add_child(button)
		_draft_buttons.append(button)
	_overlay_hint.text = "The pedestal offers one. Choose with the mouse or Escape to step away."
	_overlay.visible = true


func _on_draft_pressed(index: int) -> void:
	if director == null:
		return
	var peer := 1
	if world != null and world.get("controller") != null:
		peer = int(world.controller.local_peer_id)
	director.choose_draft(peer, _overlay_serial, index)
	close_all()


func open_shop(serial: int, wares: Array) -> void:
	_clear_overlay()
	_overlay_serial = serial
	_overlay_title.text = "THE SHOP ISLAND  ·  %d CRYSTALS" % int(
		director.state().get("crystals", 0) if director != null else 0)
	for index in wares.size():
		var ware: Dictionary = wares[index]
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%s  ·  %d crystals" % [str(ware.get("name", "?")),
			int(ware.get("price", 0))]
		button.add_theme_color_override("font_color",
			Mods.RARITY_COLOUR.get(str(ware.get("rarity", "common")), INK))
		button.add_theme_font_size_override("font_size", 18)
		button.custom_minimum_size = Vector2(0, 44)
		if bool(ware.get("sold", false)):
			button.disabled = true
			button.text += "  ·  SOLD"
		button.pressed.connect(_on_shop_pressed.bind(index))
		_overlay_body.add_child(button)
		_shop_buttons.append(button)
	_overlay_hint.text = "The party's crystals buy the wares. Escape steps away."
	_overlay.visible = true


func _on_shop_pressed(index: int) -> void:
	if director == null:
		return
	var peer := 1
	if world != null and world.get("controller") != null:
		peer = int(world.controller.local_peer_id)
	director.buy(_overlay_serial, index, peer)
	close_all()


func _clear_overlay() -> void:
	for child in _overlay_body.get_children():
		_overlay_body.remove_child(child)
		child.queue_free()
	_draft_buttons.clear()
	_shop_buttons.clear()
	_overlay_serial = 0


func open_panels() -> bool:
	return _overlay != null and _overlay.visible


func close_all() -> void:
	if _overlay != null:
		_overlay.visible = false
	_clear_overlay()


func clear_plate() -> void:
	_top.visible = false
	_mod_box.visible = false
	_downed_label.visible = false
	close_all()


## Escape, from the world's own handler: close the modal before it falls through
## to the game menu. True when it consumed the press.
func close_top() -> bool:
	if open_panels():
		close_all()
		return true
	return false
