extends SceneTree
## GHOST OF THE WARBAND: the CONTROLS sheet, and the three windows that open it.
##
## `keybind_page.gd` is a reference plate, not a rebinding UI - the warband's keys
## live in the scenes - so what can regress is the drawing: a key that does
## something must be lit, two tiles must never sit on one another, every action
## must be reached by an arrowhead that ends on its own label, and the board must
## fit the page it is given. The second half is the wiring: the frontier's quick
## menu, the warband's own menu and the settings window each open the sheet one
## page deep and hand Escape back the same way they always have.
##
## Built headless: layout is pure arithmetic on the page's own size, so none of
## this needs a renderer.

const PageScript = preload("res://scripts/ui/keybind_page.gd")
const PauseScript = preload("res://scripts/pause_menu.gd")
const WarbandMenuScript = preload("res://scripts/warband/warband_menu.gd")
const SettingsScript = preload("res://scripts/ui/settings_menu.gd")

## The keys the campaign actually reads. Every one of them must be washed blood:
## a controls sheet that leaves a live key as dead bone is the one lie it can tell.
const BOUND := ["W", "A", "S", "D", "SHIFT", "SPACE", "C", "TAB", "F1", "F5",
	"LMB", "RMB", "WHEEL", "T", "Q", "E", "R", "G", "K", "P", "O", "M", "ESC"]

var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("KEYS_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	await _check_board()
	await _check_menus()
	_finish()


# --- the sheet -------------------------------------------------------------

func _check_board() -> void:
	var page = PageScript.new()
	page.name = "Keys"
	page.size = Vector2(1100, 640)
	root.add_child(page)
	await process_frame
	await process_frame

	var labels: Array[String] = page.action_labels()
	check(labels.size() == 19, "the sheet names 19 actions (%d)" % labels.size())
	for wanted in ["MOVE", "SPRINT", "JUMP", "CROUCH", "WEAPON SET", "SWING",
			"GUARD", "STAB", "OVERHEAD", "THROW", "SIDESTEP", "SIGIL",
			"USE · LATCH", "TAKE", "GEAR", "WARBAND", "MAP", "MENU"]:
		check(labels.has(wanted), "the sheet names %s (%s)" % [wanted, str(labels)])
	check(labels.has("BODIES · F1-F5 · [ ]"),
		"and names the bodies: %s" % str(labels))

	# Every bound key is lit, and nothing that is dead is.
	var lit: Array[String] = page.lit_keys()
	for token in BOUND:
		check(lit.has(token), "%s is one of the lit keys (%s)" % [token, str(lit)])
	check(not lit.has("Z") and not lit.has("Y") and not lit.has("9"),
		"a key with no action is left dead bone (%s)" % str(lit))

	# One arrowhead per action key, each ending on its own label.
	var leaders: Array[Dictionary] = page.leaders()
	check(leaders.size() == page.arrow_count(),
		"every thread is carried in the sheet's own list")
	check(leaders.size() == 20, "twenty arrowheads serve nineteen actions (%d)" % leaders.size())
	for run in leaders:
		var label := String(run["label"])
		var rect: Rect2 = page.action_rect(label)
		check(rect.size.x > 0.0, "%s has a label rect" % label)
		if rect.size.x <= 0.0:
			continue
		var tip: Vector2 = run["tip"]
		# The head stops on the label's inner edge, whichever side it comes from.
		var near_x := tip.x >= rect.position.x - 2.0 and tip.x <= rect.end.x + 2.0
		var near_y := tip.y >= rect.position.y - 2.0 and tip.y <= rect.end.y + 2.0
		check(near_x and near_y, "%s's arrow ends on its label (%s vs %s)"
			% [label, str(tip), str(rect)])

	# No tile sits on another, and none leaves the board it is drawn on.
	var tokens: Array = []
	for token in ["ESC", "F1", "F12", "TAB", "Q", "W", "E", "A", "S", "D", "G",
			"C", "SPACE", "SHIFT", "SHIFT_R", "LMB", "RMB", "WHEEL", "BACKSPACE"]:
		var tile: Control = page.key_tile(token)
		check(tile != null, "%s has a tile" % token)
		if tile != null:
			tokens.append([token, tile])
	for i in tokens.size():
		for j in range(i + 1, tokens.size()):
			var a: Control = tokens[i][1]
			var b: Control = tokens[j][1]
			var overlap := Rect2(a.position, a.size).intersects(Rect2(b.position, b.size))
			check(not overlap, "%s and %s do not overlap (%s / %s)"
				% [tokens[i][0], tokens[j][0], str(a.position), str(b.position)])
	var board: Vector2 = page.board_size()
	check(board.x > 0.0 and board.y > 0.0, "the board has a size (%s)" % str(board))
	check(board.x <= 1100.0 - 132.0 - 96.0, "the board fits between the gutters (%s)" % str(board))

	# Labels do not collide with one another either.
	for i in labels.size():
		var a: Rect2 = page.action_rect(labels[i])
		for j in range(i + 1, labels.size()):
			var b: Rect2 = page.action_rect(labels[j])
			check(not a.intersects(b), "%s and %s have room (%s / %s)"
				% [labels[i], labels[j], str(a), str(b)])

	# A small page shrinks the board instead of piling labels on keys.
	page.size = Vector2(700, 480)
	await process_frame
	await process_frame
	var small: Vector2 = page.board_size()
	check(small.x < board.x, "a smaller page scales the board down (%s < %s)"
		% [str(small), str(board)])
	for run in page.leaders():
		var rect: Rect2 = page.action_rect(String(run["label"]))
		check(rect.end.x <= 700.0 + 1.0 and rect.end.y <= 480.0 + 1.0,
			"%s's label stays on a narrow page (%s)" % [String(run["label"]), str(rect)])

	page.queue_free()
	await process_frame


# --- the three windows -----------------------------------------------------

func _check_menus() -> void:
	# The frontier's quick menu: the sheet is one page in, and Escape walks back.
	var pause = PauseScript.new()
	pause.name = "PauseMenu"
	root.add_child(pause)
	await process_frame
	pause.open()
	check(pause.keys_button != null, "the quick menu has a KEYS row")
	check(pause.is_open() and not pause.showing_keys(), "it opens on its rows")
	pause.show_keys(true)
	check(pause.showing_keys(), "KEYS takes the frame")
	check(pause.keys_page != null and pause.keys_page.is_inside_tree(),
		"and the sheet is in the tree")
	var grown: float = pause.get_node("Menu/Frame").size.x if pause.has_node("Menu/Frame") else 0.0
	check(grown > PauseScript.PANEL_SIZE.x + 1.0,
		"the window grows for a keyboard (%d)" % int(grown))
	check(pause.back(), "Escape on the sheet hands the frame back")
	check(not pause.showing_keys() and pause.is_open(), "and the menu is still open")
	check(not pause.back(), "Escape on the rows asks the scene to close it")
	pause._show_sound_page(true)
	check(pause.showing_sound() and pause.back() and not pause.showing_sound(),
		"the sound page still unwinds the same way")
	pause.close()
	pause.queue_free()
	await process_frame

	# The campaign's own menu: the same sheet, the same one-page rule.
	var band = WarbandMenuScript.new()
	band.name = "WarbandMenu"
	root.add_child(band)
	await process_frame
	band.open()
	check(band.keys_button != null, "the campaign menu has a KEYS row")
	band.show_page("keys")
	check(band.page() == "keys", "and the sheet is a page of it (%s)" % band.page())
	check(band.keys_page != null and band.keys_page.is_inside_tree(),
		"with the board in the tree")
	check(band.action_buttons().size() == 6,
		"the six rows the campaign menu always had are untouched (%d)"
			% band.action_buttons().size())
	check(band.back() and band.page() == "menu", "Escape walks back to the rows")
	band.close()
	band.queue_free()
	await process_frame

	# The settings window, the title's door to it.
	var settings = SettingsScript.new()
	settings.name = "Settings"
	root.add_child(settings)
	await process_frame
	settings.open()
	check(settings.keys_button != null, "settings has a KEYS row")
	settings.show_page("keys")
	check(settings.page() == "keys", "the sheet is a page of settings (%s)" % settings.page())
	var wide: float = 0.0
	if settings.has_node("SettingsRoot/SettingsFrame"):
		wide = settings.get_node("SettingsRoot/SettingsFrame").size.x
	check(wide > SettingsScript.PANEL_SIZE.x + 1.0,
		"the settings window grows for the sheet (%d)" % int(wide))
	settings.show_page("root")
	check(settings.page() == "root", "and comes back to the index")
	settings.close()
	settings.queue_free()
	await process_frame


func _finish() -> void:
	print("KEYBIND_SCREEN_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
