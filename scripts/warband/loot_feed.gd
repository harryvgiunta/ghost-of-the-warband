extends CanvasLayer
## The looted list: every piece the warband takes shows up here as a line on the
## right of the screen - "+ Club", "+ Linen Bandage ×2 · squad" - and fades.
##
## It is fed from the loot vacuum's one booking path (`WarbandLoot.booked`), so a
## piece the soul's hands took, one a squadmate stripped off a body and one a sweep
## gathered all land here, and nothing can be listed that was not really booked.
## The same piece taken by the same hands within a beat is one line with a count.
## While a party is below, the header over the list carries the delve's own line
## (the floor, what the inventory holds, the master's blood).

const State = preload("res://scripts/player_state.gd")
const StashScript = preload("res://scripts/warband/town_stash_model.gd")

const MAX_LINES := 8
const LINE_SECONDS := 8.0
const FADE_SECONDS := 1.2
## Within this, a second copy taken by the same hands grows the line it joins.
const MERGE_SECONDS := 2.0
## A piece at least this dear is called out in gold.
const DEAR_VALUE := 100
const WIDTH := 320.0

var _box: VBoxContainer
var _header: Label
var _lines: Array[Dictionary] = []   # {label, item_id, who, count, age}


func _ready() -> void:
	layer = 6
	_build()


## One booked piece. `who` is empty for the soul's own hands, a name otherwise.
func note(item_id: String, who: String = "") -> void:
	if item_id.is_empty() or _box == null:
		return
	for line in _lines:
		if str(line["item_id"]) == item_id and str(line["who"]) == who \
				and float(line["age"]) <= MERGE_SECONDS:
			line["count"] = int(line["count"]) + 1
			line["age"] = 0.0
			_paint(line)
			_box.move_child(line["label"], _box.get_child_count() - 1)
			return
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(label)
	var line := {"label": label, "item_id": item_id, "who": who, "count": 1, "age": 0.0}
	_lines.append(line)
	_paint(line)
	while _lines.size() > MAX_LINES:
		var oldest: Dictionary = _lines.pop_front()
		(oldest["label"] as Label).queue_free()


## The delve's line over the list; empty puts it away.
func set_header(text: String) -> void:
	if _header == null:
		return
	_header.text = text
	_header.visible = not text.is_empty()


func header_text() -> String:
	return str(_header.text) if _header != null and _header.visible else ""


## The lines as written, oldest first, for tests and the log.
func lines() -> Array[String]:
	var out: Array[String] = []
	for line in _lines:
		out.append(str((line["label"] as Label).text))
	return out


func _process(delta: float) -> void:
	for index in range(_lines.size() - 1, -1, -1):
		var line: Dictionary = _lines[index]
		line["age"] = float(line["age"]) + delta
		var label: Label = line["label"]
		var left := LINE_SECONDS - float(line["age"])
		if left <= 0.0:
			label.queue_free()
			_lines.remove_at(index)
			continue
		label.modulate.a = clampf(left / FADE_SECONDS, 0.0, 1.0)


func _paint(line: Dictionary) -> void:
	var item_id := str(line["item_id"])
	var count := int(line["count"])
	var text := "+ %s" % str(State.ITEMS.get(item_id, {}).get("name", item_id))
	if count > 1:
		text += "  ×%d" % count
	if not str(line["who"]).is_empty():
		text += "  ·  %s" % str(line["who"])
	var label: Label = line["label"]
	label.text = text
	var dear := StashScript.value_of(item_id) >= DEAR_VALUE
	label.add_theme_color_override("font_color",
		Color(1.0, 0.80, 0.36) if dear else Color(0.92, 0.88, 0.78))
	label.modulate.a = 1.0


func _build() -> void:
	var root_control := Control.new()
	root_control.name = "LootFeed"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)
	var column := VBoxContainer.new()
	column.name = "Lines"
	column.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	column.offset_left = -WIDTH - 22.0
	column.offset_right = -22.0
	column.offset_top = 10.0
	column.offset_bottom = 10.0
	column.grow_vertical = Control.GROW_DIRECTION_END
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(column)
	_header = Label.new()
	_header.name = "DelveLine"
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_header.add_theme_font_size_override("font_size", 14)
	_header.add_theme_color_override("font_color", Color(0.80, 0.86, 0.96))
	_header.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.9))
	_header.add_theme_constant_override("outline_size", 6)
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.visible = false
	column.add_child(_header)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 1)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_box)
