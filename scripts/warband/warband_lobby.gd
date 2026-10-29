class_name WarbandLobby
extends Control
## The warband's door on the title menu, and the strip that reports the battle
## once the menu is gone.
##
## The lobby owns no socket and no scene. A press stores an intent in `GameFlow`
## - the one node that survives a hand-off - and the flow seats a real
## `WarbandSession` on the scene that next fields the warband's bodies. That is
## the whole point of the split: the title screen is freed the moment the arena
## loads, so a session created here and parented here would drop every peer at
## the exact moment the battle starts.
##
## `WarbandLobby.Banner` is the persistent half. It names the role, the port and
## the souls on the field, and it is where a refused body says - in the router's
## own words - why it said no. A guest's refusal never reaches the arena HUD: the
## controller only publishes refusals it decided itself, and a guest's request is
## refused by the host over the wire, so without this strip the second player
## would be pressing a key that silently does nothing.

## The panel the title places beside its four doors. Tall enough for the mode
## row, which is the lobby's only new question: the battle or the campaign.
const PANEL_SIZE := Vector2(744, 340)
## The warband's own port. The arena's `--warband-join` fallback has always been
## 7779, so the lobby offers the same one instead of the open world's 7777.
const DEFAULT_PORT := 7779
## The two things this door can open. Campaign is the default: the warband is
## the game now, so a player who presses HOST WARBAND without touching the mode
## row must get the co-op run through the world the four cages, the trail and
## the town share. The arena bout is still the first option and stays fully
## selectable; it is the stand-alone bout that leaves the campaign save alone.
const MODE_ARENA := "arena"
const MODE_CAMPAIGN := "campaign"
const ARENA_SCENE := "res://admin_arena.tscn"
const CAMPAIGN_SCENE := "res://scenes/warband_world.tscn"

const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")

const CREAM := Color("eee9db")
const MUTED := Color("a5b6b7")
const GOLD := Color("e9bf76")
const TEAL := Color("72cbb6")
const WARN := Color("e2a06a")

var name_input: LineEdit
var address_input: LineEdit
var port_input: SpinBox
## The choice between the stand-alone bout and the co-op campaign. Index 0 is
## the arena and index 1 the campaign; the row is built with the campaign
## selected, so the order of the options and the default are separate things.
var mode_select: OptionButton
## One line per mode, under the selector, saying what each one opens.
var mode_description: Label
var host_button: Button
var join_button: Button
var status_label: Label

func _ready() -> void:
	_build()
	# The cache is the identity every other door on this menu uses, and it is
	# written after this screen can be built (a friend's address typed in a
	# previous session, a port changed by the open-world host), so it is read
	# here rather than baked in at lines of code.
	sync_from_cache()

## The remembered name, address and port. Shared with the arena/delve/world
## doors: a player has one name and one endpoint, and remembering them twice is
## how the two forms start disagreeing.
func sync_from_cache() -> void:
	var cached_name := "Soul"
	var cached_address := "127.0.0.1"
	var cached_port := DEFAULT_PORT
	var cache := get_node_or_null("/root/NetCache")
	if cache != null:
		cached_name = str(cache.player_name)
		cached_address = str(cache.address)
		cached_port = int(cache.port)
	if name_input != null:
		name_input.text = cached_name
	if address_input != null:
		address_input.text = cached_address
	if port_input != null:
		port_input.value = clampi(cached_port, 1024, 65535)

## What the fields say, cleaned the way the join form cleans them.
func player_name() -> String:
	var text := name_input.text if name_input != null else ""
	var clean := text.strip_edges().replace("\n", " ").replace("\r", " ").replace("\t", " ")
	clean = clean.left(16)
	return clean if not clean.is_empty() else "Soul"

func address() -> String:
	return address_input.text.strip_edges() if address_input != null else "127.0.0.1"

func port() -> int:
	return int(port_input.value) if port_input != null else DEFAULT_PORT

## `"arena"` or `"campaign"`. The selector's metadata is the source of truth, so
## the payload cannot disagree with the option the player is looking at. A
## selector that was never built - or one whose current row carries no mode -
## falls back to the campaign, which is the panel's default.
func selected_mode() -> String:
	if mode_select == null:
		return MODE_CAMPAIGN
	var index := mode_select.selected
	if index < 0 or index >= mode_select.item_count:
		return MODE_CAMPAIGN
	var kind := str(mode_select.get_item_metadata(index))
	return kind if kind == MODE_CAMPAIGN or kind == MODE_ARENA else MODE_CAMPAIGN

## The intent this lobby would hand `GameFlow` right now, built without sending
## it. `action` is `"host"` or `"join"`; the scene follows the mode, not the
## action, because both peers must field the same world. The title regression
## presses HOST/JOIN for real; this accessor exists so a headless test can read
## the request without opening a socket or moving the tree.
func request_payload(action: String = "host") -> Dictionary:
	var kind := selected_mode()
	var hosting := action != "join"
	return {
		"mode": "host" if hosting else "join",
		"mode_kind": kind,
		"scene": CAMPAIGN_SCENE if kind == MODE_CAMPAIGN else ARENA_SCENE,
		"address": "127.0.0.1" if hosting else address(),
		"port": port(),
		"name": player_name(),
	}

# --- the two doors ---------------------------------------------------------

## Open a battle on this machine. The socket is created by `GameFlow` once the
## arena has fielded the bodies, so the first snapshot never describes a body the
## wire has not seen.
func host() -> void:
	var campaign := selected_mode() == MODE_CAMPAIGN
	var method := "host_campaign" if campaign else "host_warband"
	var flow := get_node_or_null("/root/GameFlow")
	if flow == null or not flow.has_method(method):
		set_status("The warband flow is unavailable.", WARN)
		return
	var payload := request_payload("host")
	var chosen_port := int(payload.get("port", DEFAULT_PORT))
	if chosen_port < 1024 or chosen_port > 65535:
		set_status("Choose a UDP port between 1024 and 65535.", WARN)
		return
	var chosen_name := str(payload.get("name", player_name()))
	# The remembered address is the field, not the payload: the intent binds
	# 127.0.0.1, but the form has always remembered what the player typed.
	_remember(chosen_name, address(), chosen_port)
	if campaign:
		set_status("Opening the campaign on UDP %d. Friends join this port." % chosen_port)
	else:
		set_status("Opening a warband battle on UDP %d. Friends join this port." % chosen_port)
	_note("warband_host", {"port": chosen_port, "name": chosen_name,
		"mode_kind": str(payload.get("mode_kind", MODE_ARENA))})
	print("WARBAND_LOBBY_HOST port=%d name=%s" % [chosen_port, chosen_name])
	if campaign:
		flow.host_campaign(chosen_port, chosen_name)
	else:
		flow.host_warband(chosen_port, chosen_name)

## Join a friend's battle. The flow enters the same scene and the first body no
## soul is inside; the host is the one that decides which body that turns out to
## be, so a body taken in the meantime comes back as a refusal, not a crash.
func join() -> void:
	var campaign := selected_mode() == MODE_CAMPAIGN
	var method := "join_campaign" if campaign else "join_warband"
	var flow := get_node_or_null("/root/GameFlow")
	if flow == null or not flow.has_method(method):
		set_status("The warband flow is unavailable.", WARN)
		return
	var payload := request_payload("join")
	var chosen_address := str(payload.get("address", address()))
	if chosen_address.is_empty():
		set_status("Enter the host's address.", WARN)
		return
	var chosen_port := int(payload.get("port", DEFAULT_PORT))
	if chosen_port < 1024 or chosen_port > 65535:
		set_status("Choose a UDP port between 1024 and 65535.", WARN)
		return
	var chosen_name := str(payload.get("name", player_name()))
	_remember(chosen_name, chosen_address, chosen_port)
	if campaign:
		set_status("Joining the campaign at %s:%d..." % [chosen_address, chosen_port])
	else:
		set_status("Joining %s:%d..." % [chosen_address, chosen_port])
	_note("warband_join", {"address": chosen_address, "port": chosen_port,
		"name": chosen_name, "mode_kind": str(payload.get("mode_kind", MODE_ARENA))})
	print("WARBAND_LOBBY_JOIN address=%s port=%d name=%s" % [chosen_address, chosen_port, chosen_name])
	if campaign:
		flow.join_campaign(chosen_address, chosen_port, chosen_name)
	else:
		flow.join_warband(chosen_address, chosen_port, chosen_name)

func set_status(message: String, color: Color = TEAL) -> void:
	if status_label == null:
		return
	status_label.text = message
	status_label.add_theme_color_override("font_color", color)

## Remember the warband endpoint the same way the other doors remember theirs.
## The mode is left alone: a warband battle is not an arena seat, a delve or the
## open world, and writing one here would move a door this screen does not own.
func _remember(chosen_name: String, chosen_address: String, chosen_port: int) -> void:
	var cache := get_node_or_null("/root/NetCache")
	if cache != null:
		cache.remember(chosen_name, chosen_address, chosen_port, "")

func _note(message: String, data: Dictionary = {}) -> void:
	var log := get_node_or_null("/root/Log")
	if log != null:
		log.event("menu", message, data)

# --- the panel -------------------------------------------------------------

func _build() -> void:
	theme = LedgerThemeScript.get_theme()
	size = PANEL_SIZE
	var panel := Panel.new()
	panel.size = PANEL_SIZE
	panel.add_theme_stylebox_override("panel",
		LedgerThemeScript.iron_panel())
	add_child(panel)
	var heading := _label(panel, "WARBAND LOBBY", Vector2(26, 20), 28, CREAM)
	heading.add_theme_font_override("font", LedgerThemeScript.FONT_DISPLAY)
	heading.size = Vector2(690, 38)
	var subtitle := _label(panel, "Choose a field: an arena bout or campaign co-op.", Vector2(28, 58), 12, MUTED)
	subtitle.size = Vector2(690, 18)

	# The mode is the lobby's one question. Campaign co-op is the default, so the
	# row is built with index 1 selected: HOST WARBAND with the dropdown never
	# touched opens the warband world. The arena stays first in the list because
	# it is the stand-alone bout and the older destination of the two, and it
	# remains one click away.
	mode_select = OptionButton.new()
	mode_select.position = Vector2(28, 82)
	mode_select.size = Vector2(300, 36)
	mode_select.add_theme_font_size_override("font_size", 14)
	mode_select.add_item("ARENA BATTLE", 0)
	mode_select.set_item_metadata(0, MODE_ARENA)
	mode_select.add_item("CAMPAIGN (CO-OP)", 1)
	mode_select.set_item_metadata(1, MODE_CAMPAIGN)
	mode_select.selected = 1
	panel.add_child(mode_select)
	# One line per mode, both readable without opening the dropdown: the choice
	# is what the bout costs the campaign save, so leaving one unexplained is how
	# a player hosts the wrong thing.
	mode_description = _label(panel,
		"ARENA BATTLE: a stand-alone bout; the campaign save is untouched.\n"
		+ "CAMPAIGN (CO-OP): co-op through the warband world and its checkpoints.",
		Vector2(340, 78), 9, MUTED)
	mode_description.size = Vector2(380, 44)
	mode_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_label(panel, "YOUR NAME", Vector2(28, 134), 10, GOLD)
	name_input = LineEdit.new()
	name_input.position = Vector2(28, 152)
	name_input.size = Vector2(220, 38)
	name_input.max_length = 16
	panel.add_child(name_input)

	_label(panel, "UDP PORT", Vector2(272, 134), 10, GOLD)
	port_input = SpinBox.new()
	port_input.position = Vector2(272, 152)
	port_input.size = Vector2(120, 38)
	port_input.min_value = 1024
	port_input.max_value = 65535
	port_input.value = DEFAULT_PORT
	panel.add_child(port_input)

	_label(panel, "HOST ADDRESS", Vector2(416, 134), 10, GOLD)
	address_input = LineEdit.new()
	address_input.position = Vector2(416, 152)
	address_input.size = Vector2(300, 38)
	panel.add_child(address_input)

	host_button = _button(panel, "HOST WARBAND", Vector2(28, 200), Vector2(340, 46))
	host_button.theme_type_variation = "PrimaryButton"
	host_button.add_theme_font_size_override("font_size", 17)
	host_button.pressed.connect(host)
	join_button = _button(panel, "JOIN WARBAND", Vector2(384, 200), Vector2(332, 46))
	join_button.add_theme_font_size_override("font_size", 17)
	join_button.pressed.connect(join)

	status_label = _label(panel, "", Vector2(28, 254), 12, TEAL)
	# The title's CLOSE button sits over this panel's lower right, so both lines
	# stay left of it instead of running underneath the button.
	status_label.size = Vector2(500, 36)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var footnote := _label(panel,
		"Arena bout or campaign co-op; friends need the same warband save and the host's UDP port.",
		Vector2(28, 294), 10, MUTED)
	footnote.size = Vector2(500, 30)
	footnote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _style(color: Color, border: Color, radius: int) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.border_color = border
	result.set_border_width_all(1)
	result.set_corner_radius_all(radius)
	return result

func _label(parent: Node, text: String, position_at: Vector2, font_size: int,
		color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.position = position_at
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	parent.add_child(result)
	return result

## The title menu's own button style, so the lobby is one panel of the same
## screen rather than a second visual language bolted beside it.
func _button(parent: Node, text: String, position_at: Vector2, size_at: Vector2) -> Button:
	var result := Button.new()
	result.text = text
	result.position = position_at
	result.size = size_at
	result.focus_mode = Control.FOCUS_NONE
	parent.add_child(result)
	return result


## The strip `GameFlow` keeps on screen for the whole battle: the role, the
## endpoint, how many souls are on the field, and the last refusal verbatim.
##
## It lives in this file because it is the lobby's other half - the same voice,
## on the screen the player is actually looking at after the menu is gone.
class Banner:
	extends CanvasLayer

	const LAYER := 40
	const HOLD_SECONDS := 8.0
	const TEAL := Color("72cbb6")
	const WARN := Color("e2a06a")

	## The role line as last painted ("WARBAND · HOSTING UDP 7790 · 2 souls").
	var state_text := ""
	## The last refusal in the router's own words. Kept after the line fades so a
	## player who looked away can still read what happened.
	var reason := ""

	var _panel: Panel
	var _state_label: Label
	var _reason_label: Label
	var _hold := 0.0

	func _ready() -> void:
		layer = LAYER
		_build()
		set_process(true)

	func show_state(text: String, warn: bool = false) -> void:
		state_text = text
		if _state_label != null:
			_state_label.text = text
			_state_label.add_theme_color_override("font_color", WARN if warn else TEAL)
		_refresh_visibility()

	func note_refusal(text: String) -> void:
		reason = text
		_hold = HOLD_SECONDS
		if _reason_label != null:
			_reason_label.text = ("Refused: " + text) if not text.is_empty() else ""
		_refresh_visibility()

	## The two lines a player can read right now.
	func reason_line() -> String:
		if _reason_label == null or not _reason_label.visible:
			return ""
		return _reason_label.text

	func _process(delta: float) -> void:
		if _hold <= 0.0:
			return
		_hold -= delta
		if _hold <= 0.0 and _reason_label != null:
			_reason_label.text = ""
			_refresh_visibility()

	func _refresh_visibility() -> void:
		if _panel == null:
			return
		var has_reason := _reason_label != null and not _reason_label.text.is_empty()
		_panel.visible = not state_text.is_empty() or has_reason
		if _reason_label != null:
			_reason_label.visible = has_reason

	func _build() -> void:
		_panel = Panel.new()
		_panel.set_anchors_preset(Control.PRESET_CENTER_TOP, true)
		_panel.position = Vector2(-300, 10)
		_panel.size = Vector2(600, 62)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.03, 0.07, 0.085, 0.86)
		style.border_color = Color("3f5b60")
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		_panel.add_theme_stylebox_override("panel", style)
		_panel.visible = false
		add_child(_panel)
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI"])
		_state_label = Label.new()
		_state_label.position = Vector2(18, 8)
		_state_label.size = Vector2(564, 22)
		_state_label.add_theme_font_size_override("font_size", 16)
		_state_label.add_theme_color_override("font_color", TEAL)
		_state_label.add_theme_font_override("font", font)
		_panel.add_child(_state_label)
		_reason_label = Label.new()
		_reason_label.position = Vector2(18, 32)
		_reason_label.size = Vector2(564, 24)
		_reason_label.add_theme_font_size_override("font_size", 13)
		_reason_label.add_theme_color_override("font_color", WARN)
		_reason_label.add_theme_font_override("font", font)
		_reason_label.visible = false
		_panel.add_child(_reason_label)
