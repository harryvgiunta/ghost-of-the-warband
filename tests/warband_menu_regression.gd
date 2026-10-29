extends SceneTree
## Warband menu regression: the quick menu has all six rows, writes and reads
## the warband through `Warband.save_state()` at whatever path the autoload
## carries, gates LOAD on a real file, opens the shared sound page and comes
## back, emits `resumed` on close, and never pauses the tree.

const MenuScript = preload("res://scripts/warband/warband_menu.gd")

const TEST_SAVE := "user://warband_menu_state.json"
const ROW_KEYS := ["resume", "save", "load", "settings", "exit", "quit"]

var checks := 0
var failures := 0
var _resumed := 0
var _loads := 0
var _exits := 0
var _saved: Array[String] = []


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WARBAND_MENU_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func _remove_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))


func _on_resumed() -> void:
	_resumed += 1


func _on_saved(path: String) -> void:
	_saved.append(path)


func _on_load_requested() -> void:
	_loads += 1


func _on_exit_requested() -> void:
	_exits += 1


func run() -> void:
	_remove_save()
	var warband := root.get_node_or_null("Warband")
	check(warband != null, "the Warband autoload exists")
	if warband == null:
		print("WARBAND_MENU_REGRESSION checks=", checks, " failures=", failures)
		quit(1)
		return
	var original_path := str(warband.save_path)
	warband.save_path = TEST_SAVE
	warband.reset_state()

	var menu = MenuScript.new()
	root.add_child(menu)
	menu.configure("LEAVE THE CAMPAIGN")
	menu.resumed.connect(_on_resumed)
	menu.load_requested.connect(_on_load_requested)
	menu.exit_requested.connect(_on_exit_requested)
	menu.saved.connect(_on_saved)

	# --- the closed menu ---------------------------------------------------
	check(not menu.is_open(), "a fresh menu is closed")
	check(not menu.visible, "a closed menu draws nothing")
	check(menu.page() == "menu", "a fresh menu is on the index page")
	var buttons: Dictionary = menu.action_buttons()
	for key in ROW_KEYS:
		check(buttons.has(key) and buttons[key] is Button,
			"action_buttons() carries a Button for '%s'" % key)
	check(str(buttons["exit"].text) == "LEAVE THE CAMPAIGN",
		"the exit row wears the label the world configured")
	check(buttons["load"].disabled, "LOAD is disabled while no save file exists")

	# --- open --------------------------------------------------------------
	menu.open({"notice": "The camp is not ready."})
	check(menu.is_open(), "open() reports the menu is up")
	check(menu.visible, "open() shows the menu")
	check(not paused, "opening the menu never pauses the tree")

	# --- save --------------------------------------------------------------
	buttons["save"].pressed.emit()
	check(FileAccess.file_exists(TEST_SAVE), "SAVE writes the warband to the autoload's path")
	check(_saved.size() == 1, "SAVE emits `saved` exactly once")
	check(_saved.size() == 1 and _saved[0] == TEST_SAVE,
		"`saved` carries the real file path")
	check(not menu.status_text().is_empty(), "SAVE sets a status line")
	check(not buttons["load"].disabled, "LOAD enables once a save file exists")

	# --- settings page -----------------------------------------------------
	buttons["settings"].pressed.emit()
	check(menu.page() == "sound", "SETTINGS opens the sound page")
	check(menu.sound_page != null and menu.sound_page.visible,
		"the shared sound page is the settings page")
	check(menu.display_button != null
			and str(menu.display_button.text).begins_with("DISPLAY:"),
		"the display row reports the window's mode")
	check(menu.back(), "BACK consumes the press on a sub-page")
	check(menu.page() == "menu", "BACK returns to the index")

	# --- close -------------------------------------------------------------
	menu.close()
	check(not menu.is_open(), "close() reports the menu is down")
	check(not menu.visible, "close() hides the menu")
	check(_resumed == 1, "close emits `resumed` once")
	check(not paused, "closing the menu never pauses the tree")

	# --- load without a file ----------------------------------------------
	_remove_save()
	menu.open()
	check(menu.is_open(), "the menu opens again")
	check(buttons["load"].disabled, "LOAD is disabled again without a file")
	buttons["load"].pressed.emit()
	check(_loads == 0, "a disabled LOAD row never asks for a load")

	# --- load with a file, and the leave rows ------------------------------
	buttons["save"].pressed.emit()
	check(FileAccess.file_exists(TEST_SAVE), "SAVE writes again")
	check(not buttons["load"].disabled, "LOAD enables on the written file")
	buttons["load"].pressed.emit()
	check(_loads == 1, "LOAD emits `load_requested`")
	buttons["exit"].pressed.emit()
	check(_exits == 1, "the exit row emits `exit_requested`")
	check(menu.page() == "menu", "the exit row leaves the menu open for the scene to decide")

	# --- the index state is clean on the next open -------------------------
	buttons["settings"].pressed.emit()
	check(menu.page() == "sound", "the menu returns to the sound page")
	menu.close()
	menu.open()
	check(menu.page() == "menu", "re-opening starts on the index, not the sliders")
	check(_resumed == 2, "every close emits `resumed`")
	check(not paused, "the tree was never paused across the whole run")

	menu.close()
	menu.queue_free()
	warband.save_path = original_path
	_remove_save()
	print("WARBAND_MENU_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
